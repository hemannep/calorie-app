import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../features/portion_editor.dart';
import '../data/models.dart';
import '../features/meal_camera.dart';
import '../features/logging.dart';
import '../features/capture_mode_bar.dart';
import 'food_lookup_screen.dart';
import '../services/food_ai_service.dart';

class FoodCameraScreen extends StatefulWidget {
  const FoodCameraScreen({
    super.key,
    required this.state,
    this.service,
    this.initialPhoto,
    this.initialMode = 'Photo',
    this.initialDate,
  });
  final AppState state;
  final FoodAIService? service;
  final Uint8List? initialPhoto;
  final String initialMode;
  final DateTime? initialDate;
  @override
  State<FoodCameraScreen> createState() => _FoodCameraScreenState();
}

class _FoodCameraScreenState extends State<FoodCameraScreen>
    with SingleTickerProviderStateMixin {
  late final FoodAIService service = widget.service ?? FoodAIService();
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  Uint8List? photo;
  bool busy = false, picking = false, processing = false;
  bool handingOffCamera = false;
  late String activeMode = widget.initialMode;
  String? handoffTarget;
  Completer<void>? cameraRelease;
  final draft = TextEditingController();
  double slideDirection = 1;
  double swipeDistance = 0;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.initialPhoto != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => scan(widget.initialPhoto!),
      );
    }
  }

  @override
  void dispose() {
    generation++;
    pulse.dispose();
    draft.dispose();
    if (widget.service == null) unawaited(service.dispose().catchError((_) {}));
    super.dispose();
  }

  bool current(int token) => mounted && generation == token;
  void manual() {
    setState(() => busy = false);
    selectMode('Text');
  }

  void selectMode(String next) => unawaited(_selectMode(next));

  Future<void> _selectMode(String next) async {
    if (next == activeMode || busy || picking || handingOffCamera) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final direction =
        captureModes.indexOf(next) > captureModes.indexOf(activeMode)
        ? 1.0
        : -1.0;
    final releasingCamera = activeMode == 'Photo' || activeMode == 'Barcode';
    if (releasingCamera) {
      final released = cameraRelease = Completer<void>();
      setState(() {
        slideDirection = direction;
        handoffTarget = next;
        handingOffCamera = true;
      });
      try {
        await released.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Some platform camera implementations do not acknowledge disposal.
        // Continue after the guard period instead of trapping the user.
      }
      if (!mounted || cameraRelease != released) return;
      // CameraX can report disposal before Samsung's camera HAL has completely
      // released the lens. Give camera-to-camera switches a short settling
      // window so the next preview does not inherit an abandoned surface.
      if (next == 'Photo' || next == 'Barcode') {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      if (!mounted || cameraRelease != released) return;
      cameraRelease = null;
      setState(() {
        activeMode = next;
        handoffTarget = null;
        handingOffCamera = false;
      });
      return;
    }
    setState(() {
      slideDirection = direction;
      activeMode = next;
    });
  }

  void cameraReleased() {
    final release = cameraRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  void swipeMode(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 120 && swipeDistance.abs() < 48) return;
    final direction = velocity.abs() >= 120 ? velocity : swipeDistance;
    final index = (captureModes.indexOf(activeMode) + (direction < 0 ? 1 : -1))
        .clamp(0, 3);
    selectMode(captureModes[index]);
  }

  Future<void> gallery() async {
    if (busy || picking) return;
    setState(() => picking = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      await scan(await image.readAsBytes());
    } catch (_) {
      if (mounted) {
        toast(context, 'The photo could not be opened. Try another image.');
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> scan(Uint8List bytes) async {
    if (busy || !mounted) return;
    final token = ++generation;
    if (!MediaQuery.disableAnimationsOf(context)) pulse.repeat(reverse: true);
    HapticFeedback.mediumImpact();
    setState(() {
      busy = true;
      processing = true;
      photo = bytes;
    });
    try {
      final result = await service.scanMeal(bytes);
      if (!mounted || !current(token)) return;
      pulse.stop();
      setState(() => processing = false);
      if (result.status == ScanStatus.noFood) {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ No Food Detected'),
            content: const Text(
              'Please make sure your meal is well-lit and clearly centered on the plate.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'retake'),
                child: const Text('Retake Photo'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'manual'),
                child: const Text('Type Meal Instead'),
              ),
            ],
          ),
        );
        if (current(token) && choice == 'manual') manual();
        return; // This branch never requests nutrition.
      }
      FoodPrediction? selected = result.first;
      if (result.status == ScanStatus.ambiguous) {
        selected = await showModalBottomSheet<FoodPrediction>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => _ClarifySheet(result: result),
        );
      }
      if (!mounted || !current(token) || selected == null) return;
      if (selected.index == 0) return;
      setState(() => processing = true);
      if (!MediaQuery.disableAnimationsOf(context)) pulse.repeat(reverse: true);
      final products = await service.fetchNutrition(selected.name);
      if (!mounted || !current(token)) return;
      pulse.stop();
      setState(() => processing = false);
      if (products.isEmpty) {
        throw StateError(
          'No matching nutrition was found. Type the meal or enter its label manually.',
        );
      }
      FoodNutrition? product;
      if (products.length == 1) {
        product = products.single;
      } else {
        product = await showModalBottomSheet<FoodNutrition>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose the matching food',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Check the name and product. Search results may include a different recipe or brand.',
                  ),
                  for (final food in products)
                    ListTile(
                      title: Text(food.name),
                      subtitle: Text(food.source),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, food),
                    ),
                ],
              ),
            ),
          ),
        );
      }
      if (!mounted || !current(token) || product == null) return;
      final logged = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FoodConfirmationScreen(
            state: widget.state,
            food: product!,
            photo: bytes,
            confidence: selected!.index < 0 ? null : selected.confidence,
          ),
        ),
      );
      if (mounted && current(token) && logged == true) {
        Navigator.pop(context, 'logged');
      }
    } catch (error) {
      if (!mounted || !current(token)) return;
      pulse.stop();
      setState(() => processing = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Let’s try another way'),
          content: Text(
            error.toString().replaceFirst(
              RegExp(r'^[A-Za-z]+(?:Error|Exception)?:\s*'),
              '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Retake Photo'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                manual();
              },
              child: const Text('Type Meal Instead'),
            ),
          ],
        ),
      );
    } finally {
      if (current(token)) {
        pulse.stop();
        setState(() => busy = false);
      }
    }
  }

  Widget _modeContent(double dockExtent) {
    if (handingOffCamera) {
      return const ColoredBox(
        key: Key('camera-handoff'),
        color: KayleoColors.camera,
        child: Center(
          child: CircularProgressIndicator(color: lime, strokeWidth: 2),
        ),
      );
    }
    if (activeMode == 'Text' || activeMode == 'Voice') {
      return LoggingFlow(
        key: ValueKey(activeMode),
        state: widget.state,
        initialMode: activeMode,
        initialDate: widget.initialDate,
        captureSurface: true,
        draftController: draft,
      );
    }
    if (activeMode == 'Barcode') {
      return FoodLookupScreen(
        state: widget.state,
        barcode: true,
        embedded: true,
        bottomInset: dockExtent,
        onCameraReleased: cameraReleased,
      );
    }
    return MealCamera(
      immersive: true,
      showModeBar: false,
      bottomInset: (dockExtent - MediaQuery.paddingOf(context).bottom).clamp(
        0,
        double.infinity,
      ),
      onClose: () => Navigator.pop(context),
      onPhoto: scan,
      onChoosePhoto: gallery,
      onSelectMode: selectMode,
      onBarcode: () => selectMode('Barcode'),
      onReleased: cameraReleased,
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: forest,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Theme(
      data: kayleoTheme(brightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: forest,
        resizeToAvoidBottomInset: false,
        body: picking
            ? const Center(child: CircularProgressIndicator(color: lime))
            : busy
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (photo != null)
                    Image.memory(
                      photo!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
                  const ColoredBox(color: Color(0xB5000000)),
                  SafeArea(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            tooltip: 'Close scanner',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ScaleTransition(
                                  scale: MediaQuery.disableAnimationsOf(context)
                                      ? const AlwaysStoppedAnimation(1)
                                      : Tween(
                                          begin: .90,
                                          end: 1.05,
                                        ).animate(pulse),
                                  child: SizedBox(
                                    width: 100,
                                    height: 100,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: lime,
                                      value: processing ? null : 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Text(
                                  processing
                                      ? 'Looking at your meal…'
                                      : 'Review your meal',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Recognition stays on your device.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF102A22), forest],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      onHorizontalDragStart: (_) => swipeDistance = 0,
                      onHorizontalDragUpdate: (details) =>
                          swipeDistance += details.delta.dx,
                      onHorizontalDragEnd: swipeMode,
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(activeMode),
                        tween: Tween(begin: 0, end: 1),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        child: Builder(
                          builder: (context) {
                            final media = MediaQuery.of(context);
                            final dockExtent =
                                captureBarHeight(context) +
                                28 +
                                media.viewPadding.bottom;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                    activeMode == 'Photo' ||
                                        activeMode == 'Barcode'
                                    ? 0
                                    : dockExtent,
                              ),
                              child: MediaQuery(
                                data: media.copyWith(
                                  viewInsets: media.viewInsets.copyWith(
                                    bottom:
                                        (media.viewInsets.bottom - dockExtent)
                                            .clamp(0, double.infinity),
                                  ),
                                ),
                                child: _modeContent(dockExtent),
                              ),
                            );
                          },
                        ),
                        builder: (context, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(
                              slideDirection * 20 * (1 - value),
                              0,
                            ),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
                    child: CaptureModeBar(
                      selected: handoffTarget ?? activeMode,
                      onSelect: selectMode,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}

class _ClarifySheet extends StatefulWidget {
  const _ClarifySheet({required this.result});
  final FoodScanResult result;
  @override
  State<_ClarifySheet> createState() => _ClarifySheetState();
}

class _ClarifySheetState extends State<_ClarifySheet> {
  final custom = TextEditingController();
  FoodPrediction? selected;
  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Clarify Your Meal',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        Text(
          'Did you mean ${widget.result.first.name} (${(widget.result.first.confidence * 100).round()}%) or ${widget.result.second.name} (${(widget.result.second.confidence * 100).round()}%)?',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in [widget.result.first, widget.result.second])
              ChoiceChip(
                label: Text('${p.name} · ${(p.confidence * 100).round()}%'),
                selected: identical(selected, p),
                onSelected: (_) => setState(() => selected = p),
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: custom,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'A different food name'),
          onChanged: (_) => setState(() => selected = null),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: custom.text.trim().length >= 2 || selected != null
                ? () => Navigator.pop(
                    context,
                    custom.text.trim().length >= 2
                        ? FoodPrediction(-1, custom.text.trim(), 0)
                        : selected,
                  )
                : null,
            child: const Text('Confirm food'),
          ),
        ),
      ],
    ),
  );
}

class FoodConfirmationScreen extends StatefulWidget {
  const FoodConfirmationScreen({
    super.key,
    required this.state,
    required this.food,
    this.photo,
    this.confidence,
  });
  final AppState state;
  final FoodNutrition food;
  final Uint8List? photo;
  final double? confidence;
  @override
  State<FoodConfirmationScreen> createState() => _FoodConfirmationScreenState();
}

class _FoodConfirmationScreenState extends State<FoodConfirmationScreen> {
  double amount = 100;
  final mealId = newId();
  Map<String, dynamic>? portion;
  late String unit = widget.food.unit;
  final form = GlobalKey<FormState>();
  late final values = widget.food.values
      .map((n) => TextEditingController(text: n?.toString() ?? ''))
      .toList();
  bool saving = false;
  String? error;
  static const labels = [
    'Calories (kcal)',
    'Protein (g)',
    'Carbohydrates (g)',
    'Fats (g)',
    'Dietary fiber (g)',
  ];
  @override
  void dispose() {
    for (final c in values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final n = values.map((c) => double.tryParse(c.text)).toList();
      final source = widget.food.toFood(n);
      final food = Food(
        id: source.id,
        name: source.name,
        aliases: source.aliases,
        per100g: source.per100g,
        servingGrams: 100,
        unit: unit,
        nutritionBasisUnit: unit,
        source:
            source.source +
            (widget.food.complete ? '' : ' · label values completed by you'),
        sourceUrl: source.sourceUrl,
        barcode: source.barcode,
      );
      await widget.state.saveMeal(
        Meal(
          id: mealId,
          name: food.name,
          time: DateTime.now(),
          category: DateTime.now().hour < 11
              ? 'Breakfast'
              : DateTime.now().hour < 17
              ? 'Lunch'
              : 'Dinner',
          items: [
            MealItem(
              foodId: food.id,
              grams: amount,
              snapshot: food,
              portion: portion,
            ),
          ],
          photo: widget.photo,
          input: widget.confidence == null ? 'Food lookup' : 'On-device camera',
          assumptions: food.source,
          notes: food.sourceUrl,
        ),
      );
      if (!mounted) return;
      if (widget.state.storageError != null) {
        setState(() => error = widget.state.storageError);
        return;
      }
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'The meal could not be saved. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review your meal')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Confirm & Log Meal'),
              ),
            ),
          ],
        ),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (widget.photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.memory(
                      widget.photo!,
                      height: 210,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
                  ),
                const SizedBox(height: 22),
                Text(
                  widget.food.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Tag(
                      widget.food.estimated
                          ? 'LOCAL ESTIMATE'
                          : widget.food.source.startsWith('USDA')
                          ? 'USDA DATA'
                          : 'PRODUCT LABEL',
                    ),
                    if (widget.confidence != null)
                      Tag('MODEL ${(widget.confidence! * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.food.source,
                  style: TextStyle(color: context.kayleoMuted),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Check that the food, brand and preparation match your meal.',
                ),
                const SizedBox(height: 24),
                Text(
                  'Portion: ${amount.round()} $unit',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Slider(
                  value: amount.clamp(50, 800),
                  min: 50,
                  max: 800,
                  divisions: 150,
                  label: '${amount.round()} $unit',
                  onChanged: saving
                      ? null
                      : (v) => setState(() {
                          amount = v;
                          portion = null;
                        }),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.straighten),
                  label: const Text('Custom amount or shared portion'),
                  onPressed: saving
                      ? null
                      : () async {
                          final known = values
                              .map((v) => double.tryParse(v.text) ?? 0.0)
                              .toList();
                          final f = widget.food.toFood(known);
                          final item = MealItem(
                            foodId: f.id,
                            grams: amount,
                            snapshot: Food(
                              id: f.id,
                              name: f.name,
                              aliases: f.aliases,
                              per100g: f.per100g,
                              servingGrams: 100,
                              unit: unit,
                              nutritionBasisUnit: unit,
                            ),
                            portion: portion,
                          );
                          final p = await editPortion(context, item);
                          if (!mounted || p == null) return;
                          setState(() {
                            amount = consumedPortion(item.snapshot!, p);
                            portion = p;
                          });
                        },
                ),
                if (widget.food.source.startsWith('Open Food Facts')) ...[
                  const Text(
                    'Check the label’s nutrition basis. Volume is not converted to mass.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final u in ['g', 'ml'])
                        ChoiceChip(
                          label: Text(u == 'g' ? 'Per 100 g' : 'Per 100 ml'),
                          selected: unit == u,
                          onSelected: saving
                              ? null
                              : (_) => setState(() {
                                  unit = u;
                                  portion = null;
                                }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Nutrition per 100 $unit',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < values.length; i++)
                  if (widget.food.values[i] == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: values[i],
                        readOnly: widget.food.values[i] != null,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: labels[i],
                          helperText: i == 4
                              ? 'Optional when the label has no fiber value.'
                              : widget.food.values[i] == null
                              ? 'Missing: enter the label value.'
                              : null,
                        ),
                        validator: (text) {
                          if (i == 4 && (text?.trim().isEmpty ?? true)) {
                            return null;
                          }
                          final n = double.tryParse(text ?? '');
                          return n == null ||
                                  !n.isFinite ||
                                  n < 0 ||
                                  n > (i == 0 ? 1200 : 100)
                              ? 'Enter a valid nonnegative label value'
                              : null;
                        },
                        onChanged: (_) => setState(() => {}),
                      ),
                    ),
                Panel(
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 16,
                    children: [
                      for (var i = 0; i < values.length; i++)
                        SizedBox(
                          width: 130,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                labels[i].split(' (').first,
                                style: TextStyle(color: context.kayleoMuted),
                              ),
                              Text(
                                double.tryParse(values[i].text) == null
                                    ? '—'
                                    : '${number(double.parse(values[i].text) * amount / 100)} ${i == 0 ? 'kcal' : 'g'}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SizedBox(height: 16),
                Text(
                  'Open Food Facts · ODbL / DbCL. USDA · public domain.',
                  style: TextStyle(color: context.kayleoMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
