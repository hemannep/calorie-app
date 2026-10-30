import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/meal_engine.dart';
import '../core/ui.dart';
import '../data/food_database.dart';
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
    service.warmUpConnection();
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
        maxWidth: 768,
        maxHeight: 768,
        imageQuality: 78,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() => picking = false);
      await scan(bytes);
    } catch (_) {
      if (mounted) {
        toast(context, 'The photo could not be opened. Try another image.');
      }
    } finally {
      if (mounted && picking) setState(() => picking = false);
    }
  }

  Future<void> _recoverFromPhoto({
    required String title,
    required String message,
    required IconData icon,
  }) async {
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _PhotoRecoverySheet(title: title, message: message, icon: icon),
    );
    if (!mounted) return;
    if (choice == 'manual') {
      manual();
    } else if (choice == 'gallery') {
      setState(() => busy = false);
      await gallery();
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
      if (service.geminiConfigured) {
        var food = await service.analyzeMealPhoto(bytes);
        if (!mounted || !current(token)) return;
        pulse.stop();
        setState(() => processing = false);
        if (food.clarifications.isNotEmpty) {
          final answers = await showModalBottomSheet<List<String>>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (context) =>
                _MealClarificationSheet(clarifications: food.clarifications),
          );
          if (!mounted || !current(token)) return;
          if (answers != null && answers.isNotEmpty) {
            setState(() => processing = true);
            if (!MediaQuery.disableAnimationsOf(context)) {
              pulse.repeat(reverse: true);
            }
            food = await service.refineMealPhoto(
              bytes,
              correction: answers.join(' '),
              previous: food,
            );
            if (!mounted || !current(token)) return;
            pulse.stop();
            setState(() => processing = false);
          }
        }
        final logged = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => FoodConfirmationScreen(
              state: widget.state,
              food: food,
              photo: bytes,
              confidence: null,
              service: service,
            ),
          ),
        );
        if (mounted && current(token) && logged == true) {
          Navigator.pop(context, 'logged');
        }
        return;
      }
      final result = await service.scanMeal(bytes);
      if (!mounted || !current(token)) return;
      pulse.stop();
      setState(() => processing = false);
      if (result.status == ScanStatus.noFood) {
        await _recoverFromPhoto(
          title: 'Nothing to log yet',
          message: 'Keep the meal close, centered, and well lit, then take another photo.',
          icon: Icons.center_focus_strong_rounded,
        );
        return;
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
                  const LocalizedText(
                    'Choose the matching food',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const LocalizedText(
                    'Check the name and product. Search results may include a different recipe or brand.',
                  ),
                  for (final food in products)
                    ListTile(
                      title: LocalizedText(food.name),
                      subtitle: LocalizedText(food.source),
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
      final photoIssue = error is PhotoAnalysisException ? error.issue : null;
      final rawMessage = error.toString().replaceFirst(
        RegExp(r'^[A-Za-z]+(?:Error|Exception)?:\s*'),
        '',
      );
      final lower = rawMessage.toLowerCase();
      final String message;
      if (lower.contains('socketexception') ||
          lower.contains('clientexception') ||
          lower.contains('connection abort') ||
          lower.contains('failed host lookup') ||
          lower.contains('googleapis.com')) {
        message = 'Kayleo couldn’t reach the network right now. Check your internet connection and try again.';
      } else {
        message = rawMessage
            .replaceAll(RegExp(r'https?://\S+'), '')
            .replaceAll(
              RegExp(r'\bgemini[-a-z0-9.]*\b', caseSensitive: false),
              'Kayleo',
            )
            .trim();
      }
      await _recoverFromPhoto(
        title: photoIssue == PhotoAnalysisIssue.noFood
            ? 'Nothing to log yet'
            : photoIssue == PhotoAnalysisIssue.unclear
            ? 'Let’s get a clearer photo'
            : 'Photo analysis paused',
        message: message,
        icon: photoIssue == PhotoAnalysisIssue.noFood
            ? Icons.no_meals_outlined
            : photoIssue == PhotoAnalysisIssue.unclear
            ? Icons.photo_camera_outlined
            : Icons.wifi_tethering_error_rounded,
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
      onPhotoCaptured: (bytes) {
        if (service.geminiConfigured) {
          unawaited(
            service
                .analyzeMealPhoto(bytes)
                .catchError(
                  (_) => const FoodNutrition(
                    id: '',
                    name: '',
                    source: '',
                    sourceUrl: '',
                    values: [],
                  ),
                ),
          );
        }
      },
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
            ? _KayleoParallaxScanView(
                photo: photo,
                animation: pulse,
                processing: processing,
                aiConfigured: service.geminiConfigured,
                onClose: () => Navigator.pop(context),
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

class _KayleoParallaxScanView extends StatefulWidget {
  const _KayleoParallaxScanView({
    required this.photo,
    required this.animation,
    required this.processing,
    required this.aiConfigured,
    required this.onClose,
  });

  final Uint8List? photo;
  final Animation<double> animation;
  final bool processing;
  final bool aiConfigured;
  final VoidCallback onClose;

  @override
  State<_KayleoParallaxScanView> createState() =>
      _KayleoParallaxScanViewState();
}

class _KayleoParallaxScanViewState extends State<_KayleoParallaxScanView> {
  Offset _dragTilt = Offset.zero;
  Timer? _stageTimer;
  int _stage = 0;

  static const _scanStages = [
    'Finding visible foods',
    'Checking ingredients & toppings',
    'Estimating portions',
    'Calculating nutrition',
  ];

  @override
  void initState() {
    super.initState();
    _stageTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted && widget.processing) {
        setState(() => _stage = math.min(_stage + 1, _scanStages.length - 1));
      }
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    super.dispose();
  }

  void _updateTilt(Offset delta, Size size) {
    final nx = (_dragTilt.dx + delta.dx / (size.width * 0.4)).clamp(-1.0, 1.0);
    final ny = (_dragTilt.dy + delta.dy / (size.height * 0.4)).clamp(-1.0, 1.0);
    setState(() => _dragTilt = Offset(nx, ny));
  }

  void _resetTilt() {
    if (_dragTilt == Offset.zero) return;
    setState(() => _dragTilt = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final size = MediaQuery.sizeOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) => _updateTilt(d.delta, size),
      onPanEnd: (_) => _resetTilt(),
      onPanCancel: _resetTilt,
      child: AnimatedBuilder(
        animation: widget.animation,
        builder: (context, _) {
          final t = disableAnimations ? 0.5 : widget.animation.value;
          final angle = t * math.pi * 2;
          final autoX = disableAnimations ? 0.0 : math.sin(angle) * 0.22;
          final autoY = disableAnimations ? 0.0 : math.cos(angle) * 0.18;
          final px = (_dragTilt.dx + autoX).clamp(-1.0, 1.0);
          final py = (_dragTilt.dy + autoY).clamp(-1.0, 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1: Soft parallax blurred meal backdrop
              if (widget.photo != null)
                Transform.translate(
                  offset: Offset(-px * 16, -py * 16),
                  child: Transform.scale(
                    scale: 1.15,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Image.memory(
                        widget.photo!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(),
                      ),
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xB8060F0C),
                      Color(0xCC060F0C),
                      Color(0xEB050B09),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: context.l10n.translate('Close scanner'),
                          onPressed: widget.onClose,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Layer 2: Larger, refined floating parallax food frame
                                Builder(
                                  builder: (context) {
                                    final frameW = math.min(
                                      size.width - 48,
                                      288.0,
                                    );
                                    final frameH = math.min(
                                      size.width - 32,
                                      308.0,
                                    );
                                    return Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()
                                        ..setEntry(3, 2, 0.001)
                                        ..rotateX(-py * 0.085)
                                        ..rotateY(px * 0.085)
                                        ..translateByDouble(
                                          px * 10,
                                          py * 10,
                                          0,
                                          1,
                                        ),
                                      child: Container(
                                        width: frameW,
                                        height: frameH,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            32,
                                          ),
                                          border: Border.all(
                                            color: widget.processing
                                                ? Color.lerp(
                                                    Colors.white.withValues(
                                                      alpha: 0.18,
                                                    ),
                                                    lime.withValues(alpha: 0.6),
                                                    t,
                                                  )!
                                                : Colors.white.withValues(
                                                    alpha: 0.2,
                                                  ),
                                            width: 1.4,
                                          ),
                                          boxShadow: [
                                            if (widget.processing)
                                              BoxShadow(
                                                color: lime.withValues(
                                                  alpha: 0.12 + (t * 0.14),
                                                ),
                                                blurRadius: 38,
                                                spreadRadius: 2,
                                              ),
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.5,
                                              ),
                                              blurRadius: 34,
                                              offset: Offset(
                                                -px * 8,
                                                -py * 8 + 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            30.5,
                                          ),
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              if (widget.photo != null)
                                                Transform.scale(
                                                  scale: 1.08,
                                                  child: Transform.translate(
                                                    offset: Offset(
                                                      -px * 8,
                                                      -py * 8,
                                                    ),
                                                    child: Image.memory(
                                                      widget.photo!,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, _, _) =>
                                                          const ColoredBox(
                                                            color: forest,
                                                          ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                const ColoredBox(color: forest),
                                              DecoratedBox(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.black.withValues(
                                                        alpha: 0.14,
                                                      ),
                                                      Colors.transparent,
                                                      Colors.black.withValues(
                                                        alpha: 0.32,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // Refined gliding scan beam with soft trailing aurora
                                              if (widget.processing)
                                                Positioned(
                                                  top: 14 + (t * (frameH - 36)),
                                                  left: 14,
                                                  right: 14,
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        height: 2,
                                                        decoration: BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                99,
                                                              ),
                                                          gradient: LinearGradient(
                                                            colors: [
                                                              Colors.white
                                                                  .withValues(
                                                                    alpha: 0,
                                                                  ),
                                                              lime.withValues(
                                                                alpha: 0.95,
                                                              ),
                                                              Colors.white,
                                                              lime.withValues(
                                                                alpha: 0.95,
                                                              ),
                                                              Colors.white
                                                                  .withValues(
                                                                    alpha: 0,
                                                                  ),
                                                            ],
                                                          ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: lime
                                                                  .withValues(
                                                                    alpha: 0.65,
                                                                  ),
                                                              blurRadius: 12,
                                                              spreadRadius: 1,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Container(
                                                        height: 34,
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            begin: Alignment
                                                                .topCenter,
                                                            end: Alignment
                                                                .bottomCenter,
                                                            colors: [
                                                              lime.withValues(
                                                                alpha: 0.2,
                                                              ),
                                                              lime.withValues(
                                                                alpha: 0,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 30),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.processing) ...[
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: lime.withValues(
                                              alpha: 0.45 + (t * 0.55),
                                            ),
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: lime.withValues(
                                                  alpha: 0.6 * t,
                                                ),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                      ],
                                      Flexible(
                                        child: LocalizedText(
                                          widget.processing
                                              ? _scanStages[_stage]
                                              : 'Review your meal',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                LocalizedText(
                                  widget.aiConfigured
                                      ? 'Estimating portions & nutrition'
                                      : 'Recognition stays on your device.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.62),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoRecoverySheet extends StatelessWidget {
  const _PhotoRecoverySheet({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: lime.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: lime, size: 27),
            ),
            const SizedBox(height: 18),
            LocalizedText(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            LocalizedText(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'retake'),
                icon: const Icon(Icons.camera_alt_outlined, size: 19),
                label: const LocalizedText('Retake photo'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(context, 'gallery'),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const LocalizedText('Choose photo'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(context, 'manual'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const LocalizedText('Type instead'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MealClarificationSheet extends StatefulWidget {
  const _MealClarificationSheet({required this.clarifications});

  final List<MealClarification> clarifications;

  @override
  State<_MealClarificationSheet> createState() =>
      _MealClarificationSheetState();
}

class _MealClarificationSheetState extends State<_MealClarificationSheet> {
  late final List<String?> selections = List.filled(
    widget.clarifications.length,
    null,
  );
  late final List<TextEditingController> customAnswers = List.generate(
    widget.clarifications.length,
    (_) => TextEditingController(),
  );

  bool get complete {
    for (var i = 0; i < selections.length; i++) {
      if (selections[i] == null && customAnswers[i].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    for (final controller in customAnswers) {
      controller.dispose();
    }
    super.dispose();
  }

  void submit() {
    final answers = <String>[];
    for (var i = 0; i < widget.clarifications.length; i++) {
      final clarification = widget.clarifications[i];
      final custom = customAnswers[i].text.trim();
      final answer = custom.isNotEmpty ? custom : selections[i]!;
      answers.add(
        answer == 'Not sure'
            ? 'For "${clarification.question}", the user is not sure. Keep a cautious generic estimate without assuming a specific ingredient.'
            : 'For "${clarification.question}", the user answered "$answer".',
      );
    }
    Navigator.pop(context, answers);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          14,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const LocalizedText(
              'One quick detail',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            LocalizedText(
              'Some ingredients are hidden in the photo and can change the nutrition estimate.',
              style: TextStyle(color: context.kayleoMuted),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < widget.clarifications.length; i++) ...[
              LocalizedText(
                widget.clarifications[i].question,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.clarifications[i].reason.isNotEmpty) ...[
                const SizedBox(height: 4),
                LocalizedText(
                  widget.clarifications[i].reason,
                  style: TextStyle(fontSize: 12.5, color: context.kayleoMuted),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in {
                    ...widget.clarifications[i].options,
                    'Not sure',
                  })
                    ChoiceChip(
                      label: LocalizedText(option),
                      selected:
                          selections[i] == option &&
                          customAnswers[i].text.trim().isEmpty,
                      onSelected: (_) => setState(() {
                        selections[i] = option;
                        customAnswers[i].clear();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: customAnswers[i],
                maxLength: 80,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: context.l10n.translate('Your answer'),
                  hintText: context.l10n.translate('Type your answer'),
                ),
                onChanged: (value) => setState(() {
                  if (value.trim().isNotEmpty) selections[i] = null;
                }),
              ),
              if (i != widget.clarifications.length - 1)
                const SizedBox(height: 14),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: complete ? submit : null,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const LocalizedText('Update my estimate'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, <String>[]),
                child: const LocalizedText('Use current estimate'),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        const LocalizedText(
          'Clarify Your Meal',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        LocalizedText(
          'Did you mean ${widget.result.first.name} (${(widget.result.first.confidence * 100).round()}%) or ${widget.result.second.name} (${(widget.result.second.confidence * 100).round()}%)?',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in [widget.result.first, widget.result.second])
              ChoiceChip(
                label: LocalizedText(
                  '${p.name} · ${(p.confidence * 100).round()}%',
                ),
                selected: identical(selected, p),
                onSelected: (_) => setState(() => selected = p),
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: custom,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: context.l10n.translate('A different food name'),
          ),
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
            child: const LocalizedText('Confirm food'),
          ),
        ),
      ],
    ),
  );
}

class _PlateItemEntry {
  _PlateItemEntry({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.baseServingGrams,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.fiberPer100g,
    this.basisUnit = 'g',
  });

  final String id;
  String name;
  double quantity;
  String unit;
  double baseServingGrams;
  double caloriesPer100g;
  double proteinPer100g;
  double carbsPer100g;
  double fatPer100g;
  double fiberPer100g;
  double share = 1.0;
  String basisUnit;

  Food toFoodSnapshot() => Food(
    id: id,
    name: name,
    aliases: const [],
    per100g: Nutrients(
      caloriesPer100g,
      proteinPer100g,
      carbsPer100g,
      fatPer100g,
      fiberPer100g,
    ),
    servingGrams: baseServingGrams > 0 ? baseServingGrams : 100,
    unit: unit == 'g' || unit == 'ml' || unit == 'oz' ? 'serving' : unit,
    nutritionBasisUnit: basisUnit,
    source: 'Kayleo plate item',
  );

  double get unitFactor => portionFactor(toFoodSnapshot(), unit);
  double get rawGrams => quantity * unitFactor;
  double get eatenGrams => (rawGrams * share).clamp(1.0, 3000.0);
  double get eatenCalories => caloriesPer100g * eatenGrams / 100.0;
  double get eatenProtein => proteinPer100g * eatenGrams / 100.0;
  double get eatenCarbs => carbsPer100g * eatenGrams / 100.0;
  double get eatenFat => fatPer100g * eatenGrams / 100.0;
  double get eatenFiber => fiberPer100g * eatenGrams / 100.0;
}

class FoodConfirmationScreen extends StatefulWidget {
  const FoodConfirmationScreen({
    super.key,
    required this.state,
    required this.food,
    this.photo,
    this.confidence,
    this.service,
  });
  final AppState state;
  final FoodNutrition food;
  final Uint8List? photo;
  final double? confidence;
  final FoodAIService? service;
  @override
  State<FoodConfirmationScreen> createState() => _FoodConfirmationScreenState();
}

class _FoodConfirmationScreenState extends State<FoodConfirmationScreen> {
  late double amount = widget.food.servingGrams;
  final mealId = newId();
  Map<String, dynamic>? portion;
  late String unit = widget.food.unit;
  final form = GlobalKey<FormState>();
  late final values = widget.food.values
      .map((n) => TextEditingController(text: n?.toString() ?? ''))
      .toList();
  final _missingFoodController = TextEditingController();
  late List<_PlateItemEntry> _plateItems;
  late FoodNutrition _reviewFood;
  bool saving = false, refining = false;
  String? error;
  static const labels = [
    'Calories (kcal)',
    'Protein (g)',
    'Carbohydrates (g)',
    'Fats (g)',
    'Dietary fiber (g)',
  ];

  @override
  void initState() {
    super.initState();
    _reviewFood = widget.food;
    _plateItems = _buildInitialPlateItems();
  }

  @override
  void dispose() {
    for (final c in values) {
      c.dispose();
    }
    _missingFoodController.dispose();
    super.dispose();
  }

  static ({double quantity, String unit, double baseGrams})
  _parsePortionLocalizedText(
    String rawPortion,
    double totalGrams,
    String basisUnit,
  ) {
    final lower = rawPortion.trim().toLowerCase();
    final m = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(pieces?|pcs?|servings?|bowls?|cups?|slices?|plates?|tbsp|tablespoons?|oz|ounces?|g|grams?|ml|glass(?:es)?)?\b',
    ).firstMatch(lower);
    if (m != null) {
      final q = double.tryParse(m.group(1)!) ?? 1.0;
      final uRaw = m.group(2) ?? '';
      String u = 'serving';
      if (uRaw.startsWith('piece') || uRaw.startsWith('pc')) {
        u = 'piece';
      } else if (uRaw.startsWith('bowl')) {
        u = 'bowl';
      } else if (uRaw.startsWith('cup')) {
        u = 'cup';
      } else if (uRaw.startsWith('slice')) {
        u = 'slice';
      } else if (uRaw.startsWith('tb') || uRaw.startsWith('table')) {
        u = 'tbsp';
      } else if (uRaw.startsWith('oz') || uRaw.startsWith('ounce')) {
        u = 'oz';
      } else if (uRaw == 'g' || uRaw.startsWith('gram')) {
        u = 'g';
      } else if (uRaw == 'ml') {
        u = 'ml';
      } else if (uRaw.startsWith('glass')) {
        u = 'glass';
      } else if (uRaw.startsWith('serving') || uRaw.startsWith('plate')) {
        u = 'serving';
      }
      if (u == 'g' || u == 'ml') {
        return (quantity: totalGrams, unit: u, baseGrams: 100);
      }
      if (u == 'oz') {
        return (quantity: totalGrams / 28.3495, unit: 'oz', baseGrams: 100);
      }
      final safeQ = q > 0 ? q : 1.0;
      return (
        quantity: safeQ,
        unit: u,
        baseGrams: (totalGrams / safeQ).clamp(10.0, 1000.0),
      );
    }
    return (
      quantity: 1.0,
      unit: basisUnit == 'ml' ? 'cup' : 'serving',
      baseGrams: totalGrams.clamp(10.0, 1000.0),
    );
  }

  List<_PlateItemEntry> _buildInitialPlateItems([FoodNutrition? updated]) {
    final food = updated ?? _reviewFood;
    if (food.plateItems.isNotEmpty) {
      return [
        for (var i = 0; i < food.plateItems.length; i++)
          () {
            final item = food.plateItems[i];
            final g = item.grams > 0 ? item.grams : 100.0;
            final factor = 100.0 / g;
            final parsed = _parsePortionLocalizedText(item.portion, g, unit);
            return _PlateItemEntry(
              id: '${food.id}:item:$i',
              name: _capitalizeFoodName(item.name),
              quantity: parsed.quantity,
              unit: parsed.unit,
              baseServingGrams: parsed.baseGrams,
              caloriesPer100g: item.calories * factor,
              proteinPer100g: item.proteinGrams * factor,
              carbsPer100g: item.carbsGrams * factor,
              fatPer100g: item.fatGrams * factor,
              fiberPer100g: item.fiberGrams * factor,
              basisUnit: unit,
            );
          }(),
      ];
    }
    final cals = food.values[0] ?? 130.0;
    final pro = food.values[1] ?? 4.0;
    final carb = food.values[2] ?? 22.0;
    final fat = food.values[3] ?? 3.0;
    final fib = food.values.length > 4 ? (food.values[4] ?? 2.0) : 2.0;
    return [
      _PlateItemEntry(
        id: food.id,
        name: _capitalizeFoodName(food.name),
        quantity: food.servingGrams,
        unit: unit,
        baseServingGrams: food.servingGrams > 0 ? food.servingGrams : 100.0,
        caloriesPer100g: cals,
        proteinPer100g: pro,
        carbsPer100g: carb,
        fatPer100g: fat,
        fiberPer100g: fib,
        basisUnit: unit,
      ),
    ];
  }

  static String _capitalizeFoodName(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Food item';
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  String get _cleanDetails {
    if (_reviewFood.details.isEmpty) return '';
    final parts = _reviewFood.details
        .split(' · ')
        .where((p) => !p.trim().toLowerCase().startsWith('on your plate:'))
        .toList();
    return parts.join(' · ');
  }

  void _syncTotalsFromPlate() {
    if (_plateItems.isEmpty) return;
    var totalGrams = 0.0;
    var totalCals = 0.0;
    var totalPro = 0.0;
    var totalCarb = 0.0;
    var totalFat = 0.0;
    var totalFib = 0.0;
    for (final item in _plateItems) {
      totalGrams += item.eatenGrams;
      totalCals += item.eatenCalories;
      totalPro += item.eatenProtein;
      totalCarb += item.eatenCarbs;
      totalFat += item.eatenFat;
      totalFib += item.eatenFiber;
    }
    amount = totalGrams.clamp(1.0, 3000.0);
    if (_reviewFood.complete && amount > 0) {
      final factor = 100.0 / amount;
      final updated = [
        totalCals * factor,
        totalPro * factor,
        totalCarb * factor,
        totalFat * factor,
        totalFib * factor,
      ];
      for (var i = 0; i < values.length && i < updated.length; i++) {
        values[i].text = updated[i].toStringAsFixed(2);
      }
    }
  }

  void _scalePlateToTotalAmount(double newAmount) {
    final currentTotal = _plateItems.fold<double>(
      0.0,
      (sum, item) => sum + item.eatenGrams,
    );
    if (currentTotal > 0 && _plateItems.isNotEmpty) {
      final ratio = newAmount / currentTotal;
      for (final item in _plateItems) {
        item.quantity = (item.quantity * ratio).clamp(0.1, 3000.0);
      }
    }
    amount = newAmount;
  }

  void _stepPlateItem(_PlateItemEntry item, double delta) {
    final step = portionStepForUnit(item.unit);
    final minVal = step >= 25 ? 10.0 : 0.25;
    setState(() {
      item.quantity = (item.quantity + delta * step).clamp(minVal, 3000.0);
      portion = null;
      _syncTotalsFromPlate();
    });
  }

  void _changePlateItemUnit(_PlateItemEntry item, String nextUnit) {
    if (item.unit == nextUnit) return;
    setState(() {
      final currentGrams = item.rawGrams;
      item.unit = nextUnit;
      final nextFactor = item.unitFactor;
      item.quantity = (currentGrams / (nextFactor > 0 ? nextFactor : 1.0))
          .clamp(0.25, 3000.0);
      portion = null;
      _syncTotalsFromPlate();
    });
  }

  Future<void> _editPlateItemPortion(_PlateItemEntry item) async {
    final snap = item.toFoodSnapshot();
    final mealItem = MealItem(
      foodId: snap.id,
      grams: item.eatenGrams,
      snapshot: snap,
      portion: {
        'quantity': item.quantity,
        'unit': item.unit,
        'share': item.share,
      },
    );
    final updated = await editPortion(context, mealItem);
    if (!mounted || updated == null) return;
    setState(() {
      item.quantity = (updated['quantity'] as num).toDouble();
      item.unit = updated['unit'] as String;
      item.share = (updated['share'] as num? ?? 1.0).toDouble();
      if (_plateItems.length == 1) {
        portion = updated;
      } else {
        portion = null;
      }
      _syncTotalsFromPlate();
    });
  }

  void _applyQuickMealShare(double nextShare) {
    setState(() {
      for (final item in _plateItems) {
        item.share = nextShare;
      }
      _syncTotalsFromPlate();
      if (nextShare < 1.0) {
        final rawTotal = _plateItems.fold<double>(
          0.0,
          (s, i) => s + i.rawGrams,
        );
        portion = {'quantity': rawTotal, 'unit': unit, 'share': nextShare};
      } else {
        portion = null;
      }
    });
  }

  Future<void> _addMissingFoodByLocalizedText([String? presetText]) async {
    final rawInput = (presetText ?? _missingFoodController.text).trim();
    if (rawInput.isEmpty) return;
    if (presetText == null &&
        widget.photo != null &&
        widget.service?.geminiConfigured == true) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        refining = true;
        error = null;
      });
      try {
        final refined = await widget.service!.refineMealPhoto(
          widget.photo!,
          correction: rawInput,
          previous: _reviewFood,
        );
        if (!mounted) return;
        setState(() {
          _reviewFood = refined;
          _plateItems = _buildInitialPlateItems(refined);
          amount = refined.servingGrams;
          for (var i = 0; i < values.length && i < refined.values.length; i++) {
            values[i].text = refined.values[i]?.toStringAsFixed(2) ?? '';
          }
          _missingFoodController.clear();
          portion = null;
          _syncTotalsFromPlate();
        });
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          error = e.toString().replaceFirst(
            RegExp(r'^[A-Za-z]+(?:Error|Exception)?:\s*'),
            '',
          );
        });
        return;
      } finally {
        if (mounted) setState(() => refining = false);
      }
    }
    final segments = rawInput
        .split(RegExp(r'\s*(?:,|\+|(?:\band\b))\s*', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return;

    final addedEntries = <_PlateItemEntry>[];
    for (final segment in segments) {
      final analysis = MealEngine.parse(segment);
      if (!analysis.unmatched && analysis.meal.items.isNotEmpty) {
        for (final matched in analysis.meal.items) {
          final f = mealItemFood(matched);
          final q = (matched.portion?['quantity'] as num?)?.toDouble() ?? 1.0;
          final u = (matched.portion?['unit'] as String?) ?? f.unit;
          addedEntries.add(
            _PlateItemEntry(
              id: '${f.id}:${DateTime.now().microsecondsSinceEpoch}:${addedEntries.length}',
              name: f.name,
              quantity: q,
              unit: u,
              baseServingGrams: f.servingGrams,
              caloriesPer100g: f.per100g.calories,
              proteinPer100g: f.per100g.protein,
              carbsPer100g: f.per100g.carbs,
              fatPer100g: f.per100g.fat,
              fiberPer100g: f.per100g.fiber ?? 1.5,
              basisUnit: f.nutritionBasisUnit,
            ),
          );
        }
      } else {
        addedEntries.add(_parseCustomTypedFood(segment));
      }
    }

    setState(() {
      _plateItems.addAll(addedEntries);
      if (presetText == null) {
        _missingFoodController.clear();
      }
      portion = null;
      _syncTotalsFromPlate();
    });
  }

  _PlateItemEntry _parseCustomTypedFood(String text) {
    var working = text.trim();
    const wordNumbers = {
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'half': '0.5',
      'a': '1',
      'an': '1',
    };
    final tokens = working.split(RegExp(r'\s+'));
    if (tokens.isNotEmpty &&
        wordNumbers.containsKey(tokens.first.toLowerCase())) {
      tokens[0] = wordNumbers[tokens.first.toLowerCase()]!;
      working = tokens.join(' ');
    }

    double quantity = 1.0;
    String itemUnit = 'piece';
    String foodName = working;

    final leadMatch = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(pieces?|pcs?|servings?|bowls?|cups?|slices?|tbsp|tablespoons?|oz|ounces?|g|grams?|ml|glass(?:es)?)?\s+(?:of\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(working);
    final trailMatch = RegExp(
      r'^(.+?)\s+(\d+(?:\.\d+)?)\s*(pieces?|pcs?|servings?|bowls?|cups?|slices?|tbsp|tablespoons?|oz|ounces?|g|grams?|ml|glass(?:es)?)?$',
      caseSensitive: false,
    ).firstMatch(working);

    String rawUnit = '';
    if (leadMatch != null) {
      quantity = double.tryParse(leadMatch.group(1)!) ?? 1.0;
      rawUnit = (leadMatch.group(2) ?? '').toLowerCase();
      foodName = leadMatch.group(3)!.trim();
    } else if (trailMatch != null) {
      foodName = trailMatch.group(1)!.trim();
      quantity = double.tryParse(trailMatch.group(2)!) ?? 1.0;
      rawUnit = (trailMatch.group(3) ?? '').toLowerCase();
    }

    if (rawUnit.startsWith('g')) {
      itemUnit = 'g';
    } else if (rawUnit.startsWith('oz') || rawUnit.startsWith('ounce')) {
      itemUnit = 'oz';
    } else if (rawUnit.startsWith('bowl')) {
      itemUnit = 'bowl';
    } else if (rawUnit.startsWith('cup')) {
      itemUnit = 'cup';
    } else if (rawUnit.startsWith('slice')) {
      itemUnit = 'slice';
    } else if (rawUnit.startsWith('tb') || rawUnit.startsWith('table')) {
      itemUnit = 'tbsp';
    } else if (rawUnit.startsWith('serv')) {
      itemUnit = 'serving';
    } else if (rawUnit.startsWith('piece') || rawUnit.startsWith('pc')) {
      itemUnit = 'piece';
    } else {
      final lowerName = foodName.toLowerCase();
      if (lowerName.contains('soup') ||
          lowerName.contains('dal') ||
          lowerName.contains('curd') ||
          lowerName.contains('yogurt') ||
          lowerName.contains('salad') ||
          lowerName.contains('curry')) {
        itemUnit = 'bowl';
      } else if (lowerName.contains('tea') ||
          lowerName.contains('coffee') ||
          lowerName.contains('milk') ||
          lowerName.contains('juice') ||
          lowerName.contains('rice')) {
        itemUnit = 'cup';
      } else if (lowerName.contains('ghee') ||
          lowerName.contains('oil') ||
          lowerName.contains('butter') ||
          lowerName.contains('chutney') ||
          lowerName.contains('sauce') ||
          lowerName.contains('pickle') ||
          lowerName.contains('achar')) {
        itemUnit = 'tbsp';
      } else {
        itemUnit = 'piece';
      }
    }

    final lower = foodName.toLowerCase();
    double baseServingGrams = 60.0;
    double cal100 = 165.0,
        pro100 = 7.0,
        carb100 = 22.0,
        fat100 = 5.5,
        fib100 = 2.0;

    if (lower.contains('egg')) {
      baseServingGrams = 50;
      cal100 = 155;
      pro100 = 13;
      carb100 = 1.1;
      fat100 = 11;
      fib100 = 0;
    } else if (lower.contains('roti') ||
        lower.contains('chapati') ||
        lower.contains('phulka')) {
      baseServingGrams = 40;
      cal100 = 297;
      pro100 = 9.8;
      carb100 = 55;
      fat100 = 3.7;
      fib100 = 4.5;
    } else if (lower.contains('naan') || lower.contains('paratha')) {
      baseServingGrams = 80;
      cal100 = 310;
      pro100 = 8.5;
      carb100 = 48;
      fat100 = 9.5;
      fib100 = 3.0;
    } else if (lower.contains('dal') || lower.contains('lentil')) {
      baseServingGrams = 180;
      cal100 = 105;
      pro100 = 6.0;
      carb100 = 16.0;
      fat100 = 2.0;
      fib100 = 4.0;
    } else if (lower.contains('salad') ||
        lower.contains('cucumber') ||
        lower.contains('veggie')) {
      baseServingGrams = 100;
      cal100 = 35;
      pro100 = 1.5;
      carb100 = 6.5;
      fat100 = 0.4;
      fib100 = 2.5;
    } else if (lower.contains('curd') ||
        lower.contains('yogurt') ||
        lower.contains('dahi')) {
      baseServingGrams = 150;
      cal100 = 61;
      pro100 = 3.5;
      carb100 = 4.7;
      fat100 = 3.3;
      fib100 = 0;
    } else if (lower.contains('ghee') ||
        lower.contains('oil') ||
        lower.contains('butter')) {
      baseServingGrams = 14;
      cal100 = 884;
      pro100 = 0;
      carb100 = 0;
      fat100 = 100;
      fib100 = 0;
    } else if (lower.contains('tea') || lower.contains('chai')) {
      baseServingGrams = 180;
      cal100 = 42;
      pro100 = 1.6;
      carb100 = 5.5;
      fat100 = 1.5;
      fib100 = 0;
    } else if (lower.contains('chicken') ||
        lower.contains('meat') ||
        lower.contains('fish') ||
        lower.contains('paneer')) {
      baseServingGrams = 100;
      cal100 = 195;
      pro100 = 22;
      carb100 = 3;
      fat100 = 10;
      fib100 = 0.5;
    }

    return _PlateItemEntry(
      id: 'custom:${DateTime.now().microsecondsSinceEpoch}',
      name: _capitalizeFoodName(foodName),
      quantity: quantity,
      unit: itemUnit,
      baseServingGrams: baseServingGrams,
      caloriesPer100g: cal100,
      proteinPer100g: pro100,
      carbsPer100g: carb100,
      fatPer100g: fat100,
      fiberPer100g: fib100,
      basisUnit: unit,
    );
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final n = values.map((c) => double.tryParse(c.text)).toList();
      final source = _reviewFood.toFood(n);
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
            (_reviewFood.complete ? '' : ' · label values completed by you'),
        sourceUrl: source.sourceUrl,
        barcode: source.barcode,
      );
      final mealItems = _plateItems.length <= 1
          ? [
              MealItem(
                foodId: food.id,
                grams: amount,
                snapshot: food,
                portion: portion,
              ),
            ]
          : [
              for (final entry in _plateItems)
                MealItem(
                  foodId: entry.id,
                  grams: entry.eatenGrams,
                  snapshot: entry.toFoodSnapshot(),
                  portion: {
                    'quantity': entry.quantity,
                    'unit': entry.unit,
                    'share': entry.share,
                  },
                ),
            ];
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
          items: mealItems,
          photo: widget.photo,
          input: _reviewFood.id.startsWith('kayleo:')
              ? 'Kayleo Vision'
              : widget.confidence == null
              ? 'Food lookup'
              : 'On-device camera',
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
  Widget build(BuildContext context) {
    final currentShare =
        (portion?['share'] as num?)?.toDouble() ??
        (_plateItems.isNotEmpty ? _plateItems.first.share : 1.0);
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Review your meal')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LocalizedText(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving || refining ? null : save,
                  child: LocalizedText(
                    saving ? 'Saving…' : 'Confirm & Log Meal',
                  ),
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
                  const SizedBox(height: 14),
                  LocalizedText(
                    _reviewFood.name,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tag(
                        _reviewFood.id.startsWith('kayleo:')
                            ? 'KAYLEO AI'
                            : _reviewFood.estimated
                            ? 'LOCAL ESTIMATE'
                            : _reviewFood.source.startsWith('USDA')
                            ? 'USDA DATA'
                            : 'PRODUCT LABEL',
                      ),
                      if (widget.confidence != null)
                        Tag('MODEL ${(widget.confidence! * 100).round()}%'),
                      if (currentShare < 0.99)
                        Tag(
                          'SHARED (${(currentShare * 100).round()}% EATEN)',
                          color: lime,
                          textColor: forest,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LocalizedText(
                    _reviewFood.source,
                    style: TextStyle(color: context.kayleoMuted, fontSize: 13),
                  ),
                  if (_cleanDetails.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.kayleoSurfaces.soft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 16,
                            color: context.kayleoPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: LocalizedText(
                              _cleanDetails,
                              style: TextStyle(
                                color: context.kayleoText,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  LocalizedText(
                    'Check that the food, brand and preparation match your meal.',
                    style: TextStyle(
                      color: context.kayleoMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // OVERALL PORTION & SHARING SECTION
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      LocalizedText(
                        'Portion: ${amount.round()} $unit',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      LocalizedText(
                        '${(amount / 28.3495).toStringAsFixed(1)} oz',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.kayleoMuted,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: amount.clamp(
                      50,
                      math.max(800, amount.ceilToDouble()),
                    ),
                    min: 50,
                    max: math.max(800, amount.ceilToDouble()),
                    divisions: math.max(150, (amount.ceil() - 50) ~/ 5),
                    label: '${amount.round()} $unit',
                    onChanged: saving
                        ? null
                        : (v) => setState(() {
                            _scalePlateToTotalAmount(v);
                            portion = null;
                          }),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.straighten),
                    label: const LocalizedText(
                      'Custom amount or shared portion',
                    ),
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
                              final newAmount = consumedPortion(
                                item.snapshot!,
                                p,
                              );
                              _scalePlateToTotalAmount(newAmount);
                              portion = p;
                            });
                          },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      LocalizedText(
                        'Shared:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.kayleoMuted,
                        ),
                      ),
                      for (final preset in const [
                        (1.0, 'Just me'),
                        (0.5, '1/2 (2 people)'),
                        (1 / 3, '1/3 (3 people)'),
                        (0.25, '1/4 (4 people)'),
                      ])
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: LocalizedText(preset.$2),
                          selected: (currentShare - preset.$1).abs() < 0.02,
                          onSelected: saving
                              ? null
                              : (_) => _applyQuickMealShare(preset.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // ON YOUR PLATE INTERACTIVE WIDGET SECTION
                  Row(
                    children: [
                      const Expanded(
                        child: LocalizedText(
                          'On your plate',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      Tag(
                        '${_plateItems.length} ${_plateItems.length == 1 ? 'ITEM' : 'ITEMS'}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LocalizedText(
                    'Tap + or − to adjust each item, switch units (piece, g, oz, bowl), or add missing foods below.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.kayleoMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < _plateItems.length; index++)
                    _PlateItemCard(
                      key: ValueKey(_plateItems[index].id),
                      index: index,
                      item: _plateItems[index],
                      canRemove: _plateItems.length > 1,
                      onDecrement: () => _stepPlateItem(_plateItems[index], -1),
                      onIncrement: () => _stepPlateItem(_plateItems[index], 1),
                      onSelectUnit: (u) =>
                          _changePlateItemUnit(_plateItems[index], u),
                      onEditPortion: () =>
                          _editPlateItemPortion(_plateItems[index]),
                      onRemove: () => setState(() {
                        _plateItems.removeAt(index);
                        portion = null;
                        _syncTotalsFromPlate();
                      }),
                    ),
                  const SizedBox(height: 6),
                  // ADD MISSING FOOD BY TEXT
                  Panel(
                    padding: 14,
                    color: context.kayleoSurfaces.soft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              size: 18,
                              color: context.kayleoPrimary,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: LocalizedText(
                                'Something missing or incorrect?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('add-missing-food-input'),
                                controller: _missingFoodController,
                                textInputAction: TextInputAction.done,
                                enabled: !refining,
                                onSubmitted: (_) =>
                                    _addMissingFoodByLocalizedText(),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: context.l10n.translate(
                                    'Type e.g. "2 roti, 1 boiled egg, 100g curd"…',
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              key: const Key('add-missing-food-button'),
                              onPressed: saving || refining
                                  ? null
                                  : () => _addMissingFoodByLocalizedText(),
                              icon: refining
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 18,
                                    ),
                              label: LocalizedText(
                                refining
                                    ? 'Applying details…'
                                    : 'Refine with AI',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final quick in const [
                              ('1 boiled egg', '+ 1 Egg'),
                              ('1 roti', '+ 1 Roti'),
                              ('1 bowl dal', '+ 1 Bowl Dal'),
                              ('1 cup steamed rice', '+ 1 Cup Rice'),
                              ('1 bowl green salad', '+ Salad'),
                              ('1 tbsp ghee', '+ 1 Tbsp Ghee'),
                            ])
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: LocalizedText(
                                  quick.$2,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: saving
                                    ? null
                                    : () => _addMissingFoodByLocalizedText(
                                        quick.$1,
                                      ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.food.source.startsWith('Open Food Facts')) ...[
                    const SizedBox(height: 12),
                    const LocalizedText(
                      'Check the label’s nutrition basis. Volume is not converted to mass.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final u in ['g', 'ml'])
                          ChoiceChip(
                            label: LocalizedText(
                              u == 'g' ? 'Per 100 g' : 'Per 100 ml',
                            ),
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
                  LocalizedText(
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
                            labelText: context.l10n.translate(labels[i]),
                            helperText: i == 4
                                ? context.l10n.translate(
                                    'Optional when the label has no fiber value.',
                                  )
                                : widget.food.values[i] == null
                                ? context.l10n.translate(
                                    'Missing: enter the label value.',
                                  )
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
                                LocalizedText(
                                  labels[i].split(' (').first,
                                  style: TextStyle(color: context.kayleoMuted),
                                ),
                                LocalizedText(
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
                  LocalizedText(
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
}

class _PlateItemCard extends StatelessWidget {
  const _PlateItemCard({
    super.key,
    required this.index,
    required this.item,
    required this.canRemove,
    required this.onDecrement,
    required this.onIncrement,
    required this.onSelectUnit,
    required this.onEditPortion,
    required this.onRemove,
  });

  final int index;
  final _PlateItemEntry item;
  final bool canRemove;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String> onSelectUnit;
  final VoidCallback onEditPortion;
  final VoidCallback onRemove;

  static const _quickUnits = [
    'serving',
    'piece',
    'bowl',
    'cup',
    'slice',
    'g',
    'oz',
    'tbsp',
  ];

  @override
  Widget build(BuildContext context) {
    final qtyText = formatPortionQuantity(item.quantity);
    final unitLabel =
        item.quantity > 1 && !['g', 'ml', 'oz', 'tbsp'].contains(item.unit)
        ? '${item.unit}s'
        : item.unit;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        padding: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBox(Icons.restaurant_menu_rounded, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        item.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      LocalizedText(
                        '${item.eatenGrams.round()} ${item.basisUnit} · '
                        '${item.eatenCalories.round()} kcal'
                        '${item.share < 0.99 ? ' · ${(item.share * 100).round()}% share' : ''}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.kayleoPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onEditPortion,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.group_outlined, size: 15),
                  label: const LocalizedText(
                    'Share / Edit',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                if (canRemove)
                  IconButton(
                    tooltip: context.l10n.translate('Remove ${item.name}'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: context.kayleoMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Readable macro pills for this item
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _MacroChip(
                  label: 'Protein',
                  value: '${item.eatenProtein.round()}g',
                  color: forest,
                ),
                _MacroChip(
                  label: 'Carbs',
                  value: '${item.eatenCarbs.round()}g',
                  color: orange,
                ),
                _MacroChip(
                  label: 'Fat',
                  value: '${item.eatenFat.round()}g',
                  color: blue,
                ),
                _MacroChip(
                  label: 'Fiber',
                  value: '${item.eatenFiber.round()}g',
                  color: context.kayleoMuted,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Quantity Stepper (- / +) and Unit Selector
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: context.kayleoSurfaces.soft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.kayleoSurfaces.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('plate-item-dec-$index'),
                        tooltip: context.l10n.translate(
                          'Decrease ${item.name}',
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: onDecrement,
                        icon: const Icon(Icons.remove_rounded, size: 18),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: LocalizedText(
                          '$qtyText $unitLabel',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        key: Key('plate-item-inc-$index'),
                        tooltip: context.l10n.translate(
                          'Increase ${item.name}',
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: onIncrement,
                        icon: const Icon(Icons.add_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
                for (final u in _quickUnits)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: LocalizedText(
                      u,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    selected: item.unit == u,
                    onSelected: (_) => onSelectUnit(u),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  const _MacroChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: LocalizedText(
      '$label $value',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: context.kayleoText,
      ),
    ),
  );
}
