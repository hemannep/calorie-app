import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ui.dart';

/// A live camera that releases its hardware on capture, backgrounding, and exit.
class MealCamera extends StatefulWidget {
  const MealCamera({
    super.key,
    required this.onPhoto,
    required this.onClose,
    required this.onChoosePhoto,
    this.immersive = false,
    this.onSelectMode,
    this.onBarcode,
  });

  final ValueChanged<Uint8List> onPhoto;
  final VoidCallback onClose;
  final VoidCallback onChoosePhoto;
  final bool immersive;
  final ValueChanged<String>? onSelectMode;
  final VoidCallback? onBarcode;

  @override
  State<MealCamera> createState() => _MealCameraState();
}

class _MealCameraState extends State<MealCamera> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  CameraDescription? _selected;
  Uint8List? _captured;
  String? _error;
  bool _loading = true, _capturing = false, _paused = false;
  bool _flashAvailable = false, _changingFlash = false;
  FlashMode _flashMode = FlashMode.off;
  int _generation = 0;
  Future<void> _operations = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_cameraChanged);
      try {
        await controller.dispose();
      } catch (_) {
        // A disconnected device can fail disposal; it must not block a retry.
      }
    }
  }

  void _open({CameraDescription? camera}) {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _captured = null;
      _paused = false;
      _flashAvailable = false;
      _flashMode = FlashMode.off;
      _changingFlash = false;
    });
    _operations = _operations.then((_) async {
      await _release();
      if (!_current(generation)) return;
      try {
        _cameras = await availableCameras();
        if (!_current(generation)) return;
        if (_cameras.isEmpty) {
          throw CameraException('NoCamera', 'No camera is connected.');
        }
        _selected =
            camera ??
            _selected ??
            _cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => _cameras.first,
            );
        final controller = CameraController(
          _selected!,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        _controller = controller;
        await controller.initialize();
        if (!_current(generation)) {
          await _release();
          return;
        }
        // Flash controls are exposed only after the device accepts flash mode.
        var flashAvailable = false;
        try {
          await controller.setFlashMode(FlashMode.off);
          flashAvailable = true;
        } catch (_) {
          // Web cameras and some lenses do not support flash.
        }
        if (!_current(generation)) {
          await _release();
          return;
        }
        try {
          await controller.setFocusMode(FocusMode.auto);
        } catch (_) {}
        if (!_current(generation)) {
          await _release();
          return;
        }
        controller.addListener(_cameraChanged);
        setState(() {
          _loading = false;
          _flashAvailable = flashAvailable;
        });
      } catch (error) {
        await _release();
        if (_current(generation)) {
          setState(() {
            _loading = false;
            _error = _message(error);
          });
        }
      }
    });
  }

  String _message(Object error) {
    if (error is CameraException) {
      if (error.code == 'CameraAccessDeniedWithoutPrompt' ||
          error.code == 'CameraAccessRestricted') {
        return 'Allow camera access in your device settings, then try again.';
      }
      if (error.code.toLowerCase().contains('denied')) {
        return 'Allow camera access for Kayleo, then try again.';
      }
      if (error.code == 'NoCamera') {
        return 'No camera is connected. You can choose a photo instead.';
      }
    }
    if (error is UnimplementedError || error is MissingPluginException) {
      return 'Open Kayleo in your browser or on your phone to use the camera.';
    }
    return 'The camera couldn’t open. Check camera access and try again.';
  }

  void _cameraChanged() {
    final controller = _controller;
    if (mounted && controller != null && controller.value.hasError) {
      setState(() => _error = 'The camera disconnected. Try opening it again.');
      _operations = _operations.then((_) => _release());
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || _loading) return;
    final generation = _generation;
    setState(() => _capturing = true);
    try {
      unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!_current(generation)) return;
      if (bytes.length > 2 * 1024 * 1024) {
        throw CameraException('PhotoSize', 'Photo is too large.');
      }
      setState(() => _captured = bytes);
      _operations = _operations.then((_) => _release());
      await _operations;
    } catch (_) {
      if (_current(generation)) {
        setState(() => _error = 'The photo couldn’t be captured. Try again.');
        _operations = _operations.then((_) => _release());
      }
    } finally {
      if (_current(generation)) setState(() => _capturing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ++_generation;
      setState(() {
        _paused = true;
        _loading = false;
        _capturing = false;
      });
      _operations = _operations.then((_) => _release());
    } else if (state == AppLifecycleState.resumed && _paused) {
      if (_captured == null) {
        _open();
      } else {
        setState(() => _paused = false);
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _operations = _operations.then((_) => _release());
    super.dispose();
  }

  Widget _preview(CameraController controller) => LayoutBuilder(
    builder: (context, c) => GestureDetector(
      onTapDown: (tap) async {
        final generation = _generation;
        try {
          final point = Offset(
            (tap.localPosition.dx / c.maxWidth).clamp(0, 1),
            (tap.localPosition.dy / c.maxHeight).clamp(0, 1),
          );
          await controller.setFocusPoint(point);
          if (!_current(generation)) return;
          await controller.setExposurePoint(point);
        } catch (_) {}
      },
      child: ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, child) {
          final orientation = value.deviceOrientation;
          final landscape =
              orientation == DeviceOrientation.landscapeLeft ||
              orientation == DeviceOrientation.landscapeRight;
          final ratio = landscape ? value.aspectRatio : 1 / value.aspectRatio;
          return ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 320 * ratio,
                  height: 320,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  void _switchCamera() {
    final next =
        (_cameras.indexWhere((c) => c.name == _selected!.name) + 1) %
        _cameras.length;
    _open(camera: _cameras[next]);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || _changingFlash || _capturing) return;
    final generation = _generation;
    final next = _flashMode == FlashMode.off
        ? FlashMode.auto
        : _flashMode == FlashMode.auto
        ? FlashMode.always
        : FlashMode.off;
    setState(() => _changingFlash = true);
    try {
      await controller.setFlashMode(next);
      if (_current(generation)) setState(() => _flashMode = next);
    } catch (_) {
      if (_current(generation)) {
        setState(() => _flashAvailable = false);
      }
    } finally {
      if (_current(generation)) setState(() => _changingFlash = false);
    }
  }

  Widget _shutter({double size = 64}) => Semantics(
    button: true,
    label: 'Capture meal photo',
    enabled: !_capturing,
    child: InkResponse(
      key: const Key('capture-photo'),
      onTap: _capturing ? null : _capture,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: forest, width: 1.5),
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: _capturing
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    color: forest,
                    strokeWidth: 2,
                  ),
                )
              : null,
        ),
      ),
    ),
  );

  Widget _immersive(bool ready) => SizedBox.expand(
    key: const Key('meal-camera'),
    child: ColoredBox(
      color: KayleoColors.camera,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_captured != null)
            Image.memory(_captured!, fit: BoxFit.cover)
          else if (ready)
            _preview(_controller!),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xAA0D120F),
                  Color(0x190D120F),
                  Color(0xD90D120F),
                ],
                stops: [0, .45, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KayleoSpacing.md,
                    KayleoSpacing.md,
                    KayleoSpacing.page,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('close-camera'),
                        tooltip: 'Close camera',
                        onPressed: widget.onClose,
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Spacer(),
                      if (widget.onBarcode != null)
                        TextButton.icon(
                          key: const Key('camera-barcode'),
                          onPressed: widget.onBarcode,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Barcode'),
                        ),
                      if (ready && _flashAvailable && _captured == null)
                        IconButton(
                          tooltip: 'Flash: ${_flashMode.name}',
                          onPressed: _changingFlash || _capturing
                              ? null
                              : _toggleFlash,
                          color: _flashMode != FlashMode.off
                              ? lime
                              : Colors.white,
                          icon: Icon(
                            _flashMode == FlashMode.auto
                                ? Icons.flash_auto_rounded
                                : _flashMode == FlashMode.always
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KayleoSpacing.xxl,
                      ),
                      child: _loading || _paused
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_loading)
                                  const CircularProgressIndicator(color: lime),
                                const SizedBox(height: KayleoSpacing.lg),
                                Text(
                                  _paused
                                      ? 'Camera paused'
                                      : 'Opening your camera…',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            )
                          : _error != null
                          ? SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.no_photography_outlined,
                                    size: 32,
                                    color: lime,
                                  ),
                                  const SizedBox(height: KayleoSpacing.lg),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      height: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: KayleoSpacing.page),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: lime,
                                      foregroundColor: forest,
                                    ),
                                    onPressed: _open,
                                    child: const Text('Try camera again'),
                                  ),
                                ],
                              ),
                            )
                          : _captured != null
                          ? const Tag('PHOTO PREVIEW', color: Colors.white)
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final textScale = MediaQuery.textScalerOf(
                                  context,
                                );
                                final copyHeight = textScale.scale(13) * 2 + 56;
                                final frameSize =
                                    (constraints.maxHeight - copyHeight).clamp(
                                      32.0,
                                      270.0,
                                    );
                                return SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: frameSize,
                                        height: frameSize,
                                        child: const CustomPaint(
                                          painter: _MealGuidePainter(),
                                        ),
                                      ),
                                      const SizedBox(height: KayleoSpacing.xl),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: forest.withValues(alpha: .88),
                                          borderRadius: BorderRadius.circular(
                                            40,
                                          ),
                                        ),
                                        child: const Text(
                                          'Point at your meal',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KayleoSpacing.xl,
                    KayleoSpacing.md,
                    KayleoSpacing.xl,
                    KayleoSpacing.page,
                  ),
                  child: _captured != null
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final retake = OutlinedButton.icon(
                              key: const Key('retake-photo'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Color(0x80FFFFFF),
                                ),
                              ),
                              onPressed: _capturing ? null : _open,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retake'),
                            );
                            final usePhoto = FilledButton.icon(
                              key: const Key('use-camera-photo'),
                              style: FilledButton.styleFrom(
                                backgroundColor: lime,
                                foregroundColor: forest,
                              ),
                              onPressed: _capturing
                                  ? null
                                  : () => widget.onPhoto(_captured!),
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Use photo'),
                            );
                            if (MediaQuery.textScalerOf(context).scale(14) >
                                20) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  retake,
                                  const SizedBox(height: KayleoSpacing.md),
                                  usePhoto,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: retake),
                                const SizedBox(width: KayleoSpacing.md),
                                Expanded(child: usePhoto),
                              ],
                            );
                          },
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _CameraControl(
                              icon: Icons.photo_library_outlined,
                              label: 'Gallery',
                              onTap: _capturing ? null : widget.onChoosePhoto,
                            ),
                            if (ready)
                              _shutter(size: 78)
                            else
                              const SizedBox(width: 78, height: 78),
                            _CameraControl(
                              controlKey: const Key('switch-camera'),
                              icon: Icons.flip_camera_ios_outlined,
                              label: 'Flip',
                              onTap: !ready || _cameras.length < 2 || _capturing
                                  ? null
                                  : _switchCamera,
                            ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final (label, mode) in [
                          ('Type', 'Text'),
                          ('Camera', 'Photo'),
                          ('Voice', 'Voice'),
                        ])
                          TextButton(
                            onPressed: mode == 'Photo'
                                ? null
                                : () => widget.onSelectMode?.call(mode),
                            style: TextButton.styleFrom(
                              backgroundColor: mode == 'Photo'
                                  ? forest
                                  : Colors.transparent,
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white,
                              minimumSize: const Size(76, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: mode == 'Photo'
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
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
  );

  @override
  Widget build(BuildContext context) {
    final ready =
        !_loading &&
        !_paused &&
        _error == null &&
        _controller?.value.isInitialized == true;
    if (widget.immersive) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: KayleoColors.camera,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: _immersive(ready),
      );
    }
    return SizedBox(
      key: const Key('meal-camera'),
      height: 320,
      width: double.infinity,
      child: ColoredBox(
        color: KayleoColors.camera,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_captured != null)
              Image.memory(_captured!, fit: BoxFit.cover)
            else if (ready)
              _preview(_controller!),
            if (_error == null && !_loading && !_paused)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x65000000),
                      Colors.transparent,
                      Color(0x95000000),
                    ],
                    stops: [0, .4, 1],
                  ),
                ),
              ),
            Positioned(
              top: 14,
              left: 14,
              child: Tag(
                _captured == null ? 'LIVE CAMERA' : 'PHOTO PREVIEW',
                color: Colors.white,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                key: const Key('close-camera'),
                tooltip: 'Close camera',
                color: Colors.white,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            if (_loading || _paused)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading) const CircularProgressIndicator(color: lime),
                    const SizedBox(height: 14),
                    Text(
                      _paused ? 'Camera paused' : 'Opening your camera…',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  KayleoSpacing.xl,
                  50,
                  KayleoSpacing.xl,
                  10,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: lime,
                      size: 30,
                    ),
                    const SizedBox(height: KayleoSpacing.md),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: KayleoSpacing.lg),
                    FilledButton(
                      onPressed: _open,
                      child: const Text('Try camera again'),
                    ),
                    TextButton(
                      onPressed: widget.onChoosePhoto,
                      child: const Text(
                        'Choose a photo instead',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              )
            else if (_captured != null)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('retake-photo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white),
                        ),
                        onPressed: _capturing ? null : _open,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: KayleoSpacing.md),
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('use-camera-photo'),
                        onPressed: _capturing
                            ? null
                            : () => widget.onPhoto(_captured!),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Use photo'),
                      ),
                    ),
                  ],
                ),
              )
            else if (ready) ...[
              const Positioned(
                bottom: 92,
                left: 20,
                right: 20,
                child: Text(
                  'Keep your whole plate in the frame.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Choose a photo instead',
                      color: Colors.white,
                      onPressed: _capturing ? null : widget.onChoosePhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                    _shutter(),
                    IconButton(
                      key: const Key('switch-camera'),
                      tooltip: 'Switch camera',
                      color: Colors.white,
                      onPressed: _cameras.length < 2 || _capturing
                          ? null
                          : _switchCamera,
                      icon: const Icon(Icons.flip_camera_ios_outlined),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CameraControl extends StatelessWidget {
  const _CameraControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.controlKey,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    child: Tooltip(
      message: label == 'Flip' ? 'Switch camera' : 'Choose a photo',
      child: TextButton(
        key: controlKey,
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(88, 72),
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0x66FFFFFF),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Four short corners leave the meal itself unobstructed.
class _MealGuidePainter extends CustomPainter {
  const _MealGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final corner = (size.shortestSide * .13).clamp(12.0, 34.0);
    const radius = 12.0;
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
  bool shouldRepaint(covariant _MealGuidePainter oldDelegate) => false;
}
