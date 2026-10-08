import 'dart:ui' show Tristate;

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/data/models.dart';
import 'package:calorie_app/features/community.dart';
import 'package:calorie_app/features/onboarding.dart';
import 'package:calorie_app/features/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _freshState({
  bool demo = false,
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  final state = await AppState.load();
  if (demo) {
    await state.completeOnboarding(BodyProfile(), withDemo: true);
  }
  await state.setAppearance(brightness.name);
  addTearDown(state.dispose);
  return state;
}

Widget _accessibleApp({
  required Widget home,
  ThemeMode mode = ThemeMode.light,
}) => MaterialApp(
  theme: kayleoTheme(),
  darkTheme: kayleoTheme(brightness: Brightness.dark),
  themeMode: mode,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(2), disableAnimations: true),
    child: child!,
  ),
  home: home,
);

Widget _screenShell(AppState state, WidgetBuilder screenBuilder) =>
    ListenableBuilder(
      listenable: state,
      builder: (context, _) => _accessibleApp(
        mode: switch (state.appearance) {
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        },
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Builder(builder: screenBuilder),
          ),
        ),
      ),
    );

Future<void> _prepareSmallPhone(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  _expectNoException(tester, 'initial render');
}

void _expectNoException(WidgetTester tester, String action) {
  expect(
    tester.takeException(),
    isNull,
    reason: '$action must remain usable at 320×640 with 2× text',
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  _expectNoException(tester, 'tapping ${finder.describeMatch(Plurality.one)}');
}

Future<void> _selectSemanticChoice(WidgetTester tester, String label) async {
  final semantics = tester.ensureSemantics();
  try {
    await _tapVisible(tester, find.text(label));
    expect(
      tester.getSemantics(find.text(label)).flagsCollection.isSelected,
      Tristate.isTrue,
    );
  } finally {
    semantics.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final textFont = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await textFont.load();
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconFont.load();
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'Every onboarding step supports large text and reduced motion in ${brightness.name}',
      (tester) async {
        final state = await _freshState(brightness: brightness);
        await _prepareSmallPhone(
          tester,
          _accessibleApp(
            home: OnboardingScreen(state: state),
            mode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
          ),
        );

        const titles = [
          'Snap it.\nKayleo gets it.',
          'Speak naturally.\nJust like you.',
          'Or type it.',
          'What brings\nyou here?',
          'About you.',
          'Find your\nrhythm.',
          'Your plan.\nYour pace.',
        ];
        for (var step = 0; step < titles.length; step++) {
          expect(find.text(titles[step]), findsOneWidget);
          _expectNoException(tester, 'onboarding step ${step + 1}');
          if (step < 3) {
            expect(
              tester
                  .widgetList<AnimatedContainer>(
                    find.descendant(
                      of: find.byKey(const Key('onboarding-intro-progress')),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .map((widget) => widget.duration),
              everyElement(Duration.zero),
            );
          } else if (step == 3) {
            await _selectSemanticChoice(tester, 'Build muscle');
          } else if (step == 4) {
            await tester.enterText(
              find.widgetWithText(TextFormField, 'What should we call you?'),
              'Jamie',
            );
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Age'),
              '30',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
          } else if (step == 5) {
            await _selectSemanticChoice(tester, 'Moderately active');
            await _tapVisible(tester, find.text('Vegetarian'));
            expect(
              tester
                  .widget<ChoiceChip>(
                    find.widgetWithText(ChoiceChip, 'Vegetarian'),
                  )
                  .selected,
              isTrue,
            );
          }
          await _tapVisible(
            tester,
            find.byKey(const Key('onboarding-continue')),
          );
        }

        expect(state.onboarded, isTrue);
        expect(state.demo, isFalse);
        expect(state.profile.name, 'Jamie');
        expect(state.profile.goal, 'Build muscle');
        expect(state.profile.activity, 'Moderately active');
        expect(state.profile.diet, 'Vegetarian');
        expect(state.meals, isEmpty);
        final restored = await AppState.load();
        expect(restored.onboarded, isTrue);
        expect(restored.profile.name, 'Jamie');
        restored.dispose();
      },
    );

    testWidgets(
      'Settings sheets and preferences support large text in ${brightness.name}',
      (tester) async {
        final state = await _freshState(demo: true, brightness: brightness);
        final destinations = <int>[];
        await _prepareSmallPhone(
          tester,
          _screenShell(
            state,
            (_) => SettingsScreen(state: state, navigate: destinations.add),
          ),
        );

        await _tapVisible(tester, find.text('Saved meals'));
        await _tapVisible(tester, find.text('Community'));
        expect(destinations, [4, 5]);

        for (final (action, sheetType) in [
          ('Edit profile', EditProfileSheet),
          ('Measurements', EditProfileSheet),
          ('Diet preferences', DietPreferencesSheet),
          ('Goals', TargetsSheet),
          ('Notifications', ReminderSheet),
          ('Privacy & data', PrivacySheet),
          ('About Kayleo', AboutSheet),
          ('Kayleo+', PremiumSheet),
          ('Reset & sample data', DataToolsSheet),
        ]) {
          await _tapVisible(tester, find.text(action));
          expect(find.byType(sheetType), findsOneWidget);
          if (action == 'Notifications') {
            await _tapVisible(tester, find.text('Hydration reminders'));
            expect(state.preferences['Hydration reminders'], isTrue);
            expect(
              tester
                  .widget<SwitchListTile>(
                    find.widgetWithText(SwitchListTile, 'Hydration reminders'),
                  )
                  .value,
              isTrue,
            );
          }
          if (action == 'Diet preferences') {
            await _tapVisible(tester, find.text('Vegetarian'));
            expect(state.profile.diet, 'Vegetarian');
          }
          await _tapVisible(tester, find.byTooltip('Close'));
          expect(find.byType(sheetType), findsNothing);
        }

        await _tapVisible(tester, find.text('Units'));
        expect(find.text('Choose your units'), findsOneWidget);
        await _tapVisible(tester, find.text('Imperial · lb & inches'));
        expect(state.profile.units, 'Imperial');
        await _tapVisible(tester, find.text('Appearance'));
        expect(find.byType(AppearanceSheet), findsOneWidget);
        for (final (label, value, mode) in [
          ('Light', 'light', ThemeMode.light),
          ('Dark', 'dark', ThemeMode.dark),
          ('System', 'system', ThemeMode.system),
        ]) {
          await _tapVisible(tester, find.text(label));
          expect(state.appearance, value);
          expect(
            tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
            mode,
          );
        }
        await _tapVisible(tester, find.byTooltip('Close'));
        final restored = await AppState.load();
        expect(restored.profile.units, 'Imperial');
        expect(restored.preferences['Hydration reminders'], isTrue);
        expect(restored.profile.diet, 'Vegetarian');
        expect(restored.appearance, 'system');
        restored.dispose();
      },
    );

    testWidgets(
      'Community supports large text and state updates in ${brightness.name}',
      (tester) async {
        final state = await _freshState(demo: true, brightness: brightness);
        await _prepareSmallPhone(
          tester,
          _screenShell(state, (_) => CommunityScreen(state: state)),
        );

        await _tapVisible(tester, find.text('Explore preview'));
        expect(state.community, isTrue);
        expect(find.text('Discover'), findsOneWidget);
        await _tapVisible(tester, find.text('Join preview group').first);
        expect(state.joined, contains('regional'));
        expect(find.text('Joined · tap to leave'), findsOneWidget);
        await _tapVisible(tester, find.text('My groups'));
        expect(
          find.text('My usual dal bhat, with more greens.'),
          findsOneWidget,
        );
        expect(
          find.text('The lunch bowl I keep coming back to.'),
          findsNothing,
        );
        await _tapVisible(tester, find.text('Discover'));

        await _tapVisible(tester, find.text('Join the challenge'));
        expect(state.joined, contains('challenge'));
        expect(find.text('Leave challenge'), findsOneWidget);
        await _tapVisible(tester, find.text('24 cheers'));
        expect(state.liked, contains('sample-1'));
        expect(find.text('25 cheers'), findsOneWidget);

        await _tapVisible(tester, find.text('Leave community preview'));
        expect(state.community, isFalse);
        expect(find.text('Explore preview'), findsOneWidget);
        final restored = await AppState.load();
        expect(restored.community, isFalse);
        expect(restored.liked, contains('sample-1'));
        expect(restored.joined, containsAll(['regional', 'challenge']));
        restored.dispose();
      },
    );
  }
}
