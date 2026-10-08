import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pytorch_lite/pytorch_lite.dart';

import '../data/food_database.dart';
import '../data/models.dart';

enum ScanStatus { noFood, ambiguous, confident }

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
  });
  final String id, name, source, sourceUrl, unit, barcode;

  /// Energy, protein, carbohydrate, fat, fiber per 100 g or ml. Missing stays null.
  final List<double?> values;
  final bool estimated;
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
    servingGrams: 100,
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
  }) : _detector = detector ?? PytorchFoodDetector(),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _bundle = bundle ?? rootBundle;
  final FoodDetector _detector;
  final http.Client _client;
  final bool _ownsClient;
  final AssetBundle _bundle;
  Map<int, String>? _labels;
  Future<void>? _initializing;
  Future<void> _operations = Future.value();
  bool _closed = false;
  static final _requests = <String, List<DateTime>>{};
  static final _cache =
      <String, ({DateTime time, List<FoodNutrition> foods})>{};

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
