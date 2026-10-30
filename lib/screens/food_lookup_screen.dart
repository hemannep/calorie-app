import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../features/capture_input_layout.dart';
import '../services/food_ai_service.dart';
import 'food_camera_screen.dart';

class FoodLookupScreen extends StatefulWidget {
  const FoodLookupScreen({
    super.key,
    required this.state,
    this.barcode = false,
    this.embedded = false,
    this.bottomInset = 0,
    this.onCameraReleased,
  });
  final AppState state;
  final bool barcode;
  final bool embedded;
  final double bottomInset;
  final VoidCallback? onCameraReleased;
  @override
  State<FoodLookupScreen> createState() => _FoodLookupScreenState();
}

class _FoodLookupScreenState extends State<FoodLookupScreen> {
  final service = FoodAIService(), query = TextEditingController();
  List<FoodNutrition> results = [];
  String? error;
  bool busy = false;
  bool embeddedScanning = true;
  List<String> unavailableSources = [];
  int generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.barcode && !widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scan();
      });
    }
  }

  @override
  void dispose() {
    generation++;
    query.dispose();
    unawaited(service.dispose().catchError((_) {}));
    super.dispose();
  }

  Future<void> search() async {
    if (busy) return;
    final token = ++generation;
    setState(() {
      busy = true;
      error = null;
      results = [];
    });
    try {
      final combined = widget.barcode
          ? null
          : await service.searchAll(query.text);
      final found = widget.barcode
          ? [await service.lookupBarcode(query.text)]
                .whereType<FoodNutrition>()
                .toList()
          : combined!.foods;
      if (!mounted || token != generation) return;
      setState(() {
        results = found;
        unavailableSources = combined?.unavailableSources ?? [];
        error = found.isEmpty
            ? 'No matching food found. Try a more specific food, dish, or brand.'
            : null;
      });
    } catch (e) {
      if (mounted && token == generation) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  Future<void> scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ProductBarcodeScreen()),
    );
    if (!mounted || code == null) return;
    query.text = code;
    await search();
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? _embeddedBarcode()
      : Scaffold(
          appBar: AppBar(
            title: LocalizedText(
              widget.barcode ? 'Scan a barcode' : 'Find your food',
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (widget.barcode)
                      FilledButton.icon(
                        onPressed: busy ? null : scan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const LocalizedText('Open barcode camera'),
                      ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: query,
                      maxLength: 100,
                      keyboardType: widget.barcode
                          ? TextInputType.number
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: context.l10n.translate(
                          widget.barcode ? 'Barcode number' : 'Search food',
                        ),
                        hintText: context.l10n.translate(
                          widget.barcode
                              ? 'Digits below the barcode'
                              : 'Food, dish, or brand',
                        ),
                      ),
                      onSubmitted: (_) => search(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy ? null : search,
                      icon: const Icon(Icons.search),
                      label: LocalizedText(
                        widget.barcode ? 'Find product' : 'Search foods',
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      LocalizedText(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (unavailableSources.isNotEmpty && !widget.barcode)
                      LocalizedText(
                        'Some sources are temporarily unavailable: ${unavailableSources.join(', ')}',
                      ),
                    for (final food in results)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Panel(
                          padding: 0,
                          child: ListTile(
                            title: LocalizedText(food.name),
                            subtitle: LocalizedText(
                              '${food.source}\n${food.values[0] == null ? 'Calories unavailable' : '${number(food.values[0]!)} kcal'} / 100 ${food.unit}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              final logged = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FoodConfirmationScreen(
                                    state: widget.state,
                                    food: food,
                                  ),
                                ),
                              );
                              if (context.mounted && logged == true) {
                                Navigator.pop(context, true);
                              }
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    LocalizedText(
                      'Open Food Facts · ODbL / DbCL community labels.\nUSDA FoodData Central · public domain.\nReview missing values and the product before logging.',
                      style: TextStyle(
                        color: context.kayleoMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

  Widget _embeddedBarcode() {
    if (embeddedScanning) {
      return ProductBarcodeScreen(
        embedded: true,
        bottomInset: widget.bottomInset,
        onReleased: widget.onCameraReleased,
        onCode: (code) {
          query.text = code;
          setState(() => embeddedScanning = false);
          search();
        },
      );
    }
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.bottomInset),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 24, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.l10n.translate('Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const Spacer(),
                  const Brand(light: true, size: 23),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const LocalizedText(
                    'Your product',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  LocalizedText(
                    query.text,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 24),
                  if (busy) const Center(child: CircularProgressIndicator()),
                  if (error != null)
                    LocalizedText(
                      error!,
                      style: const TextStyle(color: Color(0xFFF3C6B9)),
                    ),
                  for (final food in results)
                    Panel(
                      padding: 0,
                      child: ListTile(
                        title: LocalizedText(food.name),
                        subtitle: LocalizedText(
                          '${food.source} · Review nutrition and portion',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final logged = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FoodConfirmationScreen(
                                state: widget.state,
                                food: food,
                              ),
                            ),
                          );
                          if (mounted && logged == true) {
                            Navigator.pop(context, 'logged');
                          }
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(() => embeddedScanning = true),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const LocalizedText('Scan another barcode'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarcodeFramePainter extends CustomPainter {
  const _BarcodeFramePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const corner = 24.0, radius = 14.0;
    final path = Path()
      ..moveTo(0, corner)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..lineTo(corner, 0)
      ..moveTo(size.width - corner, 0)
      ..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, corner)
      ..moveTo(size.width, size.height - corner)
      ..lineTo(size.width, size.height - radius)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - radius,
        size.height,
      )
      ..lineTo(size.width - corner, size.height)
      ..moveTo(corner, size.height)
      ..lineTo(radius, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - radius)
      ..lineTo(0, size.height - corner);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BarcodeFramePainter oldDelegate) => false;
}

class ProductBarcodeScreen extends StatefulWidget {
  const ProductBarcodeScreen({
    super.key,
    this.embedded = false,
    this.onCode,
    this.bottomInset = 0,
    this.onReleased,
  });
  final bool embedded;
  final ValueChanged<String>? onCode;
  final double bottomInset;
  final VoidCallback? onReleased;
  @override
  State<ProductBarcodeScreen> createState() => _ProductBarcodeScreenState();
}

class _ProductBarcodeScreenState extends State<ProductBarcodeScreen>
    with WidgetsBindingObserver {
  final barcodeInput = TextEditingController();
  MobileScannerController? controller;
  Future<void> operations = Future.value();
  Timer? startTimer;
  Completer<void>? startCancellation;
  bool closing = false, starting = false, paused = false;
  String? error;
  static bool get supported =>
      kIsWeb ||
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!supported) {
      error = 'The barcode camera is unavailable on this platform. Enter the barcode instead.';
      return;
    }
    // 7.4.2's native web polling reader fails to stop its video tracks.
    if (kIsWeb) {
      MobileScannerPlatform.instance.setWebBarcodeReader(
        WebBarcodeReader.zxingJs,
      );
    }
    controller = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  void start() {
    if (closing || starting || paused || controller == null) return;
    final scanner = controller!;
    setState(() => starting = true);
    operations = operations.then((_) async {
      final cancelled = Completer<void>();
      final timedOut = Completer<void>();
      startCancellation = cancelled;
      startTimer = Timer(
        const Duration(seconds: 8),
        () => timedOut.completeError(
          TimeoutException('Barcode camera startup timed out.'),
        ),
      );
      try {
        await Future.any([scanner.start(), timedOut.future, cancelled.future]);
        if (closing || paused || !mounted || controller != scanner) {
          await _stop(scanner);
        } else if (error != null) {
          setState(() => error = null);
        }
        // Android's start call can resolve before the first SurfaceView frame,
        // especially just after another camera client was released. Keep the
        // startup treatment visible instead of briefly presenting a black UI.
        if (!closing && !paused && mounted && controller == scanner) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      } catch (failure) {
        await _stop(scanner);
        if (mounted) {
          setState(
            () => error = failure is TimeoutException
                ? 'The camera took too long to open. Tap retry, or enter the barcode below.'
                : 'The camera could not start. Tap retry, or enter the barcode below.',
          );
        }
      } finally {
        startTimer?.cancel();
        startTimer = null;
        if (startCancellation == cancelled) startCancellation = null;
        if (mounted) setState(() => starting = false);
      }
    });
  }

  void cancelPendingStart() {
    startTimer?.cancel();
    startTimer = null;
    final cancellation = startCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  Future<void> stop() async {
    final scanner = controller;
    if (scanner != null) await _stop(scanner);
  }

  Future<void> _stop(MobileScannerController scanner) async {
    try {
      await scanner.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> finish(String? code) async {
    if (closing) return;
    closing = true;
    cancelPendingStart();
    operations = operations.then((_) => stop());
    await operations;
    if (!mounted) return;
    if (widget.embedded && code != null) {
      widget.onCode?.call(code);
    } else {
      Navigator.pop(context, code);
    }
  }

  Future<void> retry() async {
    if (starting || closing || !supported) return;
    await operations;
    final previous = controller;
    controller = null;
    if (previous != null) {
      await _stop(previous);
      await previous.dispose();
    }
    if (!mounted) return;
    setState(() {
      controller = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
      error = null;
    });
    start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive &&
        starting &&
        !(controller?.value.hasCameraPermission ?? false)) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      paused = false;
      start();
    } else {
      paused = true;
      cancelPendingStart();
      operations = operations.then((_) => stop());
    }
  }

  @override
  void dispose() {
    closing = true;
    cancelPendingStart();
    barcodeInput.dispose();
    WidgetsBinding.instance.removeObserver(this);
    final scanner = controller;
    controller = null;
    unawaited(
      operations
          .then((_) async {
            if (scanner != null) {
              await _stop(scanner);
              await scanner.dispose();
            }
          })
          .catchError((_) {})
          .whenComplete(() => widget.onReleased?.call()),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? _embeddedCamera()
      : PopScope(
          canPop: closing,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) unawaited(finish(null));
          },
          child: Scaffold(
            appBar: AppBar(
              title: const LocalizedText('Scan a barcode'),
              leading: IconButton(
                tooltip: context.l10n.translate('Close barcode camera'),
                onPressed: () => finish(null),
                icon: const Icon(Icons.close),
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * .46,
                    child: error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LocalizedText(
                                    error!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  if (supported)
                                    FilledButton(
                                      onPressed: retry,
                                      child: const LocalizedText(
                                        'Retry camera',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                        : Stack(
                            alignment: Alignment.center,
                            children: [
                              if (controller != null)
                                MobileScanner(
                                  controller: controller,
                                  onDetect: (capture) {
                                    if (closing || paused || error != null) {
                                      return;
                                    }
                                    for (final b in capture.barcodes) {
                                      final code = b.rawValue ?? '';
                                      if (RegExp(r'^\d{8,14}$')
                                          .hasMatch(code)) {
                                        unawaited(finish(code));
                                        break;
                                      }
                                    }
                                  },
                                ),
                              IgnorePointer(
                                child: Container(
                                  width: 280,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: lime, width: 2),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        20,
                        24,
                        24 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const LocalizedText(
                            'Place the barcode inside the frame, or enter the number printed below it.',
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: barcodeInput,
                            keyboardType: TextInputType.number,
                            maxLength: 14,
                            decoration: InputDecoration(
                              labelText: context.l10n.translate(
                                'Barcode number',
                              ),
                              hintText: context.l10n.translate('8–14 digits'),
                              prefixIcon: Icon(Icons.numbers_rounded),
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              if (RegExp(r'^\d{8,14}$')
                                  .hasMatch(barcodeInput.text.trim())) {
                                finish(barcodeInput.text.trim());
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed:
                                RegExp(r'^\d{8,14}$')
                                    .hasMatch(barcodeInput.text.trim())
                                ? () => finish(barcodeInput.text.trim())
                                : null,
                            child: const LocalizedText('Find product'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

  Widget _embeddedCamera() => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: KayleoColors.camera),
      if (controller != null && error == null)
        MobileScanner(
          controller: controller,
          errorBuilder: (_, scannerError) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: LocalizedText(
                'Allow camera access to scan, or enter the barcode below.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          onDetect: (capture) {
            if (closing || paused || error != null) return;
            for (final barcode in capture.barcodes) {
              final code = barcode.rawValue ?? '';
              if (RegExp(r'^\d{8,14}$').hasMatch(code)) {
                unawaited(finish(code));
                break;
              }
            }
          },
        ),
      if (starting)
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0x730D120F),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: lime,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(height: 12),
                  LocalizedText(
                    'Starting camera…',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB30D120F), Color(0x330D120F), Color(0xF20D120F)],
            ),
          ),
        ),
      ),
      SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomInset),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 24, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: context.l10n.translate('Close'),
                      onPressed: () => finish(null),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    const Spacer(),
                    if (MediaQuery.viewInsetsOf(context).bottom > 0)
                      TextButton(
                        onPressed: () =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        child: const LocalizedText('Done'),
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
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          disabledBackgroundColor: Colors.white.withValues(
                            alpha: .07,
                          ),
                          disabledForegroundColor: Colors.white38,
                          textStyle: const TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed:
                            RegExp(r'^\d{8,14}$')
                                .hasMatch(barcodeInput.text.trim())
                            ? () => finish(barcodeInput.text.trim())
                            : null,
                        child: const LocalizedText('Find product'),
                      ),
                    ),
                  ),
                  content: LayoutBuilder(
                    key: const Key('capture-barcode-viewport'),
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
                          children: [
                            const LocalizedText(
                              'Scan a barcode',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.8,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const LocalizedText(
                              'Line up the barcode on your food label.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: 268,
                              height: (constraints.maxHeight * .28).clamp(
                                72,
                                148,
                              ),
                              child: const CustomPaint(
                                painter: _BarcodeFramePainter(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (error != null) ...[
                              LocalizedText(
                                supported ? error! : 'Camera unavailable. Enter the barcode below.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                              if (supported)
                                TextButton(
                                  onPressed: retry,
                                  child: const LocalizedText('Retry camera'),
                                ),
                              const SizedBox(height: 16),
                            ],
                            TextField(
                              key: const Key('capture-barcode-input'),
                              controller: barcodeInput,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              maxLength: 14,
                              decoration: InputDecoration(
                                labelText: context.l10n.translate(
                                  'Barcode number',
                                ),
                                hintText: context.l10n.translate(
                                  'Or enter 8–14 digits',
                                ),
                                counterText: '',
                                labelStyle: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                                hintStyle: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: .045),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: .1),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide(
                                    color: lime.withValues(alpha: .42),
                                  ),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) {
                                if (RegExp(r'^\d{8,14}$')
                                    .hasMatch(barcodeInput.text.trim())) {
                                  finish(barcodeInput.text.trim());
                                }
                              },
                            ),
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
    ],
  );
}
