import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/data/models.dart';
import 'package:calorie_app/features/logging.dart';
import 'package:calorie_app/features/meal_camera.dart';
import 'package:calorie_app/features/capture_mode_bar.dart';
import 'package:calorie_app/screens/food_camera_screen.dart';
import 'package:calorie_app/screens/food_lookup_screen.dart';
import 'package:calorie_app/main.dart';

import 'widget_test.dart' show prepare, snapshot;

class CaptureNavigationObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

class TestCameraPlatform extends CameraPlatform {
  final active = <int>{};
  final created = <CameraDescription>[];
  final audio = <bool>[];
  final flashModes = <FlashMode>[];
  int disposed = 0;
  bool denied = false, noCamera = false, flashSupported = false;
  Completer<void>? initialization;
  late Uint8List image;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (denied) throw CameraException('CameraAccessDenied', 'Denied');
    return noCamera
        ? []
        : const [
            CameraDescription(
              name: 'back',
              lensDirection: CameraLensDirection.back,
              sensorOrientation: 90,
            ),
            CameraDescription(
              name: 'front',
              lensDirection: CameraLensDirection.front,
              sensorOrientation: 90,
            ),
          ];
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings settings,
  ) async {
    created.add(description);
    audio.add(settings.enableAudio);
    final id = created.length;
    active.add(id);
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initialization?.future;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      Stream.fromFuture(Completer<CameraErrorEvent>().future);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.green);

  @override
  Future<XFile> takePicture(int cameraId) async =>
      XFile.fromData(image, mimeType: 'image/jpeg');

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (!flashSupported) throw UnimplementedError('No flash on this camera');
    flashModes.add(mode);
  }

  @override
  Future<void> dispose(int cameraId) async {
    if (active.remove(cameraId)) disposed++;
  }
}

void main() {
  late CameraPlatform original;
  late TestCameraPlatform cameras;

  setUpAll(() async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() async {
    original = CameraPlatform.instance;
    cameras = TestCameraPlatform();
    cameras.image = (await rootBundle.load('assets/images/bowl.jpg')).buffer
        .asUint8List();
    CameraPlatform.instance = cameras;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    CameraPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  Future<AppState> state() async {
    final result = await AppState.load();
    await result.completeOnboarding(BodyProfile(), withDemo: true);
    return result;
  }

  Future<void> openLogger(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: Scaffold(body: LoggingFlow(state: await state())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      cameras.created,
      isEmpty,
      reason: 'Showing a sample does not request the camera.',
    );
    await tester.tap(find.byKey(const Key('sample-plate-camera')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Sample camera opens inline; capture, retake, and use return a photo',
    (tester) async {
      await openLogger(tester);
      expect(find.byType(MealCamera), findsOneWidget);
      expect(find.byType(CameraPreview), findsOneWidget);
      expect(find.text('SAMPLE PLATE · PHOTO DEMO'), findsNothing);
      expect(cameras.created.single.lensDirection, CameraLensDirection.back);
      expect(cameras.audio, [false]);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('logging-continue')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('capture-photo')));
      await tester.pumpAndSettle();
      expect(find.text('PHOTO PREVIEW'), findsOneWidget);
      expect(
        cameras.active,
        isEmpty,
        reason: 'Capture releases the live stream.',
      );
      await tester.tap(find.byKey(const Key('retake-photo')));
      await tester.pumpAndSettle();
      expect(cameras.active, hasLength(1));
      await tester.tap(find.byKey(const Key('capture-photo')));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.tap(find.byKey(const Key('use-camera-photo')));
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpAndSettle();
      expect(find.text('Let’s try another way'), findsOneWidget);
      await tester.tap(find.text('Type Meal Instead'));
      await tester.pumpAndSettle();
      expect(cameras.active, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Switching lens and closing releases the camera and restores sample',
    (tester) async {
      await openLogger(tester);
      await tester.tap(find.byKey(const Key('switch-camera')));
      await tester.pumpAndSettle();
      expect(cameras.created.last.lensDirection, CameraLensDirection.front);
      expect(cameras.active, hasLength(1));
      expect(cameras.disposed, 1);
      await tester.tap(find.byKey(const Key('close-camera')));
      await tester.pumpAndSettle();
      expect(cameras.active, isEmpty);
      expect(find.text('SAMPLE PLATE · PHOTO DEMO'), findsOneWidget);
    },
  );

  testWidgets('Permission denial has recovery and can retry successfully', (
    tester,
  ) async {
    cameras.denied = true;
    await openLogger(tester);
    expect(
      find.text('Allow camera access for Kayleo, then try again.'),
      findsOneWidget,
    );
    expect(find.text('Choose a photo instead'), findsOneWidget);
    cameras.denied = false;
    await tester.tap(find.text('Try camera again'));
    await tester.pumpAndSettle();
    expect(find.byType(CameraPreview), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(cameras.active, isEmpty);
  });

  testWidgets('Background pauses hardware and resuming restores the preview', (
    tester,
  ) async {
    await openLogger(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(cameras.active, isEmpty);
    expect(find.text('Camera paused'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cameras.active, hasLength(1));
    expect(find.byType(CameraPreview), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(cameras.active, isEmpty);
  });

  testWidgets(
    'Closing during initialization safely releases the eventual stream',
    (tester) async {
      cameras.initialization = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MealCamera(
              bottomInset: 0,
              onPhoto: (_) {},
              onClose: () {},
              onChoosePhoto: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(cameras.active, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      cameras.initialization!.complete();
      await tester.pumpAndSettle();
      expect(cameras.active, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Center camera opens immersive capture and switches to text or voice',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      cameras.flashSupported = true;
      await tester.pumpWidget(
        KayleoApp(state: await state(), splashDuration: Duration.zero),
      );
      await tester.pumpAndSettle();
      expect(cameras.created, isEmpty);
      await tester.tap(find.byKey(const Key('bottom-camera-button')));
      await tester.pumpAndSettle();
      expect(find.byType(CameraPreview), findsOneWidget);
      expect(
        tester.widget<MealCamera>(find.byType(MealCamera)).immersive,
        isTrue,
      );
      expect(tester.getSize(find.byKey(const Key('meal-camera'))).width, 390);
      expect(
        tester.getSize(find.byKey(const Key('meal-camera'))).height,
        greaterThan(700),
      );
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.byKey(const Key('camera-mode-barcode')), findsOneWidget);
      expect(cameras.flashModes, [FlashMode.off]);
      await tester.tap(find.byTooltip('Flash: off'));
      await tester.pumpAndSettle();
      expect(cameras.flashModes.last, FlashMode.auto);
      await tester.tap(find.byTooltip('Flash: auto'));
      await tester.pumpAndSettle();
      expect(cameras.flashModes.last, FlashMode.always);
      await tester.tap(find.byTooltip('Flash: always'));
      await tester.pumpAndSettle();
      expect(cameras.flashModes.last, FlashMode.off);

      final galleryResult = Completer<String?>();
      const galleryChannel = MethodChannel('plugins.flutter.io/image_picker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(galleryChannel, (call) async {
        expect(call.method, 'pickImage');
        return galleryResult.future;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(galleryChannel, null),
      );
      await tester.tap(find.text('Gallery'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MealCamera), findsNothing);
      expect(cameras.active, isEmpty);
      galleryResult.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(MealCamera), findsOneWidget);
      expect(cameras.active, hasLength(1));

      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      expect(find.byType(MealCamera), findsNothing);
      expect(cameras.active, isEmpty);
      expect(find.byKey(const Key('meal-description')), findsOneWidget);
      expect(find.text('What did you eat?'), findsWidgets);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bottom-camera-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('bottom-camera-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice'));
      await tester.pumpAndSettle();
      expect(find.byType(MealCamera), findsNothing);
      expect(cameras.active, isEmpty);
      expect(find.text('Tap and tell Kayleo what you ate'), findsOneWidget);
      expect(find.byType(KayleoRing), findsWidgets);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bottom-camera-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('camera-mode-barcode')), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-camera')));
      await tester.pumpAndSettle();
      expect(cameras.active, isEmpty);
      expect(find.byType(MealCamera), findsNothing);
      expect(find.byKey(const Key('bottom-camera-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Capture keeps one mode bar, switches without navigation and preserves the draft',
    (tester) async {
      final appState = await state();
      final observer = CaptureNavigationObserver();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await prepare(
        tester,
        const Size(390, 844),
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: kayleoTheme(),
          navigatorObservers: [observer],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLogger(context, appState, mode: 'Text'),
                child: const Text('Start capture'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start capture'));
      await tester.pumpAndSettle();
      final pushes = observer.pushes;
      final barElement = tester.element(find.byType(CaptureModeBar));
      expect(find.byType(FoodCameraScreen), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.enterText(
        find.byKey(const Key('meal-description')),
        'Two eggs and toast',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('capture-mode-Voice'))),
      );
      await tester.pumpAndSettle();
      final hoverTile = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const Key('capture-mode-Voice')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        (hoverTile.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
      expect(
        tester.widget<CaptureModeBar>(find.byType(CaptureModeBar)).selected,
        'Text',
      );
      await mouse.removePointer();
      await snapshot(tester, 'capture-unified-type');
      await tester.tap(find.text('Voice'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('meal-description')))
            .controller!
            .text,
        'Two eggs and toast',
      );
      expect(tester.element(find.byType(CaptureModeBar)), same(barElement));
      expect(observer.pushes, pushes);
      await snapshot(tester, 'capture-unified-voice');
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      expect(cameras.active, hasLength(1));
      expect(tester.element(find.byType(CaptureModeBar)), same(barElement));
      await snapshot(tester, 'capture-unified-camera');
      // Swipe across the shared bar directly from Camera to Barcode.
      final start = tester.getCenter(
        find.byKey(const Key('capture-mode-Photo')),
      );
      final end = tester.getCenter(
        find.byKey(const Key('capture-mode-Barcode')),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.dragFrom(start, end - start);
      await tester.pumpAndSettle();
      expect(find.byType(ProductBarcodeScreen), findsOneWidget);
      expect(
        tester
            .widget<ProductBarcodeScreen>(find.byType(ProductBarcodeScreen))
            .embedded,
        isTrue,
      );
      expect(cameras.active, isEmpty);
      expect(observer.pushes, pushes);
      expect(tester.element(find.byType(CaptureModeBar)), same(barElement));
      await snapshot(tester, 'capture-unified-barcode');
      // A slow swipe on the content also changes modes, without pushing a route.
      await tester.timedDragFrom(
        const Offset(60, 160),
        const Offset(180, 0),
        const Duration(milliseconds: 900),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tell Kayleo'), findsOneWidget);
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('meal-description')))
            .controller!
            .text,
        'Two eggs and toast',
      );
      // Repeated native-camera handoffs must release the previous owner before
      // the next preview starts; this guards Android black-screen regressions.
      for (var cycle = 0; cycle < 3; cycle++) {
        await tester.tap(find.text('Camera'));
        await tester.pumpAndSettle();
        expect(cameras.active, hasLength(1));
        await tester.tap(find.text('Barcode'));
        await tester.pumpAndSettle();
        expect(find.byType(ProductBarcodeScreen), findsOneWidget);
        expect(cameras.active, isEmpty);
      }
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      expect(observer.pushes, pushes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Immersive capture remains usable at 2x text scale on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final appState = await state();
      await tester.pumpWidget(
        MaterialApp(
          theme: kayleoTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () =>
                      showLogger(context, appState, openCamera: true),
                  child: const Text('Open scanner'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open scanner'));
      await tester.pumpAndSettle();
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Point at your meal'), findsOneWidget);
      expect(find.byTooltip('Flash: off'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Voice'));
      await tester.pumpAndSettle();
      expect(cameras.active, isEmpty);
      expect(find.text('Tell Kayleo'), findsOneWidget);
      expect(find.byKey(const Key('meal-description')), findsOneWidget);
      expect(find.text('Listening…'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      final barBeforeKeyboard = tester.getRect(
        find.byKey(const Key('capture-mode-bar')),
      );
      final actionBeforeKeyboard = tester.getRect(
        find.byKey(const Key('logging-continue')),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('capture-mode-bar'))),
        barBeforeKeyboard,
      );
      expect(
        tester.getRect(find.byKey(const Key('logging-continue'))),
        actionBeforeKeyboard,
      );
      expect(
        tester
            .getBottomLeft(find.byKey(const Key('capture-editor-viewport')))
            .dy,
        lessThanOrEqualTo(400),
      );
      expect(find.text('Done'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.tap(find.text('Barcode'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('capture-barcode-input')), findsOneWidget);
      final barcodeDock = tester.getRect(
        find.byKey(const Key('capture-mode-bar')),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('capture-mode-bar'))),
        barcodeDock,
      );
      expect(
        tester
            .getBottomLeft(find.byKey(const Key('capture-barcode-viewport')))
            .dy,
        lessThanOrEqualTo(400),
      );
      tester.view.resetViewInsets();
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      expect(cameras.active, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('capture-photo')));
      await tester.pumpAndSettle();
      expect(cameras.active, isEmpty);
      expect(find.text('PHOTO PREVIEW'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.tap(find.byKey(const Key('use-camera-photo')));
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpAndSettle();
      expect(find.text('Let’s try another way'), findsOneWidget);
      await tester.tap(find.text('Type Meal Instead'));
      await tester.pumpAndSettle();
      expect(find.byType(MealCamera), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(cameras.active, isEmpty);
    },
  );
}
