import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:pytorch_lite/pytorch_lite.dart';

import '../data/food_database.dart';
import '../data/models.dart';
import 'gemini_env.local.dart';

enum ScanStatus { noFood, ambiguous, confident }

enum PhotoAnalysisIssue { noFood, unclear }

class PhotoAnalysisException implements Exception {
  const PhotoAnalysisException(this.issue, this.message);
  final PhotoAnalysisIssue issue;
  final String message;

  @override
  String toString() => message;
}

class FoodPrediction {
  const FoodPrediction(this.index, this.name, this.confidence);
  final int index;
  final String name;
  final double confidence;
}

class FoodScanResult {
  const FoodScanResult(this.status, this.first, this.second);
  final ScanStatus status;
  final FoodPrediction first, second;
}

abstract interface class FoodDetector {
  Future<void> initialize(int classes);
  Future<List<double>> predict(Uint8List image);
  Future<void> dispose();
}

/// A screen owns this detector; inference and release are serialized by the service.
class PytorchFoodDetector implements FoodDetector {
  ClassificationModel? _model;
  static bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  @override
  Future<void> initialize(int classes) async {
    if (!supported) {
      throw UnsupportedError(
        'On-device recognition is available on Android and iOS. You can type your meal on this device.',
      );
    }
    // JSON is not supported by the plugin's labelPath reader. Parse it ourselves.
    _model = await PytorchLite.loadClassificationModel(
      'assets/models/food_edge_detector_500.pt',
      224,
      224,
      classes,
    );
  }

  @override
  Future<List<double>> predict(Uint8List image) async {
    final logits = await _model!.getImagePredictionList(image);
    if (logits.isEmpty || logits.any((n) => !n.isFinite)) {
      throw const FormatException('The model returned invalid scores.');
    }
    // Stable softmax avoids overflow in large logits.
    final max = logits.reduce(math.max);
    final exp = logits.map((n) => math.exp(n - max)).toList();
    final sum = exp.fold<double>(0, (a, b) => a + b);
    return exp.map((n) => n / sum).toList();
  }

  @override
  Future<void> dispose() async {
    final model = _model;
    _model = null;
    await model?.dispose();
  }
}

class DetectedPlateItem {
  const DetectedPlateItem({
    required this.name,
    this.portion = '1 serving',
    required this.grams,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
    required this.fiberGrams,
  });

  final String name;
  final String portion;
  final double grams;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
  final double fiberGrams;
}

class FoodNutrition {
  const FoodNutrition({
    required this.id,
    required this.name,
    required this.source,
    required this.sourceUrl,
    required this.values,
    this.unit = 'g',
    this.barcode = '',
    this.estimated = false,
    this.servingGrams = 100,
    this.details = '',
    this.plateItems = const [],
  });
  final String id, name, source, sourceUrl, unit, barcode;

  /// Energy, protein, carbohydrate, fat, fiber per 100 g or ml. Missing stays null.
  final List<double?> values;
  final bool estimated;
  final double servingGrams;
  final String details;
  final List<DetectedPlateItem> plateItems;
  bool get complete => values.take(4).every((n) => n != null);
  Food toFood(List<double?> completed) => Food(
    id: id,
    name: name,
    aliases: const [],
    per100g: Nutrients(
      completed[0]!,
      completed[1]!,
      completed[2]!,
      completed[3]!,
      completed[4],
    ),
    servingGrams: servingGrams,
    unit: unit,
    nutritionBasisUnit: unit,
    source: source,
    sourceUrl: sourceUrl,
    barcode: barcode,
  );
}

class FoodSearchResults {
  const FoodSearchResults(this.foods, this.unavailableSources);
  final List<FoodNutrition> foods;
  final List<String> unavailableSources;
}

class FoodAIService {
  FoodAIService({
    FoodDetector? detector,
    http.Client? client,
    AssetBundle? bundle,
    String? geminiApiKey,
    String? geminiModel,
    String? geminiFallbackModel,
  }) : _detector = detector ?? PytorchFoodDetector(),
       _client = client ?? _sharedClient,
       _ownsClient = false,
       _bundle = bundle ?? rootBundle,
       _geminiApiKey = _resolveGeminiApiKey(geminiApiKey),
       _geminiModel =
           geminiModel ??
           const String.fromEnvironment(
             'GEMINI_MODEL',
             defaultValue: localGeminiModel,
           ),
       _geminiFallbackModel =
           geminiFallbackModel ??
           const String.fromEnvironment(
             'GEMINI_FALLBACK_MODEL',
             defaultValue: localGeminiFallbackModel,
           );

  static String _resolveGeminiApiKey(String? explicit) {
    if (explicit != null) return explicit;
    const defined = String.fromEnvironment('GEMINI_API_KEY');
    if (defined.trim().isNotEmpty) return defined;
    if (const bool.fromEnvironment('GEMINI_LIVE_TEST')) {
      return localGeminiApiKey;
    }
    try {
      final binding = WidgetsBinding.instance.runtimeType.toString();
      if (!binding.contains('Test')) return localGeminiApiKey;
    } catch (_) {}
    return '';
  }
  final FoodDetector _detector;
  final http.Client _client;
  final bool _ownsClient;
  final AssetBundle _bundle;
  final String _geminiApiKey;
  final String _geminiModel;
  final String _geminiFallbackModel;
  Map<int, String>? _labels;
  Future<void>? _initializing;
  Future<void> _operations = Future.value();
  bool _closed = false;
  static final http.Client _sharedClient = http.Client();
  static DateTime? _lastWarmUp;
  static final _requests = <String, List<DateTime>>{};
  static final _cache =
      <String, ({DateTime time, List<FoodNutrition> foods})>{};
  static final _photoCache =
      <String, ({DateTime time, Future<FoodNutrition> future})>{};

  bool get geminiConfigured => _geminiApiKey.trim().isNotEmpty;

  /// Pre-warms DNS + TLS routing to Google's Generative Language API
  /// using a short-lived client so no idle socket is left behind to be
  /// aborted by Android (`errno = 103`) when the Gallery picker opens.
  void warmUpConnection() {
    if (!geminiConfigured) return;
    if (_client.runtimeType.toString() == 'MockClient') return;
    final now = DateTime.now();
    if (_lastWarmUp != null &&
        now.difference(_lastWarmUp!) < const Duration(seconds: 45)) {
      return;
    }
    _lastWarmUp = now;
    final warmClient = http.Client();
    unawaited(
      warmClient
          .head(Uri.https('generativelanguage.googleapis.com', '/'))
          .timeout(const Duration(seconds: 4))
          .then<void>((_) {}, onError: (_) {})
          .whenComplete(warmClient.close),
    );
  }

  static String _photoSignature(Uint8List bytes) {
    final len = bytes.length;
    if (len == 0) return '0';
    final a = bytes[0];
    final b = bytes[len ~/ 3];
    final c = bytes[(len * 2) ~/ 3];
    final d = bytes[len - 1];
    return '$len:$a:$b:$c:$d';
  }

  /// Identifies a complete visible meal and returns editable nutrition per
  /// 100 g plus Gemini's estimated photographed serving size.
  Future<FoodNutrition> analyzeMealPhoto(Uint8List image) {
    if (_closed) return Future.error(StateError('Scanner closed'));
    if (!geminiConfigured) {
      return Future.error(
        StateError(
          'Kayleo photo analysis is not available right now.',
        ),
      );
    }
    if (image.isEmpty || image.length > 10 * 1024 * 1024) {
      return Future.error(
        const FormatException('Choose an image under 10 MB.'),
      );
    }
    final isMockClient = _client.runtimeType.toString() == 'MockClient';
    if (!isMockClient) {
      final key = _photoSignature(image);
      final cached = _photoCache[key];
      if (cached != null &&
          DateTime.now().difference(cached.time) <
              const Duration(minutes: 2)) {
        return cached.future;
      }
      final future = _analyzeMealPhotoImpl(image, isMockClient: false);
      _photoCache[key] = (time: DateTime.now(), future: future);
      future.catchError((_) {
        _photoCache.remove(key);
        return const FoodNutrition(
          id: '',
          name: '',
          source: '',
          sourceUrl: '',
          values: [],
        );
      });
      return future;
    }
    return _analyzeMealPhotoImpl(image, isMockClient: true);
  }

  Future<FoodNutrition> _analyzeMealPhotoImpl(
    Uint8List rawImage, {
    required bool isMockClient,
  }) async {
    final image = !isMockClient && rawImage.length > 95 * 1024
        ? await _downscaleFast(rawImage)
        : rawImage;
    final mimeType = _imageMimeType(image);
    final encodedImage = base64Encode(image);
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/interactions',
    );
    final schema = {
      'type': 'object',
      'additionalProperties': false,
      'required': [
        'classification',
        'mealName',
        'items',
        'confidence',
        'assumptions',
      ],
      'properties': {
        'classification': {
          'type': 'string',
          'enum': ['food', 'unclear', 'not_food'],
          'description': 'food if any edible food or drink is visible; unclear only when the image cannot be judged; not_food only when no edible item is visible.',
        },
        'mealName': {
          'type': 'string',
          'description': 'A short natural name for the complete visible meal.',
        },
        'items': {
          'type': 'array',
          'minItems': 0,
          'maxItems': 8,
          'description': 'Every distinct visible edible component. Split mixed plates into useful components but keep inseparable dishes together.',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'required': [
              'name',
              'portion',
              'grams',
              'calories',
              'proteinGrams',
              'carbsGrams',
              'fatGrams',
              'fiberGrams',
            ],
            'properties': {
              'name': {
                'type': 'string',
                'description': 'Specific visible food or drink name.',
              },
              'portion': {
                'type': 'string',
                'description': 'Plain-language visible portion, such as 1 cup or 2 pieces.',
              },
              'grams': {
                'type': 'number',
                'minimum': 1,
                'maximum': 3000,
                'description': 'Estimated edible weight of this visible item.',
              },
              'calories': {
                'type': 'number',
                'minimum': 0,
                'maximum': 5000,
                'description':
                    'Estimated kcal for this item and portion, not per 100 g.',
              },
              'proteinGrams': {'type': 'number', 'minimum': 0, 'maximum': 500},
              'carbsGrams': {'type': 'number', 'minimum': 0, 'maximum': 1000},
              'fatGrams': {'type': 'number', 'minimum': 0, 'maximum': 500},
              'fiberGrams': {'type': 'number', 'minimum': 0, 'maximum': 200},
            },
          },
        },
        'confidence': {
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
          'description': 'Confidence that the foods and visible portions were identified correctly.',
        },
        'assumptions': {
          'type': 'string',
          'description': 'One short note about uncertain cooking method, ingredients, scale, or portion.',
        },
      },
    };
    final request = <String, dynamic>{
      'model': _geminiModel,
      'input': [
        {
          'type': 'text',
          'text':
              'Act as a careful meal-photo estimator for a calorie diary. '
              'Look across the whole image before deciding. If any edible food '
              'or drink is visible, classification must be food, even when the '
              'dish, portion, or preparation is uncertain. Recognize regional '
              'foods, including South Asian and Nepali meals, by their most likely '
              'common name. Estimate each visible item separately, including oils '
              'and sauces only when visually plausible. Nutrition is for each '
              'photographed portion, not per 100 g. Do not invent hidden sides or '
              'ingredients. Use unclear only for a severely blurred, dark, blocked, '
              'or distant image. Use not_food only when no edible item is visible. '
              'The user will review every estimate before saving.',
        },
        {'type': 'image', 'data': encodedImage, 'mime_type': mimeType},
      ],
      'response_format': {
        'type': 'text',
        'mime_type': 'application/json',
        'schema': schema,
      },
    };
    Future<http.Response> send(String model) {
      request['model'] = model;
      return _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _geminiApiKey,
            },
            body: jsonEncode(request),
          )
          .timeout(const Duration(seconds: 10));
    }

    const fastLivePrompt =
        'Food photo estimator. If any edible food or drink is visible, '
        'classification="food" (use "unclear" only if unreadable, "not_food" '
        'only if no food/drink). Recognize regional, South Asian, and Nepali '
        'dishes. List 1-4 visible items on the plate separately with portion '
        '(e.g. "2 pieces", "1 bowl", "1.5 cups") and portion nutrition (not per 100g). '
        'Keep text concise (<5 words). Return compact single-line JSON: '
        '{"classification":"food","mealName":"...","items":[{"name":"...","portion":"1 bowl","grams":250,"calories":320,"proteinGrams":14,"carbsGrams":45,"fatGrams":8,"fiberGrams":5}],"confidence":0.9,"assumptions":"..."}';

    Future<http.Response> sendLegacy(
      String model, {
      Duration timeout = const Duration(seconds: 12),
      http.Client? overrideClient,
    }) {
      final activeClient = overrideClient ?? _client;
      return activeClient
          .post(
            Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/$model:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _geminiApiKey,
              if (!isMockClient) 'Connection': 'close',
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text': isMockClient
                          ? (request['input'] as List).first['text']
                          : fastLivePrompt,
                    },
                    {
                      'inlineData': {
                        'mimeType': mimeType,
                        'data': encodedImage,
                      },
                    },
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.1,
                if (model.startsWith('gemini-3')) ...{
                  'mediaResolution': 'MEDIA_RESOLUTION_LOW',
                  'thinkingConfig': {'thinkingLevel': 'MINIMAL'},
                },
                'responseMimeType': 'application/json',
                if (isMockClient) 'responseJsonSchema': schema,
              },
            }),
          )
          .timeout(timeout);
    }

    var usedModel = _geminiModel;
    var usedLegacyApi = !isMockClient;
    late http.Response response;
    if (isMockClient) {
      try {
        try {
          response = await send(usedModel);
        } on TimeoutException {
          usedLegacyApi = true;
          response = await sendLegacy(usedModel);
        }
        if (response.statusCode == 429 || response.statusCode >= 500) {
          usedLegacyApi = true;
          response = await sendLegacy(usedModel);
        }
        if ((response.statusCode == 429 || response.statusCode >= 500) &&
            _geminiFallbackModel.isNotEmpty &&
            _geminiFallbackModel != usedModel) {
          usedModel = _geminiFallbackModel;
          usedLegacyApi = true;
          response = await sendLegacy(usedModel);
        }
      } on TimeoutException {
        throw TimeoutException(
          'Kayleo took too long to read this photo. Try again.',
        );
      } catch (e) {
        final raw = e.toString().toLowerCase();
        if (raw.contains('socketexception') ||
            raw.contains('clientexception') ||
            raw.contains('connection abort') ||
            raw.contains('failed host lookup')) {
          throw StateError(
            'Kayleo couldn’t reach the network right now. Check your internet connection and try again.',
          );
        }
        rethrow;
      }
    } else {
      final primaryModel =
          (_geminiModel.isNotEmpty &&
              _geminiModel != 'gemini-3.8-flash' &&
              _geminiModel != 'gemini-3.6-flash' &&
              _geminiModel != 'gemini-3-flash-preview')
          ? _geminiModel
          : 'gemini-3.1-flash-lite';
      final candidates = <String>[
        primaryModel,
        'gemini-3.1-flash-lite',
        'gemini-3.1-flash-lite',
        'gemini-3.1-flash-lite',
      ];
      const retryDelays = <Duration>[
        Duration(milliseconds: 450),
        Duration(milliseconds: 900),
        Duration(milliseconds: 1500),
      ];
      http.Response? lastResponse;
      Object? lastError;
      for (var attempt = 0; attempt < candidates.length; attempt++) {
        final candidate = candidates[attempt];
        usedModel = candidate;
        final freshClient = http.Client();
        try {
          final res = await sendLegacy(
            candidate,
            overrideClient: freshClient,
          );
          lastResponse = res;
          if (res.statusCode >= 200 && res.statusCode < 300) {
            break;
          }
          if (res.statusCode == 401 || res.statusCode == 403) {
            break;
          }
        } on TimeoutException catch (e) {
          lastError = e;
        } catch (e) {
          lastError = e;
        } finally {
          freshClient.close();
        }
        if (attempt < retryDelays.length) {
          await Future<void>.delayed(retryDelays[attempt]);
        }
      }
      if (lastResponse == null) {
        if (lastError is TimeoutException) {
          throw TimeoutException(
            'Kayleo took too long to read this photo. Try again.',
          );
        }
        throw StateError(
          'Kayleo couldn’t reach the network right now. Check your internet connection and try again.',
        );
      }
      response = lastResponse;
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError(
        'Kayleo photo analysis is temporarily unavailable. Please try again shortly.',
      );
    }
    if (response.statusCode == 429) {
      throw StateError(
        'Kayleo is busy right now. Try again in a moment.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = '';
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body is Map && body['error'] is Map) {
          detail = (body['error'] as Map)['message']?.toString().trim() ?? '';
        }
      } catch (_) {
        // Keep the stable status-only fallback for non-JSON error pages.
      }
      final cleanDetail = detail.replaceAll(
        RegExp(r'\bgemini[-a-z0-9.]*\b', caseSensitive: false),
        'Kayleo',
      );
      throw StateError(
        cleanDetail.isEmpty
            ? 'Kayleo couldn’t analyze this photo (${response.statusCode}).'
            : 'Kayleo couldn’t analyze this photo: $cleanDetail',
      );
    }
    if (response.bodyBytes.length > 1024 * 1024) {
      throw const FormatException(
        'Kayleo returned an unexpectedly large response.',
      );
    }
    final envelope = jsonDecode(utf8.decode(response.bodyBytes));
    if (envelope is! Map) {
      throw const FormatException('Kayleo couldn’t read this photo clearly.');
    }
    final interaction = envelope['interaction'] is Map
        ? envelope['interaction'] as Map
        : envelope;
    Object? text = interaction['output_text'] ?? interaction['outputText'];
    if (usedLegacyApi) {
      final candidates = envelope['candidates'];
      final content = candidates is List &&
              candidates.isNotEmpty &&
              candidates.first is Map
          ? (candidates.first as Map)['content']
          : null;
      final parts = content is Map ? content['parts'] : null;
      if (parts is List) {
        text = parts
            .whereType<Map>()
            .map((part) => part['text'])
            .whereType<String>()
            .join();
      }
    }
    if (text is! String) {
      throw const FormatException('Kayleo couldn’t read this photo clearly.');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Kayleo couldn’t estimate this meal.');
    }
    final data = Map<String, dynamic>.from(decoded);
    final classification = data['classification']?.toString();
    if (classification == 'not_food') {
      throw const PhotoAnalysisException(
        PhotoAnalysisIssue.noFood,
        'We couldn’t find a visible food or drink in this photo.',
      );
    }
    if (classification != 'food') {
      throw const PhotoAnalysisException(
        PhotoAnalysisIssue.unclear,
        'The photo is too unclear to estimate confidently.',
      );
    }
    final name = data['mealName']?.toString().trim() ?? '';
    final confidence = _number(data['confidence'], 1);
    final rawItems = data['items'];
    if (name.length < 2 ||
        name.length > 100 ||
        rawItems is! List ||
        rawItems.isEmpty) {
      throw const FormatException('Kayleo couldn’t estimate the full nutrition for this meal.');
    }
    var serving = 0.0,
        calories = 0.0,
        protein = 0.0,
        carbs = 0.0,
        fat = 0.0,
        fiber = 0.0;
    final items = <String>[];
    final plateItems = <DetectedPlateItem>[];
    for (final raw in rawItems.take(8)) {
      if (raw is! Map) throw const FormatException('Kayleo couldn’t read one of the food items.');
      final item = Map<String, dynamic>.from(raw);
      final itemName = item['name']?.toString().trim() ?? '';
      final portion = item['portion']?.toString().trim() ?? '';
      final itemGrams = _number(item['grams'], 3000);
      final itemCalories = _number(item['calories'], 5000);
      final itemProtein = _number(item['proteinGrams'], 500);
      final itemCarbs = _number(item['carbsGrams'], 1000);
      final itemFat = _number(item['fatGrams'], 500);
      final itemFiber = _number(item['fiberGrams'], 200);
      if (itemName.isEmpty ||
          itemGrams == null ||
          itemCalories == null ||
          itemProtein == null ||
          itemCarbs == null ||
          itemFat == null ||
          itemFiber == null) {
        throw const FormatException('Kayleo returned incomplete food details.');
      }
      serving += itemGrams;
      calories += itemCalories;
      protein += itemProtein;
      carbs += itemCarbs;
      fat += itemFat;
      fiber += itemFiber;
      items.add(portion.isEmpty ? itemName : '$itemName ($portion)');
      plateItems.add(
        DetectedPlateItem(
          name: itemName,
          portion: portion.isEmpty ? '1 serving' : portion,
          grams: itemGrams,
          calories: itemCalories,
          proteinGrams: itemProtein,
          carbsGrams: itemCarbs,
          fatGrams: itemFat,
          fiberGrams: itemFiber,
        ),
      );
    }
    if (serving < 1 || calories <= 0) {
      throw const FormatException('Kayleo couldn’t estimate calories for this meal.');
    }
    final factor = 100 / serving;
    final notes = data['assumptions']?.toString().trim() ?? '';
    final details = [
      if (items.isNotEmpty) 'On your plate: ${items.join(', ')}',
      if (notes.isNotEmpty) notes,
      if (confidence != null)
        'Confidence: ${(confidence * 100).round()}%',
    ].join(' · ');
    return FoodNutrition(
      id: 'kayleo:${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      source: 'Kayleo Vision estimate · review before logging',
      sourceUrl: '',
      values: [
        calories * factor,
        protein * factor,
        carbs * factor,
        fat * factor,
        fiber * factor,
      ],
      estimated: true,
      servingGrams: serving,
      details: details,
      plateItems: plateItems,
    );
  }

  static String _imageMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'image/webp';
    }
    return 'image/jpeg';
  }


  /// Search both providers independently so an outage cannot hide other results.
  Future<FoodSearchResults> searchAll(String query) async {
    query = query.trim();
    if (query.length < 2 || query.length > 100) {
      throw const FormatException('Enter a food name of 2–100 characters.');
    }
    final results = <FoodNutrition>[];
    final unavailable = <String>[];
    Future<void> search(
      String source,
      Future<List<FoodNutrition>> Function() run,
    ) async {
      try {
        results.addAll(await run());
      } catch (_) {
        unavailable.add(source);
      }
    }

    await Future.wait([
      search(
        'Open Food Facts',
        () => fetchNutrition(query, localFallback: false),
      ),
      search('USDA FoodData Central', () => searchUsda(query)),
    ]);
    for (final food in foods) {
      if (food.aliases.any(
        (alias) => alias.toLowerCase() == query.toLowerCase(),
      )) {
        final n = food.per100g;
        results.add(
          FoodNutrition(
            id: food.id,
            name: food.name,
            source: food.source,
            sourceUrl: food.sourceUrl,
            values: [n.calories, n.protein, n.carbs, n.fat, n.fiber],
            estimated: true,
          ),
        );
      }
    }
    final unique = {for (final food in results) food.id: food}.values.toList();
    final tokens = query.toLowerCase().split(RegExp(r'\s+'));
    int score(FoodNutrition food) =>
        (food.name.toLowerCase() == query.toLowerCase() ? 1000 : 0) +
        tokens
                .where((token) => food.name.toLowerCase().contains(token))
                .length *
            10 +
        (food.complete ? 1 : 0);
    unique.sort((a, b) {
      final rank = score(b).compareTo(score(a));
      return rank != 0 ? rank : a.name.compareTo(b.name);
    });
    return FoodSearchResults(unique, unavailable);
  }

  Future<void> initialize() {
    if (_closed) return Future.error(StateError('Scanner closed'));
    if (_detector is PytorchFoodDetector && !PytorchFoodDetector.supported) {
      return _detector.initialize(0);
    }
    return _initializing ??= () async {
      final raw = jsonDecode(
        await _bundle.loadString('assets/metadata/labels.json'),
      );
      if (raw is! Map || raw.length < 2) {
        throw const FormatException('Invalid labels.');
      }
      final labels = <int, String>{};
      for (final entry in raw.entries) {
        final index = int.tryParse(entry.key.toString());
        if (index == null ||
            entry.value is! String ||
            entry.value.toString().trim().isEmpty) {
          throw const FormatException('Invalid label entry.');
        }
        labels[index] = entry.value;
      }
      if (labels[0] != 'non_food' ||
          List.generate(
            labels.length,
            (i) => i,
          ).any((i) => !labels.containsKey(i))) {
        throw const FormatException(
          'Labels must be contiguous with non_food at index 0.',
        );
      }
      await _detector.initialize(labels.length);
      _labels = labels;
    }();
  }

  Future<FoodScanResult> scanMeal(Uint8List image) {
    final operation = _operations.then((_) async {
      if (_closed) throw StateError('Scanner closed');
      if (image.isEmpty || image.length > 10 * 1024 * 1024) {
        throw const FormatException('Choose an image under 10 MB.');
      }
      await initialize();
      final probabilities = await _detector.predict(image);
      if (probabilities.length != _labels!.length ||
          probabilities.any((p) => !p.isFinite || p < 0 || p > 1)) {
        throw const FormatException('Model output does not match the labels.');
      }
      final total = probabilities.fold<double>(0, (a, b) => a + b);
      if ((total - 1).abs() > .02) {
        throw const FormatException('Invalid model probabilities.');
      }
      final sorted = List.generate(probabilities.length, (i) => i)
        ..sort((a, b) => probabilities[b].compareTo(probabilities[a]));
      FoodPrediction prediction(int i) => FoodPrediction(
        i,
        _labels![i]!.replaceAll('_', ' '),
        probabilities[i],
      );
      final first = prediction(sorted[0]), second = prediction(sorted[1]);
      final status = first.index == 0 || first.confidence < .40
          ? ScanStatus.noFood
          : first.confidence < .70 || first.confidence - second.confidence < .20
          ? ScanStatus.ambiguous
          : ScanStatus.confident;
      return FoodScanResult(status, first, second);
    });
    _operations = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<Map<String, dynamic>> _get(Uri uri, String quota, int limit) async {
    if (_closed) throw StateError('Scanner closed');
    final now = DateTime.now();
    final requests = _requests.putIfAbsent(quota, () => [])
      ..removeWhere((d) => now.difference(d) > const Duration(minutes: 1));
    if (requests.length >= limit) {
      throw StateError('Please wait a minute before searching again.');
    }
    requests.add(now);
    final headers = {'Accept': 'application/json'};
    if (uri.host.contains('openfoodfacts')) {
      headers[kIsWeb
          ? 'X-User-Agent'
          : 'User-Agent'] = const String.fromEnvironment(
        'OFF_USER_AGENT',
        defaultValue: 'Kayleo/1.0 (food nutrition lookup)',
      );
    }
    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 429) {
      throw StateError('Food database rate limit reached. Try again later.');
    }
    if (response.statusCode != 200) {
      throw StateError('Food database unavailable (${response.statusCode}).');
    }
    if (response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const FormatException('Food response too large.');
    }
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(response.bodyBytes)),
    );
  }

  Future<List<FoodNutrition>> fetchNutrition(
    String name, {
    bool localFallback = true,
  }) async {
    final query = name.trim();
    if (query.length < 2 || query.length > 100) {
      throw const FormatException('Enter a food name of 2–100 characters.');
    }
    final key = 'off:${query.toLowerCase()}';
    final saved = _cache[key];
    if (saved != null &&
        DateTime.now().difference(saved.time) < const Duration(minutes: 10)) {
      return saved.foods;
    }
    try {
      final data = await _get(
        Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
          'search_terms': query,
          'search_simple': '1',
          'action': 'process',
          'json': '1',
          'page_size': '3',
          'fields': 'code,product_name,nutriments,serving_size',
        }),
        'off-search',
        10,
      );
      final result = (data['products'] as List? ?? [])
          .whereType<Map>()
          .map((p) => parseOff(Map<String, dynamic>.from(p)))
          .whereType<FoodNutrition>()
          .toList();
      if (_cache.length >= 60) _cache.remove(_cache.keys.first);
      _cache[key] = (time: DateTime.now(), foods: result);
      return result;
    } catch (_) {
      if (!localFallback) rethrow;
      final matches =
          foods
              .where(
                (f) => f.aliases.any(
                  (a) => RegExp(
                    '\\b${RegExp.escape(a)}\\b',
                    caseSensitive: false,
                  ).hasMatch(query),
                ),
              )
              .toList()
            ..sort((a, b) => b.name.length.compareTo(a.name.length));
      if (matches.isEmpty) rethrow;
      final f = matches.first, n = f.per100g;
      return [
        FoodNutrition(
          id: 'local:${f.id}',
          name: f.name,
          source: 'Local recipe estimate · offline fallback',
          sourceUrl: '',
          estimated: true,
          values: [n.calories, n.protein, n.carbs, n.fat, n.fiber],
        ),
      ];
    }
  }

  Future<List<FoodNutrition>> searchUsda(String name) async {
    final query = name.trim();
    if (query.length < 2 || query.length > 100) {
      throw const FormatException('Enter 2–100 characters.');
    }
    final data = await _get(
      Uri.https('api.nal.usda.gov', '/fdc/v1/foods/search', {
        'query': query,
        'pageSize': '5',
        'api_key': const String.fromEnvironment(
          'USDA_API_KEY',
          defaultValue: 'DEMO_KEY',
        ),
      }),
      'usda',
      10,
    );
    return (data['foods'] as List? ?? []).whereType<Map>().map((f) {
      final nutrients = <int, double?>{};
      for (final n in (f['foodNutrients'] as List? ?? []).whereType<Map>()) {
        final id = n['nutrientId'];
        final unit = n['unitName']?.toString().toLowerCase();
        if (id is int && (unit == 'g' || unit == 'kcal' || unit == 'kj')) {
          final energy = [1008, 2047, 2048].contains(id);
          if ((energy && unit != 'kcal' && unit != 'kj') ||
              (!energy && unit != 'g')) {
            continue;
          }
          final number = _number(
            n['value'],
            energy ? (unit == 'kj' ? 5020.8 : 1200) : 100,
          );
          nutrients[id] = unit == 'kj' && number != null
              ? number / 4.184
              : number;
        }
      }
      return FoodNutrition(
        id: 'usda:${f['fdcId']}',
        name: f['description']?.toString() ?? 'Food',
        source: 'USDA FoodData Central',
        sourceUrl:
            'https://fdc.nal.usda.gov/food-details/${f['fdcId']}/nutrients',
        values: [
          nutrients[1008] ?? nutrients[2048] ?? nutrients[2047],
          nutrients[1003],
          nutrients[1005],
          nutrients[1004],
          nutrients[1079],
        ],
      );
    }).toList();
  }

  Future<FoodNutrition?> lookupBarcode(String code) async {
    if (!RegExp(r'^\d{8,14}$').hasMatch(code.trim())) {
      throw const FormatException('Enter an 8–14 digit product barcode.');
    }
    final data = await _get(
      Uri.https(
        'world.openfoodfacts.org',
        '/api/v2/product/${code.trim()}.json',
        {'fields': 'code,product_name,nutriments,serving_size'},
      ),
      'off-barcode',
      15,
    );
    if (data['status'] != 1 || data['product'] is! Map) return null;
    return parseOff(
      Map<String, dynamic>.from(data['product']),
      barcode: code.trim(),
    );
  }

  static double? _number(Object? value, double max) {
    final n = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return n != null && n.isFinite && n >= 0 && n <= max ? n : null;
  }

  static FoodNutrition? parseOff(
    Map<String, dynamic> p, {
    String barcode = '',
  }) {
    final name = p['product_name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final n = p['nutriments'] is Map
        ? Map<String, dynamic>.from(p['nutriments'])
        : <String, dynamic>{};
    final code = p['code']?.toString() ?? barcode;
    final volume = RegExp(
      r'\bml\b|\bl\b',
      caseSensitive: false,
    ).hasMatch(p['serving_size']?.toString() ?? '');
    return FoodNutrition(
      id: 'off:${code.isEmpty ? Uri.encodeComponent(name) : code}',
      name: name,
      source: 'Open Food Facts · community product label',
      sourceUrl: code.isEmpty
          ? 'https://world.openfoodfacts.org'
          : 'https://world.openfoodfacts.org/product/$code',
      barcode: code,
      unit: volume ? 'ml' : 'g',
      values: [
        _number(n['energy-kcal_100g'], 1200) ??
            (_number(n['energy_100g'], 5020.8) == null
                ? null
                : _number(n['energy_100g'], 5020.8)! /
                      (n['energy_unit']?.toString().toLowerCase() == 'kcal'
                          ? 1
                          : 4.184)),
        _number(n['proteins_100g'], 100),
        _number(n['carbohydrates_100g'], 100),
        _number(n['fat_100g'], 100),
        _number(n['fiber_100g'], 100),
      ],
    );
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _operations;
    try {
      await _initializing;
    } catch (_) {
      /* A failed load has no model to release. */
    }
    await _detector.dispose();
    if (_ownsClient) _client.close();
  }
}

Future<Uint8List> _downscaleFast(Uint8List raw) async {
  try {
    final codec = await ui.instantiateImageCodec(raw, targetWidth: 384);
    final frame = await codec.getNextFrame();
    final uiImg = frame.image;
    final w = uiImg.width;
    final h = uiImg.height;
    final rgba = await uiImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    uiImg.dispose();
    codec.dispose();
    if (rgba != null) {
      return await compute(_encodeRgbaToJpg, (
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        w,
        h,
      ));
    }
  } catch (_) {}
  return compute(_downscaleForGemini, raw);
}

Uint8List _encodeRgbaToJpg((Uint8List, int, int) input) {
  final (bytes, w, h) = input;
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: bytes.buffer,
    bytesOffset: bytes.offsetInBytes,
    numChannels: 4,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 72));
}

Uint8List _downscaleForGemini(Uint8List raw) {
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    var image = img.bakeOrientation(decoded);
    const maxSide = 384;
    if (image.width > maxSide || image.height > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: maxSide,
              interpolation: img.Interpolation.nearest,
            )
          : img.copyResize(
              image,
              height: maxSide,
              interpolation: img.Interpolation.nearest,
            );
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 72));
  } catch (_) {
    return raw;
  }
}
