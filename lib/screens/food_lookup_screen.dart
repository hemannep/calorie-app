import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../services/food_ai_service.dart';
import 'food_camera_screen.dart';

class FoodLookupScreen extends StatefulWidget {
  const FoodLookupScreen({
    super.key,
    required this.state,
    this.barcode = false,
  });
  final AppState state;
  final bool barcode;
  @override
  State<FoodLookupScreen> createState() => _FoodLookupScreenState();
}

class _FoodLookupScreenState extends State<FoodLookupScreen> {
  final service = FoodAIService(), query = TextEditingController();
  List<FoodNutrition> results = [];
  String? error;
  bool busy = false, usda = false;
  int generation = 0;
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
      final found = widget.barcode
          ? [await service.lookupBarcode(query.text)]
                .whereType<FoodNutrition>()
                .toList()
          : usda
          ? await service.searchUsda(query.text)
          : await service.fetchNutrition(query.text, localFallback: false);
      if (!mounted || token != generation) return;
      setState(() {
        results = found;
        error = found.isEmpty
            ? 'No matching food found. Try another name or type the label manually.'
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.barcode ? 'Scan a barcode' : 'Find your food'),
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
                  label: const Text('Open barcode camera'),
                ),
              if (!widget.barcode)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in [false, true])
                      ChoiceChip(
                        label: Text(
                          source ? 'USDA FoodData Central' : 'Open Food Facts',
                        ),
                        selected: usda == source,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => usda = source),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              TextField(
                controller: query,
                maxLength: 100,
                keyboardType: widget.barcode
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: widget.barcode ? 'Barcode number' : 'Search food',
                  hintText: widget.barcode
                      ? 'Digits below the barcode'
                      : 'Food, dish, or brand',
                ),
                onSubmitted: (_) => search(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : search,
                icon: const Icon(Icons.search),
                label: Text(widget.barcode ? 'Find product' : 'Search foods'),
              ),
              const SizedBox(height: 20),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final food in results)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Panel(
                    padding: 0,
                    child: ListTile(
                      title: Text(food.name),
                      subtitle: Text(
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
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Open Food Facts · ODbL / DbCL community labels.\nUSDA FoodData Central · public domain.\nReview missing values and the product before logging.',
                style: TextStyle(color: context.kayleoMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ProductBarcodeScreen extends StatefulWidget {
  const ProductBarcodeScreen({super.key});
  @override
  State<ProductBarcodeScreen> createState() => _ProductBarcodeScreenState();
}

class _ProductBarcodeScreenState extends State<ProductBarcodeScreen>
    with WidgetsBindingObserver {
  MobileScannerController? controller;
  Future<void> operations = Future.value();
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
    setState(() => starting = true);
    operations = operations.then((_) async {
      try {
        await controller!.start();
        if (closing || paused || !mounted) await stop();
      } catch (_) {
        if (mounted) {
          setState(
            () => error = 'Allow camera access in your device or browser settings, then try again. You can enter the barcode instead.',
          );
        }
      } finally {
        if (mounted) setState(() => starting = false);
      }
    });
  }

  Future<void> stop() async {
    try {
      await controller?.stop();
    } catch (_) {}
  }

  Future<void> finish(String? code) async {
    if (closing) return;
    closing = true;
    operations = operations.then((_) => stop());
    await operations;
    if (mounted) Navigator.pop(context, code);
  }

  Future<void> retry() async {
    if (starting || closing || !supported) return;
    await operations;
    await stop();
    await controller?.dispose();
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
      operations = operations.then((_) => stop());
    }
  }

  @override
  void dispose() {
    closing = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      operations
          .then((_) async {
            await stop();
            await controller?.dispose();
          })
          .catchError((_) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: closing,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(finish(null));
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Point at the barcode'),
        leading: IconButton(
          tooltip: 'Close barcode camera',
          onPressed: () => finish(null),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              error!,
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            if (supported)
                              FilledButton(
                                onPressed: retry,
                                child: const Text('Retry camera'),
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
                              if (closing || paused || error != null) return;
                              for (final b in capture.barcodes) {
                                final code = b.rawValue ?? '';
                                if (RegExp(r'^\d{8,14}$').hasMatch(code)) {
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
            Padding(
              padding: const EdgeInsets.all(20),
              child: OutlinedButton(
                onPressed: () => finish(null),
                child: const Text(
                  'Enter barcode instead',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
