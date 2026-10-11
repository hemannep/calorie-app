import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/app_state.dart';
import '../core/meal_engine.dart';
import '../core/meal_lookup.dart';
import '../services/food_ai_service.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../data/food_database.dart';
import 'meal_camera.dart';
import 'capture_input_layout.dart';
import 'portion_editor.dart';
import 'meal_food_match.dart';
import '../screens/food_camera_screen.dart';
import '../screens/food_lookup_screen.dart';

Future<void> showLogger(
  BuildContext context,
  AppState state, {
  String mode = 'Photo',
  Meal? meal,
  DateTime? initialDate,
  bool openCamera = false,
}) async {
  if (meal == null &&
      ((mode == 'Photo' && openCamera) ||
          mode == 'Text' ||
          mode == 'Voice' ||
          mode == 'Barcode')) {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FoodCameraScreen(
          state: state,
          initialMode: mode,
          initialDate: initialDate,
        ),
        fullscreenDialog: true,
      ),
    );
    if (context.mounted && result == 'barcode') {
      await showLogger(context, state, mode: 'Barcode');
    } else if (context.mounted && (result == 'manual' || result == 'voice')) {
      await showLogger(
        context,
        state,
        mode: result == 'voice' ? 'Voice' : 'Text',
      );
    }
    return;
  }
  if (meal == null && (mode == 'Barcode' || mode == 'Search')) {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            FoodLookupScreen(state: state, barcode: mode == 'Barcode'),
      ),
    );
    return;
  }
  final flow = LoggingFlow(
    state: state,
    initialMode: mode,
    existing: meal,
    initialDate: initialDate,
    openCamera: openCamera || (mode == 'Voice' && meal == null),
  );
  if (meal == null && ((openCamera && mode == 'Photo') || mode == 'Voice')) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: flow,
        ),
      ),
    );
  } else {
    await openSheet<void>(context, flow);
  }
}

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageTitle(
        'Kayleo',
        'What’s on your plate?',
        'Snap a meal, type it, or tell Kayleo.',
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final photo = ClipRRect(
            borderRadius: BorderRadius.circular(KayleoRadius.large),
            child: SizedBox(
              height: 390,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const FoodPhoto(image: 'bowl', radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB0203528)],
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 24,
                    left: 24,
                    child: Tag(
                      'SAMPLE PLATE',
                      color: Colors.white,
                      icon: Icons.camera_alt_outlined,
                    ),
                  ),
                  Positioned(
                    bottom: 28,
                    left: 28,
                    right: 28,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Snap a meal',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.8,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () =>
                              showLogger(context, state, openCamera: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: lime,
                            foregroundColor: forest,
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 19),
                          label: const Text('Log a meal with a photo'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
          final actions = Column(
            children: [
              _CaptureAction(
                icon: Icons.edit_note_rounded,
                title: 'Type it',
                subtitle: '“Two eggs and avocado toast for breakfast.”',
                onTap: () => showLogger(context, state, mode: 'Text'),
              ),
              const SizedBox(height: KayleoSpacing.lg),
              _CaptureAction(
                icon: Icons.mic_none_rounded,
                title: 'Tell Kayleo',
                subtitle: 'Your words, turned into a meal to review.',
                onTap: () => showLogger(context, state, mode: 'Voice'),
              ),
              const SizedBox(height: KayleoSpacing.lg),
              _CaptureAction(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan a label',
                subtitle: 'Scan a product or enter its barcode.',
                onTap: () => showLogger(context, state, mode: 'Barcode'),
              ),
              const SizedBox(height: KayleoSpacing.lg),
              _CaptureAction(
                icon: Icons.add_rounded,
                title: 'Add it yourself',
                subtitle: 'Search a food or enter calories and macros.',
                onTap: () => showLogger(context, state, mode: 'Manual'),
              ),
            ],
          );
          return constraints.maxWidth > 700
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: photo),
                    const SizedBox(width: KayleoSpacing.xl),
                    Expanded(flex: 2, child: actions),
                  ],
                )
              : Column(
                  children: [
                    photo,
                    const SizedBox(height: KayleoSpacing.page),
                    actions,
                  ],
                );
        },
      ),
      const SizedBox(height: KayleoSpacing.xl),
      Panel(
        color: context.kayleoSurfaces.soft,
        border: false,
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: context.kayleoPrimary),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'You’re in control of every estimate. Review portions, ingredients, and preparation before saving.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.kayleoText,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _CaptureAction extends StatelessWidget {
  const _CaptureAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Panel(
      padding: 18,
      child: Row(
        children: [
          IconBox(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: KayleoSpacing.xs),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: context.kayleoMuted),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            size: 17,
            color: context.kayleoPrimary,
          ),
        ],
      ),
    ),
  );
}

class LoggingFlow extends StatefulWidget {
  const LoggingFlow({
    super.key,
    required this.state,
    this.initialMode = 'Photo',
    this.existing,
    this.initialDate,
    this.openCamera = false,
    this.foodService,
    this.captureSurface = false,
    this.draftController,
  });
  final AppState state;
  final String initialMode;
  final Meal? existing;
  final DateTime? initialDate;
  final bool openCamera;
  final FoodAIService? foodService;
  final bool captureSurface;
  final TextEditingController? draftController;
  @override
  State<LoggingFlow> createState() => _LoggingFlowState();
}

class _LoggingFlowState extends State<LoggingFlow> {
  late String mode;
  int stage = 0, questionIndex = 0;
  int? answer;
  bool busy = false, saveUsual = false, listening = false;
  bool cameraOpen = false;
  int analysisGeneration = 0;
  MealAnalysis? analysis;
  Meal? meal;
  Uint8List? photo;
  String sample = 'Chicken bowl';
  String? error;
  late final description = widget.draftController ?? TextEditingController();
  final title = TextEditingController();
  final notes = TextEditingController();
  final speech = SpeechToText();
  late final foodService = widget.foodService ?? FoodAIService();
  List<String> missingFoods = [];
  ColorScheme get _scheme => Theme.of(context).colorScheme;
  Color get _secondary => _scheme.onSurfaceVariant;
  KayleoSurfaces get _surfaces =>
      Theme.of(context).extension<KayleoSurfaces>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? KayleoSurfaces.dark
          : KayleoSurfaces.light);

  DateTime get defaultTime {
    final now = DateTime.now();
    final day = widget.initialDate ?? now;
    return DateTime(day.year, day.month, day.day, now.hour, now.minute);
  }

  late final bool isEditing =
      widget.existing != null &&
      widget.state.meals.any((m) => m.id == widget.existing!.id);
  @override
  void initState() {
    super.initState();
    mode = widget.initialMode;
    cameraOpen =
        widget.openCamera && mode == 'Photo' && widget.existing == null;
    if (widget.existing != null) {
      meal = widget.existing!.copy();
      stage = 2;
      title.text = meal!.name;
      notes.text = meal!.notes;
    }
  }

  @override
  void dispose() {
    speech.cancel();
    if (widget.foodService == null) {
      foodService.dispose();
    }
    if (widget.draftController == null) description.dispose();
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  void openCamera() {
    setState(() {
      cameraOpen = true;
      error = null;
    });
  }

  void changeMode(String nextMode) {
    analysisGeneration++;
    speech.stop();
    setState(() {
      mode = nextMode;
      busy = false;
      error = null;
      listening = false;
      cameraOpen = false;
    });
  }

  Future<void> usePhoto(Uint8List bytes) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FoodCameraScreen(state: widget.state, initialPhoto: bytes),
      ),
    );
    if (!mounted) return;
    if (result == 'logged') {
      Navigator.pop(context);
      return;
    }
    if (result == 'manual') {
      changeMode('Text');
      return;
    }

    setState(() {
      photo = bytes;
      cameraOpen = false;
      error = null;
      description.clear();
    });
  }

  Future<void> pickPhoto() async {
    final returnToCamera = cameraOpen && widget.openCamera;
    setState(() => cameraOpen = false);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 75,
        requestFullMetadata: false,
      );
      if (!mounted) {
        return;
      }
      if (file == null) {
        if (returnToCamera) setState(() => cameraOpen = true);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) {
        return;
      }
      if (bytes.length > 2 * 1024 * 1024) {
        setState(
          () => error = 'Choose an image smaller than 2 MB so it can be saved on this device.',
        );
        return;
      }
      setState(() {
        photo = bytes;
        error = null;
        description.clear();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'We couldn’t open the photo library. Try a sample plate or use text instead.',
        );
      }
    }
  }

  Future<void> microphone() async {
    if (listening) {
      await speech.stop();
      if (mounted) {
        setState(() => listening = false);
      }
      return;
    }
    try {
      final available = await speech.initialize(
        onStatus: (status) {
          if (mounted && (status == 'done' || status == 'notListening')) {
            setState(() => listening = false);
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() {
              listening = false;
              error = 'Voice recognition isn’t available. Type your meal or try the voice example.';
            });
          }
        },
      );
      if (!mounted) {
        return;
      }
      if (!available) {
        setState(
          () => error = 'Voice recognition isn’t available on this device. You can type below or try the example.',
        );
        return;
      }
      setState(() {
        listening = true;
        error = null;
      });
      await speech.listen(
        onResult: (result) {
          if (mounted) {
            setState(() => description.text = result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          listening = false;
          error = 'Microphone unavailable. Try typing or the voice example.';
        });
      }
    }
  }

  Future<void> analyze() async {
    if (busy) {
      return;
    }
    final generation = ++analysisGeneration;
    if (mode == 'Barcode') {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FoodLookupScreen(state: widget.state, barcode: true),
        ),
      );
      if (!mounted) return;
      if (saved == true) Navigator.pop(context);
      return;
    }
    if (mode == 'Photo' && photo == null) {
      description.text = sample == 'Chicken bowl'
          ? 'chicken bowl'
          : sample == 'Rice & curry'
          ? 'rice and chicken curry'
          : '8 chicken momo';
    }
    if (description.text.trim().isEmpty) {
      setState(
        () => error = mode == 'Photo'
            ? 'Describe the foods in your photo to create an estimate.'
            : 'Tell us what you ate first.',
      );
      return;
    }
    await speech.stop();
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
      listening = false;
    });
    final text = description.text.toLowerCase();
    if (text.contains('same breakfast') || text.contains('my usual')) {
      Meal? remembered;
      if (text.contains('same breakfast')) {
        final matches = widget.state
            .mealsFor(defaultTime.subtract(const Duration(days: 1)))
            .where((m) => m.category == 'Breakfast');
        if (matches.isNotEmpty) {
          remembered = matches.first;
        }
      } else if (widget.state.templates.isNotEmpty) {
        final matches = widget.state.templates.where(
          (m) =>
              text.contains(m.name.toLowerCase()) ||
              m.name.toLowerCase().contains(
                text.replaceAll('my usual', '').trim(),
              ),
        );
        if (matches.isNotEmpty) {
          remembered = matches.first;
        }
      }
      if (remembered != null) {
        meal = remembered.copy(id: newId(), time: defaultTime);
        meal!.input = 'Meal memory';
        setState(() {
          title.text = meal!.name;
          notes.text = description.text;
          stage = 2;
          busy = false;
        });
        return;
      }
      setState(() {
        busy = false;
        error = 'No matching meal in your memory yet. Describe the foods or choose a saved meal.';
      });
      return;
    }
    try {
      final plan = MealLookupPlan.parse(
        description.text,
        now: defaultTime,
        input: mode == 'Photo'
            ? (photo == null ? 'Photo demo' : 'Photo + description')
            : mode,
      );
      missingFoods = [];
      for (final request in plan.requests) {
        final found = await foodService.searchAll(request.query);
        if (!mounted || generation != analysisGeneration) return;
        // Previously confirmed API records remain useful without connectivity.
        final saved = <String, FoodNutrition>{};
        for (final previous in [
          ...widget.state.meals,
          ...widget.state.templates,
        ]) {
          for (final item in previous.items) {
            final f = item.snapshot;
            if (f != null && f.name.toLowerCase().contains(request.query)) {
              final n = f.per100g;
              saved[f.id] = FoodNutrition(
                id: f.id,
                name: f.name,
                source: '${f.source} · saved on this device',
                sourceUrl: f.sourceUrl,
                unit: f.nutritionBasisUnit,
                barcode: f.barcode,
                values: [n.calories, n.protein, n.carbs, n.fat, n.fiber],
              );
            }
          }
        }
        final choices = {
          for (final f in saved.values) f.id: f,
          for (final f in found.foods) f.id: f,
        }.values.toList();
        if (choices.isEmpty) {
          missingFoods.add(
            '${request.query}${found.unavailableSources.isEmpty ? ' (no matching record)' : ' (databases unavailable)'}',
          );
          continue;
        }
        setState(() => busy = false);
        final item = await openSheet<MealItem>(
          context,
          MealFoodMatch(
            request: request,
            results: FoodSearchResults(choices, found.unavailableSources),
          ),
        );
        if (!mounted || generation != analysisGeneration) return;
        if (item == null) {
          setState(() => busy = false);
          return;
        }
        setState(() => busy = true);
        plan.analysis.meal.items.add(item);
      }
      analysis = plan.analysis;
      if (plan.requests.isNotEmpty && analysis!.meal.items.isNotEmpty) {
        analysis!.meal.name = analysis!.meal.items
            .map((i) => mealItemFood(i).name)
            .take(3)
            .join(' + ');
        analysis!.meal.assumptions += '\nDatabase matches and portions were selected by you. See each food’s source below.';
      }
      questionIndex = 0;
      answer = null;
    } catch (e) {
      if (mounted && generation == analysisGeneration) {
        setState(() {
          busy = false;
          error = e
              .toString()
              .replaceFirst('FormatException: ', '')
              .replaceFirst('Bad state: ', '');
        });
      }
      return;
    }
    if (!mounted || generation != analysisGeneration) return;
    meal = analysis!.meal;
    meal!.photo = photo;
    title.text = meal!.name;
    notes.text = meal!.notes;
    setState(() {
      busy = false;
      stage = analysis!.questions.isEmpty ? 2 : 1;
    });
  }

  Future<void> save() async {
    if (busy || meal == null) {
      return;
    }
    if (meal!.items.isEmpty && meal!.manual == null) {
      setState(() => error = 'Add a food or enter nutrition before saving.');
      return;
    }
    if (title.text.trim().isEmpty) {
      setState(() => error = 'Give your meal a name.');
      return;
    }
    setState(() => busy = true);
    meal!.name = title.text.trim();
    meal!.notes = notes.text.trim();
    try {
      await widget.state.saveMeal(meal!);
      if (saveUsual && widget.state.storageError == null) {
        await widget.state.saveTemplate(meal!);
      }
      if (widget.state.storageError != null) {
        throw StateError(widget.state.storageError!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e
              .toString()
              .replaceFirst('Bad state: ', '')
              .replaceFirst('FormatException: ', '');
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      busy = false;
      stage = 3;
    });
  }

  Future<void> addFood() async {
    final food = await openSheet<Food>(context, const FoodPicker());
    if (food != null && mounted) {
      setState(() {
        meal ??= Meal(
          id: newId(),
          name: food.name,
          time: defaultTime,
          category: MealEngine.categoryForHour(defaultTime.hour),
          items: [],
          input: 'Manual',
          image: food.image,
        );
        meal!.items.add(MealItem(foodId: food.id, grams: food.servingGrams));
        if (title.text.isEmpty) {
          title.text = food.name;
        }
        stage = 2;
        error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.captureSurface) return _captureSurface();
    if (widget.openCamera && cameraOpen && stage == 0) {
      return MealCamera(
        immersive: true,
        bottomInset: 0,
        onClose: () => Navigator.pop(context),
        onChoosePhoto: pickPhoto,
        onPhoto: usePhoto,
        onSelectMode: changeMode,
      );
    }
    if (stage == 0 && mode == 'Voice') return _voiceSurface();
    final titles = [
      'Log your meal',
      'One detail would improve this estimate',
      isEditing
          ? 'Edit your meal'
          : meal?.items.isNotEmpty == true && meal?.input != 'Manual'
          ? 'Kayleo sees'
          : 'Review your meal',
      'Meal added',
    ];
    final frame = SheetFrame(
      title: titles[stage],
      subtitle: stage == 0
          ? 'Choose what feels easiest.'
          : stage == 1
          ? 'Confirm this detail, then review your meal.'
          : stage == 2
          ? 'Review the estimate. You have the final say.'
          : 'Saved on this device.',
      onBack: stage == 1 || (stage == 2 && !isEditing)
          ? () => setState(() {
              stage = 0;
              error = null;
              questionIndex = 0;
              answer = null;
            })
          : null,
      footer: _footer(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stage == 0) _input(),
          if (stage == 1) _question(),
          if (stage == 2) _review(),
          if (stage == 3) _success(),
          if (error != null) ...[
            const SizedBox(height: KayleoSpacing.lg),
            Text(
              error!,
              style: const TextStyle(
                color: KayleoColors.error,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ],
        ],
      ),
    );
    if (!widget.openCamera) return frame;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: frame,
        ),
      ),
    );
  }

  Widget _captureSurface() => Theme(
    data: kayleoTheme(brightness: Brightness.dark),
    child: Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 24, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      color: Colors.white70,
                      icon: const Icon(Icons.close_rounded, size: 22),
                    ),
                    if (stage > 0 && stage < 3)
                      IconButton(
                        tooltip: 'Back to input',
                        onPressed: () => setState(() {
                          stage = 0;
                          error = null;
                        }),
                        color: Colors.white70,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    const Spacer(),
                    if (MediaQuery.viewInsetsOf(context).bottom > 0)
                      TextButton(
                        onPressed: () =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        child: const Text('Done'),
                      )
                    else
                      const Brand(light: true, size: 20),
                  ],
                ),
              ),
              Expanded(
                child: CaptureInputLayout(
                  footer: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        filledButtonTheme: FilledButtonThemeData(
                          style: FilledButton.styleFrom(
                            backgroundColor: lime,
                            foregroundColor: forest,
                            minimumSize: const Size(double.infinity, 52),
                            textStyle: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                      child: _footer() ?? const SizedBox.shrink(),
                    ),
                  ),
                  content: LayoutBuilder(
                    key: const Key('capture-editor-viewport'),
                    builder: (context, constraints) => SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 44).clamp(
                            0,
                            double.infinity,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (stage == 0) _captureEditor(),
                            if (stage == 1) _question(),
                            if (stage == 2) _review(),
                            if (stage == 3) _success(),
                            if (error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFF3C6B9),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _captureEditor() {
    final voice = mode == 'Voice';
    return Column(
      key: Key(voice ? 'capture-voice-composer' : 'capture-type-composer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: voice ? Alignment.center : Alignment.centerLeft,
          child: _CaptureEyebrow(
            icon: voice ? Icons.graphic_eq_rounded : Icons.auto_awesome_rounded,
            label: voice
                ? (listening ? 'LISTENING NOW' : 'VOICE ENTRY')
                : 'SMART ENTRY',
            active: listening,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          voice
              ? (listening ? 'Listening…' : 'Tell Kayleo')
              : 'What did you eat?',
          textAlign: voice ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          voice
              ? (listening
                    ? 'Speak naturally — your words appear below.'
                    : 'Tap and tell Kayleo what you ate')
              : 'Add the foods and portions you remember.',
          textAlign: voice ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
        if (voice) ...[
          Center(
            child: _VoiceControl(
              listening: listening,
              onTap: microphone,
              premium: true,
            ),
          ),
          const SizedBox(height: 24),
        ],
        _CaptureMealComposer(
          controller: description,
          voice: voice,
          listening: listening,
        ),
        if (!voice) ...[
          const SizedBox(height: 14),
          Text(
            'QUICK START',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .42),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in ['Two eggs and toast', 'Chicken rice bowl'])
                ActionChip(
                  label: Text(example),
                  avatar: const Icon(Icons.add_rounded, size: 14),
                  backgroundColor: Colors.white.withValues(alpha: .045),
                  side: BorderSide(color: Colors.white.withValues(alpha: .1)),
                  labelStyle: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => description.text = example),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _voiceSurface() => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: forest,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Theme(
      data: kayleoTheme(brightness: Brightness.dark),
      child: Material(
        color: forest,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 24, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        color: Colors.white,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Spacer(),
                      const Brand(light: true, size: 23),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.all(KayleoSpacing.xl),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 48).clamp(
                            0,
                            double.infinity,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              listening ? 'Listening…' : 'Tell Kayleo',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.8,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              listening
                                  ? 'Tell me what was on your plate.'
                                  : 'Tap and tell Kayleo what you ate',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 13,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 32),
                            _VoiceControl(
                              listening: listening,
                              onTap: microphone,
                            ),
                            const SizedBox(height: 30),
                            TextField(
                              key: const Key('meal-description'),
                              controller: description,
                              minLines: 2,
                              maxLines: 4,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Your words (you can edit them)',
                                hintText: 'For example: rice and chicken curry',
                                fillColor: Colors.white.withValues(alpha: .07),
                                labelStyle: const TextStyle(
                                  color: Color(0xCCFFFFFF),
                                ),
                                hintStyle: const TextStyle(
                                  color: Color(0x99FFFFFF),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'TRY SAYING',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0x99FFFFFF),
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final example in [
                                  'I had a veg burger and five ounces of fries',
                                  'Two eggs and avocado toast',
                                ])
                                  ActionChip(
                                    label: Text(
                                      example,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: .05,
                                    ),
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: .18,
                                      ),
                                    ),
                                    onPressed: () => setState(
                                      () => description.text = example,
                                    ),
                                  ),
                              ],
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFF3C6B9),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            const Text(
                              'Speech recognition uses your device. Review your words before continuing.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 10,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: _footer(),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final (label, nextMode) in [
                          ('Type', 'Text'),
                          ('Camera', 'Photo'),
                          ('Voice', 'Voice'),
                        ])
                          TextButton(
                            onPressed: nextMode == 'Voice'
                                ? null
                                : () {
                                    changeMode(nextMode);
                                    if (nextMode == 'Photo') openCamera();
                                  },
                            style: TextButton.styleFrom(
                              minimumSize: const Size(76, 44),
                              foregroundColor: Colors.white,
                              disabledForegroundColor: forest,
                              backgroundColor: nextMode == 'Voice'
                                  ? lime
                                  : Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _input() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (m, icon) in [
              ('Photo', Icons.camera_alt_outlined),
              ('Text', Icons.edit_note_rounded),
              ('Voice', Icons.mic_none_rounded),
              ('Barcode', Icons.qr_code_scanner_rounded),
              ('Manual', Icons.add_rounded),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15),
                      const SizedBox(width: 5),
                      Text(
                        m == 'Photo' ? 'Camera' : m,
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                  selected: mode == m,
                  showCheckmark: false,
                  selectedColor: lime,
                  labelStyle: TextStyle(
                    color: mode == m ? forest : _scheme.onSurface,
                  ),
                  side: BorderSide(color: _surfaces.border),
                  onSelected: (_) {
                    changeMode(m);
                    if (m == 'Barcode') analyze();
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: KayleoSpacing.card),
      if (mode == 'Photo') ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: cameraOpen
              ? MealCamera(
                  bottomInset: 0,
                  onClose: () => setState(() => cameraOpen = false),
                  onChoosePhoto: pickPhoto,
                  onPhoto: usePhoto,
                )
              : SizedBox(
                  height: 250,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (photo == null)
                        FoodPhoto(
                          image: sample == 'Chicken bowl'
                              ? 'bowl'
                              : sample == 'Rice & curry'
                              ? 'curry'
                              : 'momo',
                          radius: 0,
                        )
                      else
                        Image.memory(photo!, fit: BoxFit.cover),
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Tag(
                          photo == null
                              ? 'SAMPLE PLATE · PHOTO DEMO'
                              : 'YOUR PHOTO',
                          color: Colors.white,
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(42),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .8),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(
                                KayleoRadius.large,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 14,
                        right: 14,
                        child: IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: forest,
                          ),
                          key: const Key('sample-plate-camera'),
                          onPressed: openCamera,
                          tooltip: 'Take photo',
                          icon: Icon(Icons.camera_alt_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        if (!cameraOpen) ...[
          const SizedBox(height: KayleoSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickPhoto,
                  icon: Icon(Icons.photo_library_outlined, size: 16),
                  label: Text('Choose photo'),
                ),
              ),
              const SizedBox(width: KayleoSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: openCamera,
                  icon: Icon(Icons.camera_alt_outlined, size: 16),
                  label: Text('Take photo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: KayleoSpacing.lg),
          if (photo == null) ...[
            Text(
              'Try a sample meal',
              style: TextStyle(fontSize: 11, color: _secondary),
            ),
            const SizedBox(height: KayleoSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ['Chicken bowl', 'Rice & curry', 'Chicken momo']
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s, style: TextStyle(fontSize: 11)),
                      selected: sample == s,
                      selectedColor: _surfaces.soft,
                      side: BorderSide(color: _surfaces.border),
                      onSelected: (_) => setState(() => sample = s),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: KayleoSpacing.md),
            Text(
              'These sample plates use preset descriptions to demonstrate meal estimates. For your own photo, describe the food after capture.',
              style: TextStyle(color: _secondary, fontSize: 10, height: 1.6),
            ),
          ] else ...[
            Text(
              'What’s in your photo?',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Your description creates the estimate. Kayleo does not identify foods from this photo.',
              style: TextStyle(fontSize: 11, color: _secondary),
            ),
            const SizedBox(height: KayleoSpacing.md),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'For example: 1 cup of rice and home-style chicken curry',
              ),
            ),
          ],
        ],
      ],
      if (mode == 'Text') ...[
        TextField(
          key: const Key('meal-description'),
          controller: description,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Describe your meal',
            hintText: 'What did you eat?',
          ),
        ),
        const SizedBox(height: KayleoSpacing.lg),
        Text(
          'TRY AN EXAMPLE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: _secondary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final example in [
              'Rice and chicken curry',
              'Two eggs and avocado toast',
              '8 chicken momo',
            ])
              ActionChip(
                label: Text(example, style: TextStyle(fontSize: 10)),
                side: BorderSide(color: _surfaces.border),
                onPressed: () => setState(() => description.text = example),
              ),
          ],
        ),
      ],
      if (mode == 'Barcode') ...[
        _CaptureAction(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Scan a packaged food',
          subtitle: 'Use the camera or enter a barcode to review real product nutrition.',
          onTap: analyze,
        ),
      ],
      if (mode == 'Manual') ...[
        _CaptureAction(
          icon: Icons.search_rounded,
          title: 'Find a food',
          subtitle: 'Search basics, favorites, and regional meals.',
          onTap: addFood,
        ),
        const SizedBox(height: KayleoSpacing.lg),
        _CaptureAction(
          icon: Icons.edit_outlined,
          title: 'Enter calories & macros',
          subtitle: 'Use the nutrition label or your own recipe.',
          onTap: quickAdd,
        ),
      ],
    ],
  );

  Widget _question() {
    final q = analysis!.questions[questionIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FoodPhoto(
          image: meal!.image,
          meal: meal,
          height: 140,
          width: double.infinity,
        ),
        const SizedBox(height: KayleoSpacing.card),
        Tag(
          'DETAIL ${questionIndex + 1} OF ${analysis!.questions.length}',
          color: _surfaces.soft,
          textColor: _scheme.onSurface,
        ),
        const SizedBox(height: 18),
        Text(q.question, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: KayleoSpacing.md),
        Text(
          q.portion
              ? 'Choose a serving, or enter a measured amount and the share you ate.'
              : 'Hidden cooking oil can meaningfully change the estimate.',
          style: TextStyle(color: _secondary, fontSize: 12),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => setState(() => answer = i),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: answer == i ? _surfaces.soft : _surfaces.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: answer == i ? _scheme.primary : _surfaces.border,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        q.options[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      answer == i
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: answer == i ? _scheme.primary : _secondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (q.portion)
          OutlinedButton.icon(
            onPressed: () async {
              final item = meal!.items[q.itemIndex!];
              final portion = await editPortion(context, item);
              if (!mounted || portion == null) return;
              item.grams = consumedPortion(mealItemFood(item), portion);
              item.portion = portion;
              nextQuestion(custom: true);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Enter a custom amount'),
          ),
        TextButton(
          onPressed: () {
            answer = 0;
            nextQuestion();
          },
          child: Text('Not sure — use a standard serving'),
        ),
      ],
    );
  }

  void nextQuestion({bool custom = false}) {
    if (!custom && answer == null) {
      return;
    }
    if (!custom) {
      MealEngine.answer(meal!, analysis!.questions[questionIndex], answer!);
    }
    setState(() {
      answer = null;
      if (questionIndex + 1 < analysis!.questions.length) {
        questionIndex++;
      } else {
        stage = 2;
      }
    });
  }

  Widget _review() {
    final m = meal!;
    final n = mealNutrition(m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (missingFoods.isNotEmpty) ...[
          Panel(
            child: Text(
              'Not included: ${missingFoods.join(', ')}. Search Open Food Facts and USDA again when online, add a food below, or enter its label nutrition. No values were invented.',
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (m.items.isNotEmpty || m.manual != null) ...[
          _KayleoStatus(isEditing ? 'Review your changes' : 'Ready to add'),
          const SizedBox(height: KayleoSpacing.md),
          if (m.input == 'Photo + description')
            Text(
              'Estimated from your description. Your photo is saved with the meal.',
              style: TextStyle(fontSize: 11, color: _secondary),
            )
          else if (m.input == 'Photo demo')
            Text(
              'Sample meal estimate from a preset description.',
              style: TextStyle(fontSize: 11, color: _secondary),
            ),
          const SizedBox(height: 14),
        ],
        if (m.items.isEmpty && m.manual == null) ...[
          Panel(
            color: _surfaces.soft,
            border: false,
            child: Text(
              'No nutrition match is available yet. Add foods below or enter nutrition from a label.',
              style: TextStyle(fontSize: 12, color: _scheme.onSurface),
            ),
          ),
          const SizedBox(height: 18),
        ],
        Panel(
          padding: 20,
          border: false,
          child: Row(
            children: [
              FoodPhoto(image: m.image, meal: m, width: 82, height: 82),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated total',
                      style: TextStyle(color: _secondary, fontSize: 11),
                    ),
                    const SizedBox(height: KayleoSpacing.sm),
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: [
                          TextSpan(
                            text: number(n.calories),
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          const TextSpan(
                            text: ' kcal',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KayleoSpacing.card),
        Row(
          children: [
            Expanded(child: _macro('Protein', n.protein, KayleoColors.protein)),
            const SizedBox(width: 10),
            Expanded(child: _macro('Carbs', n.carbs, KayleoColors.carbs)),
            const SizedBox(width: 10),
            Expanded(child: _macro('Fat', n.fat, KayleoColors.fat)),
          ],
        ),
        const SizedBox(height: KayleoSpacing.card),
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Meal name'),
        ),
        const SizedBox(height: KayleoSpacing.lg),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: ['Breakfast', 'Lunch', 'Dinner', 'Snack']
              .map(
                (category) => ChoiceChip(
                  label: Text(category, style: TextStyle(fontSize: 11)),
                  selected: m.category == category,
                  selectedColor: _surfaces.soft,
                  side: BorderSide(color: _surfaces.border),
                  onSelected: (_) => setState(() => m.category = category),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: KayleoSpacing.md),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: m.time,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (d != null && mounted) {
                  setState(
                    () => m.time = DateTime(
                      d.year,
                      d.month,
                      d.day,
                      m.time.hour,
                      m.time.minute,
                    ),
                  );
                }
              },
              icon: Icon(Icons.calendar_today_outlined, size: 15),
              label: Text(
                DateFormat('d MMM yyyy').format(m.time),
                style: TextStyle(fontSize: 11),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(m.time),
                );
                if (t != null && mounted) {
                  setState(
                    () => m.time = DateTime(
                      m.time.year,
                      m.time.month,
                      m.time.day,
                      t.hour,
                      t.minute,
                    ),
                  );
                }
              },
              icon: Icon(Icons.schedule_rounded, size: 15),
              label: Text(
                DateFormat('h:mm a').format(m.time),
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SectionTitle('On your plate', action: 'Add food', onAction: addFood),
        for (final item in m.items) _itemRow(item),
        if (m.manual != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const IconBox(Icons.edit_outlined),
            title: Text(
              'Your nutrition entry',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${number(m.manual!.calories)} kcal · entered by you',
              style: TextStyle(fontSize: 11),
            ),
            trailing: IconButton(
              onPressed: () => setState(() => m.manual = null),
              tooltip: 'Remove manual nutrition',
              icon: Icon(Icons.close_rounded, size: 18),
            ),
            onTap: quickAdd,
          ),
        const SizedBox(height: KayleoSpacing.md),
        TextButton.icon(
          onPressed: quickAdd,
          icon: Icon(Icons.edit_note_rounded, size: 17),
          label: Text(
            'Enter nutrition from a label',
            style: TextStyle(fontSize: 11),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 6, bottom: KayleoSpacing.md),
          child: Text(
            'Check for missing foods and hidden ingredients. Portions are assumed unless you specified or confirmed them.',
            style: TextStyle(fontSize: 10, color: _secondary, height: 1.7),
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: KayleoSpacing.lg),
          leading: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: _scheme.primary,
          ),
          title: Text(
            'How did we calculate this?',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${m.assumptions}\n\nEach item uses nutrient values per 100 g × portion grams ÷ 100. These are practical estimates, and regional recipes use illustrative values. Hidden oil, brands, and preparation can change the result.',
                style: TextStyle(fontSize: 11, color: _secondary, height: 1.8),
              ),
            ),
            const SizedBox(height: KayleoSpacing.md),
            for (final item in m.items)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${mealItemFood(item).name}: ${mealItemFood(item).source}',
                  style: TextStyle(fontSize: 10, color: _secondary),
                ),
              ),
          ],
        ),
        TextField(
          controller: notes,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'A note for next time (optional)',
          ),
        ),
        const SizedBox(height: 14),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: saveUsual,
          onChanged: (v) => setState(() => saveUsual = v),
          title: Text(
            'Remember this as a usual meal',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            'Log it again in a tap from Saved meals.',
            style: TextStyle(fontSize: 10, color: _secondary),
          ),
        ),
      ],
    );
  }

  Widget _macro(String label, double value, Color color) => Container(
    decoration: BoxDecoration(
      color: _surfaces.card,
      borderRadius: BorderRadius.circular(16),
    ),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
    child: Column(
      children: [
        Container(
          height: 3,
          width: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${value.round()}g',
          style: TextStyle(
            color: _scheme.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 21,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10, color: _secondary)),
      ],
    ),
  );

  Widget _itemRow(MealItem item) {
    final food = mealItemFood(item);
    final quantity = (item.portion?['quantity'] as num?)?.toDouble();
    final portionUnit = item.portion?['unit'] as String?;
    final quantityText = quantity == null
        ? ''
        : quantity == quantity.roundToDouble()
        ? '${quantity.toInt()}'
        : '$quantity';
    final countLabel =
        quantity != null &&
            quantity != 1 &&
            ['piece', 'egg', 'slice'].contains(portionUnit)
        ? '$quantityText × '
        : '';
    final amountLabel = quantity == null || portionUnit == null
        ? '${item.grams.round()} ${food.nutritionBasisUnit}'
        : portionUnit == 'g' || portionUnit == 'ml' || portionUnit == 'oz'
        ? '$quantityText $portionUnit'
        : '$quantityText ${quantity == 1 ? portionUnit : '${portionUnit}s'} · ≈${item.grams.round()} g';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _surfaces.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _surfaces.border),
        ),
        child: InkWell(
          onTap: () => editItem(item),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 4, 14),
            child: Row(
              children: [
                FoodPhoto(image: food.image, width: 48, height: 48, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$countLabel${food.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        amountLabel,
                        style: TextStyle(fontSize: 10, color: _secondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${itemNutrition(item).calories.round()} kcal',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        food.source,
                        style: TextStyle(fontSize: 10, color: _secondary),
                      ),
                      if (food.sourceUrl.isNotEmpty)
                        Text(
                          food.sourceUrl,
                          style: TextStyle(fontSize: 10, color: _secondary),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => editItem(item),
                  tooltip: 'Edit ${food.name}',
                  icon: const Icon(Icons.edit_outlined, size: 17),
                ),
                IconButton(
                  onPressed: () => setState(() => meal!.items.remove(item)),
                  tooltip: 'Remove ${food.name}',
                  icon: Icon(Icons.close_rounded, size: 17, color: _secondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> editItem(MealItem item) async {
    final portion = await editPortion(context, item);
    if (portion != null && mounted) {
      setState(() {
        item.grams = consumedPortion(mealItemFood(item), portion);
        item.portion = portion;
      });
    }
  }

  Future<void> quickAdd() async {
    final existing = meal?.manual;
    final controllers = List.generate(
      4,
      (i) => TextEditingController(
        text: existing == null
            ? ''
            : [
                existing.calories,
                existing.protein,
                existing.carbs,
                existing.fat,
              ][i].round().toString(),
      ),
    );
    final name = TextEditingController(text: title.text);
    final key = GlobalKey<FormState>();
    final ok = await showManagedDialog<bool>(
      controllers: [...controllers, name],
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enter your nutrition'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Meal name'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 14),
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: KayleoSpacing.md),
                      child: TextFormField(
                        controller: controllers[i],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: [
                            'Calories (kcal)',
                            'Protein (g)',
                            'Carbs (g)',
                            'Fat (g)',
                          ][i],
                        ),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          return n == null ||
                                  !n.isFinite ||
                                  n < 0 ||
                                  n > (i == 0 ? 10000 : 1000)
                              ? 'Enter a valid amount'
                              : null;
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: Text('Use these values'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final values = controllers.map((c) => double.parse(c.text)).toList();
      setState(() {
        meal ??= Meal(
          id: newId(),
          name: name.text.trim(),
          time: defaultTime,
          category: MealEngine.categoryForHour(defaultTime.hour),
          items: [],
          input: 'Manual',
        );
        meal!.manual = Nutrients(values[0], values[1], values[2], values[3]);
        title.text = name.text.trim();
        stage = 2;
        error = null;
      });
    }
  }

  Widget _success() {
    final total = widget.state.totalsFor(meal!.time);
    return Center(
      child: Column(
        children: [
          const SizedBox(height: KayleoSpacing.page),
          const IconBox(Icons.check_rounded, size: 76, color: lime),
          const SizedBox(height: KayleoSpacing.xl),
          Text(
            !isEditing ? 'Your meal is added.' : 'Your meal is updated.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: KayleoSpacing.md),
          Text(
            '${meal!.name}\n${number(mealNutrition(meal!).calories)} estimated kcal',
            textAlign: TextAlign.center,
            style: TextStyle(color: _secondary, height: 1.8),
          ),
          const SizedBox(height: 28),
          Panel(
            color: _surfaces.soft,
            border: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: _scheme.primary,
                ),
                const SizedBox(width: KayleoSpacing.md),
                Flexible(
                  child: Text(
                    '${number(total.calories)} / ${number(widget.state.profile.calorieTarget)} kcal on ${DateFormat('d MMM').format(meal!.time)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _scheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Your food story, one meal at a time.',
            style: TextStyle(fontSize: 12, color: _secondary),
          ),
          const SizedBox(height: KayleoSpacing.page),
        ],
      ),
    );
  }

  Widget? _footer() {
    if (stage == 0 && mode == 'Manual') {
      return null;
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: Key(stage == 2 ? 'save-meal' : 'logging-continue'),
        onPressed: busy || cameraOpen || (stage == 1 && answer == null)
            ? null
            : stage == 0
            ? analyze
            : stage == 1
            ? nextQuestion
            : stage == 2
            ? save
            : () => Navigator.pop(context),
        icon: busy
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                stage == 2 ? Icons.check_rounded : Icons.arrow_forward_rounded,
                size: 18,
              ),
        label: Text(
          busy
              ? 'Preparing your estimate…'
              : stage == 0
              ? (mode == 'Barcode' ? 'Look up food' : 'Understand my meal')
              : stage == 1
              ? 'Continue'
              : stage == 2
              ? (!isEditing ? 'Add meal' : 'Save changes')
              : 'Done',
        ),
      ),
    );
  }
}

class _KayleoStatus extends StatelessWidget {
  const _KayleoStatus(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const KayleoDot(size: 8),
      const SizedBox(width: KayleoSpacing.sm),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ],
  );
}

class _CaptureEyebrow extends StatelessWidget {
  const _CaptureEyebrow({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: active
          ? lime.withValues(alpha: .14)
          : Colors.white.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: active
            ? lime.withValues(alpha: .28)
            : Colors.white.withValues(alpha: .08),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: active ? lime : Colors.white54),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? lime : Colors.white54,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.15,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CaptureMealComposer extends StatefulWidget {
  const _CaptureMealComposer({
    required this.controller,
    required this.voice,
    required this.listening,
  });

  final TextEditingController controller;
  final bool voice, listening;

  @override
  State<_CaptureMealComposer> createState() => _CaptureMealComposerState();
}

class _CaptureMealComposerState extends State<_CaptureMealComposer> {
  bool focused = false;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: focused ? .065 : .04),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: focused
            ? lime.withValues(alpha: .48)
            : Colors.white.withValues(alpha: .1),
      ),
      boxShadow: focused
          ? [
              BoxShadow(
                color: lime.withValues(alpha: .06),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ]
          : null,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: widget.listening ? lime : Colors.white30,
                shape: BoxShape.circle,
                boxShadow: widget.listening
                    ? [
                        BoxShadow(
                          color: lime.withValues(alpha: .4),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.voice ? 'LIVE TRANSCRIPT' : 'MEAL DESCRIPTION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '${value.text.length}',
                        style: const TextStyle(
                          color: Colors.white30,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (value) => setState(() => focused = value),
          child: TextField(
            key: const Key('meal-description'),
            controller: widget.controller,
            minLines: widget.voice ? 2 : 4,
            maxLines: widget.voice ? 4 : 7,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onEditingComplete: () =>
                FocusManager.instance.primaryFocus?.unfocus(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.55,
            ),
            decoration: InputDecoration(
              hintText: widget.voice
                  ? 'Your words will appear here…'
                  : 'e.g. two eggs, avocado toast and coffee',
              hintStyle: const TextStyle(
                color: Colors.white30,
                fontSize: 14,
                height: 1.55,
              ),
              isCollapsed: true,
              filled: false,
              fillColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    ),
  );
}

class _VoiceControl extends StatefulWidget {
  const _VoiceControl({
    required this.listening,
    required this.onTap,
    this.premium = false,
  });
  final bool listening;
  final VoidCallback onTap;
  final bool premium;

  @override
  State<_VoiceControl> createState() => _VoiceControlState();
}

class _VoiceControlState extends State<_VoiceControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_VoiceControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.listening && !_reduceMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.premium
      ? _premiumControl()
      : Semantics(
          button: true,
          label: widget.listening ? 'Stop listening' : 'Start listening',
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(100),
            child: SizedBox(
              width: 180,
              height: 180,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: 1 + _pulse.value * .045,
                      child: KayleoRing(
                        progress: 1,
                        highlight: false,
                        size: 172,
                        stroke: 1,
                        color: lime.withValues(alpha: .15),
                        track: Colors.transparent,
                        state: widget.listening
                            ? KayleoRingState.listening
                            : KayleoRingState.idle,
                        child: const SizedBox.shrink(),
                      ),
                    ),
                    KayleoRing(
                      progress: 1,
                      highlight: false,
                      size: 140,
                      stroke: 1,
                      color: lime.withValues(alpha: .3),
                      track: Colors.transparent,
                      child: const SizedBox.shrink(),
                    ),
                    Container(
                      width: 106,
                      height: 106,
                      decoration: BoxDecoration(
                        color: lime,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: lime.withValues(
                              alpha: .17 + _pulse.value * .09,
                            ),
                            blurRadius: 28,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.listening
                            ? Icons.stop_rounded
                            : Icons.mic_none_rounded,
                        size: 38,
                        color: forest,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
  Widget _premiumControl() => Semantics(
    button: true,
    label: widget.listening ? 'Stop listening' : 'Start listening',
    child: InkWell(
      borderRadius: BorderRadius.circular(80),
      onTap: widget.onTap,
      child: SizedBox(
        width: 144,
        height: 144,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + _pulse.value * .055,
                child: KayleoRing(
                  progress: 1,
                  highlight: false,
                  size: 136,
                  stroke: 1,
                  color: widget.listening
                      ? lime.withValues(alpha: .5)
                      : Colors.white.withValues(alpha: .1),
                  track: Colors.transparent,
                  child: const SizedBox.shrink(),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: widget.listening
                        ? [
                            lime.withValues(alpha: .24),
                            lime.withValues(alpha: .1),
                          ]
                        : [
                            Colors.white.withValues(alpha: .09),
                            Colors.white.withValues(alpha: .035),
                          ],
                  ),
                  border: Border.all(
                    color: widget.listening
                        ? lime.withValues(alpha: .32)
                        : Colors.white.withValues(alpha: .12),
                  ),
                  boxShadow: widget.listening
                      ? [
                          BoxShadow(
                            color: lime.withValues(
                              alpha: .08 + _pulse.value * .08,
                            ),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.listening
                          ? Icons.stop_rounded
                          : Icons.mic_none_rounded,
                      size: 34,
                      color: lime,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.listening ? 'STOP' : 'TAP TO SPEAK',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class FoodPicker extends StatefulWidget {
  const FoodPicker({super.key});
  @override
  State<FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<FoodPicker> {
  String search = '', category = 'All';
  @override
  Widget build(BuildContext context) {
    final matches = foods
        .where(
          (f) =>
              (category == 'All' || f.category == category) &&
              (f.name.toLowerCase().contains(search.toLowerCase()) ||
                  f.aliases.any((a) => a.contains(search.toLowerCase()))),
        )
        .take(80)
        .toList();
    return SheetFrame(
      title: 'Find a food',
      subtitle: '500+ foods ready offline. Search or browse by category.',
      child: Column(
        children: [
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search rice, momo, eggs…',
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  [
                        'All',
                        'Regional',
                        'Asian',
                        'European',
                        'African',
                        'Americas',
                        'Basics',
                        'Breakfast',
                        'Snacks',
                        'Drinks',
                      ]
                      .map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              c,
                              style: const TextStyle(fontSize: 10),
                            ),
                            selected: category == c,
                            selectedColor: context.kayleoSurfaces.soft,
                            onSelected: (_) => setState(() => category = c),
                            side: BorderSide(
                              color: context.kayleoSurfaces.border,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          const SizedBox(height: 14),
          if (matches.isEmpty)
            const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No match just yet',
              subtitle: 'Try a simpler name, or go back and enter your own calories and macros.',
            ),
          if (matches.length == 80)
            Text(
              'Showing the first 80 matches. Search to narrow the list.',
              style: TextStyle(fontSize: 11, color: context.kayleoMuted),
            ),
          for (final f in matches)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconBox(
                f.category == 'Regional'
                    ? Icons.ramen_dining_rounded
                    : Icons.restaurant_rounded,
              ),
              title: Text(
                f.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '1 ${f.unit} · ${f.servingGrams.round()} g',
                style: TextStyle(fontSize: 10, color: context.kayleoMuted),
              ),
              trailing: Text(
                '${(f.per100g.calories * f.servingGrams / 100).round()} kcal',
                style: TextStyle(
                  fontSize: 11,
                  color: context.kayleoPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => Navigator.pop(context, f),
            ),
        ],
      ),
    );
  }
}
