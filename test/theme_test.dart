import 'dart:math' as math;

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/data/models.dart';
import 'package:calorie_app/features/logging.dart';
import 'package:calorie_app/features/shell.dart';
import 'package:calorie_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> sampleState() async {
  SharedPreferences.setMockInitialValues({});
  final state = await AppState.load();
  await state.completeOnboarding(BodyProfile(), withDemo: true);
  addTearDown(state.dispose);
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'Appearance preserves legacy meal records and resets with local data',
    () async {
      final state = await sampleState();
      final before = state.meals.map((meal) => meal.id).toList();
      expect(state.appearance, 'light');
      for (final appearance in ['dark', 'system', 'light']) {
        await state.setAppearance(appearance);
        final restored = await AppState.load();
        expect(restored.appearance, appearance);
        expect(restored.meals.map((meal) => meal.id), before);
        restored.dispose();
      }
      await state.setAppearance('unsupported');
      expect(state.appearance, 'light');
      await state.setAppearance('dark');
      await state.reset();
      expect(state.appearance, 'light');
      expect(state.meals, isEmpty);
    },
  );

  testWidgets(
    'Appearance switches live without closing the route or clearing a meal draft',
    (tester) async {
      final state = await sampleState();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        KayleoApp(state: state, splashDuration: Duration.zero),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('You').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Appearance'));
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(state.appearance, 'dark');
      expect(find.text('Dark'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('Dark'))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Type it'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('meal-description')),
        'Rice and chicken curry',
      );
      for (final appearance in ['light', 'dark']) {
        await state.setAppearance(appearance);
        await tester.pumpAndSettle();
        expect(find.byType(LoggingFlow), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('meal-description')))
              .controller!
              .text,
          'Rice and chicken curry',
        );
        expect(
          Theme.of(tester.element(find.byType(LoggingFlow))).brightness,
          appearance == 'dark' ? Brightness.dark : Brightness.light,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Dark primary routes support a narrow phone and doubled text', (
    tester,
  ) async {
    final state = await sampleState();
    await state.setAppearance('dark');
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(brightness: Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: AppShell(state: state),
      ),
    );
    await tester.pumpAndSettle();
    for (final route in ['Today', 'Diary', 'Progress', 'You']) {
      await tester.tap(find.text(route).last);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '$route supports dark mode and large text',
      );
      expect(
        Theme.of(tester.element(find.byType(AppShell))).brightness,
        Brightness.dark,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'Both palettes keep body, secondary text and button labels readable',
    () {
      double contrast(Color a, Color b) =>
          (math.max(a.computeLuminance(), b.computeLuminance()) + .05) /
          (math.min(a.computeLuminance(), b.computeLuminance()) + .05);
      for (final brightness in Brightness.values) {
        final theme = kayleoTheme(brightness: brightness);
        final surfaces = theme.extension<KayleoSurfaces>()!;
        for (final background in [
          theme.scaffoldBackgroundColor,
          surfaces.card,
        ]) {
          expect(
            contrast(theme.colorScheme.onSurface, background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(theme.colorScheme.onSurfaceVariant, background),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(
          contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );
}
