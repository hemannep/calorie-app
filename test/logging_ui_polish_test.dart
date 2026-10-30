import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/meal_engine.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/features/dashboard.dart';
import 'package:calorie_app/features/logging.dart';
import 'package:calorie_app/features/progress.dart';
import 'package:calorie_app/features/milestones.dart';
import 'package:calorie_app/features/settings.dart';
import 'package:calorie_app/features/shell.dart';
import 'package:calorie_app/screens/food_lookup_screen.dart';
import 'package:calorie_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notifications_milestones_test.dart' show FakeNotifications;
import 'widget_test.dart' show prepare, snapshot;

Future<AppState> fresh() async {
  SharedPreferences.setMockInitialValues({});
  final s = await AppState.load();
  s.profile.name = 'Alex';
  await s.completeOnboarding(s.profile, withDemo: true);
  addTearDown(s.dispose);
  return s;
}

Widget page(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: kayleoTheme(brightness: brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  ),
);
void main() {
  setUpAll(() async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.clearAllTestValues();
  });
  testWidgets('Today places search below the rings and opens live lookup', (
    t,
  ) async {
    final s = await fresh();
    await prepare(
      t,
      const Size(390, 980),
      page(DashboardScreen(state: s, navigate: (_) {})),
    );
    expect(find.byKey(const Key('home-barcode')), findsNothing);
    expect(find.byKey(const Key('home-food-search')), findsOneWidget);
    final macroCard = find
        .ancestor(
          of: find.byType(KayleoRing).at(3),
          matching: find.byType(Panel),
        )
        .first;
    final headingGap =
        t.getTopLeft(find.byKey(const Key('today-calorie-ring'))).dy -
        t.getBottomLeft(find.byKey(const Key('rings-heading-nutrition'))).dy;
    expect(headingGap, greaterThan(0));
    expect(
      t.getTopLeft(find.byKey(const Key('home-food-search'))).dy -
          t.getBottomLeft(macroCard).dy,
      inInclusiveRange(0, 24),
    );
    expect(
      t.getTopLeft(find.byKey(const Key('home-food-search'))).dy,
      greaterThan(t.getBottomLeft(find.byType(KayleoRing).at(3)).dy),
    );
    await snapshot(t, 'today-polished');
    await t.tap(find.byKey(const Key('home-food-search')));
    await t.pumpAndSettle();
    expect(
      t.widget<FoodLookupScreen>(find.byType(FoodLookupScreen)).barcode,
      isFalse,
    );
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Logging barcode chip opens the camera and manual input', (
    t,
  ) async {
    final s = await fresh();
    await t.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: Scaffold(
          body: LoggingFlow(state: s, initialMode: 'Text'),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'samosa');
    await t.ensureVisible(find.widgetWithText(ChoiceChip, 'Barcode'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Barcode'));
    await t.pumpAndSettle();
    expect(find.byType(ProductBarcodeScreen), findsOneWidget);
    expect(find.text('Barcode number'), findsOneWidget);
    await t.tap(find.byTooltip('Close barcode camera'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'Profile and milestones support 320px and 2x text in ${brightness.name}',
      (t) async {
        final s = await fresh();
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox.shrink());
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        await t.pumpWidget(
          page(
            SettingsScreen(state: s, navigate: (_) {}),
            brightness: brightness,
            scale: 2,
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(
          page(ProgressScreen(state: s), brightness: brightness, scale: 2),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('open-milestones')));
        await t.pumpAndSettle();
        expect(find.byType(MilestonesScreen), findsOneWidget);
        await t.ensureVisible(find.text('5 saved meals'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('Profile and milestone previews show earned progress', (t) async {
    final s = await fresh();
    for (var i = 0; i < 5; i++) {
      await s.saveMeal(
        MealEngine.parse('100 g rice').meal.copy(id: 'personal-$i'),
      );
    }
    await prepare(
      t,
      const Size(390, 980),
      page(SettingsScreen(state: s, navigate: (_) {})),
    );
    await snapshot(t, 'profile-polished');
    await prepare(t, const Size(390, 980), page(ProgressScreen(state: s)));
    await t.tap(find.byKey(const Key('open-milestones')));
    await t.pumpAndSettle();
    await snapshot(t, 'milestones-polished');
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Weight-loss personalization is editable and shown in progress', (
    t,
  ) async {
    final s = await fresh();
    s.profile
      ..goal = 'Lose weight'
      ..weight = 80
      ..targetWeight = 70
      ..goalDurationMonths = 6;
    await s.logWeight(
      80,
      date: DateTime.now().subtract(const Duration(days: 5)),
    );
    await s.logWeight(76);

    await prepare(t, const Size(390, 980), page(EditProfileSheet(state: s)));
    expect(
      find.byKey(const Key('profile-height-unit-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-weight-goal-section')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile-goal-duration')), findsOneWidget);

    await prepare(t, const Size(390, 1200), page(ProgressScreen(state: s)));
    await t.ensureVisible(find.byKey(const Key('weight-goal-summary')));
    await t.pumpAndSettle();
    expect(find.text('Goal 70.0 kg'), findsOneWidget);
    expect(find.text('6.0 kg to go'), findsOneWidget);
    expect(find.byKey(const Key('weight-goal-progress')), findsOneWidget);
  });
  testWidgets('Reminder UI enables, tests and disables device delivery', (
    t,
  ) async {
    final s = await fresh();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kathmandu'));
    final d = FakeNotifications();
    final n = NotificationService(driver: d);
    n.attach(s);
    await n.settled;
    await prepare(
      t,
      const Size(390, 980),
      page(ReminderSheet(state: s, notifications: n)),
    );
    await t.tap(find.text('Enable device notifications'));
    await t.pumpAndSettle();
    expect(d.pending.keys, containsAll([10, 11, 15]));
    await t.tap(find.text('Send test notification'));
    await t.pumpAndSettle();
    expect(d.shown, contains(99));
    ScaffoldMessenger.of(t.element(find.byType(ReminderSheet)))
        .clearSnackBars();
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await snapshot(t, 'reminders-polished');
    await t.tap(find.widgetWithText(SwitchListTile, 'Device notifications'));
    await t.pumpAndSettle();
    expect(d.pending, isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
    await n.settled;
    n.dispose();
  });
  testWidgets('Milestone compliment stays in inbox after reload', (t) async {
    final s = await fresh();
    await s.saveMeal(MealEngine.parse('100 g rice').meal);
    final restored = await AppState.load();
    addTearDown(restored.dispose);
    await t.pumpWidget(page(InboxSheet(state: restored)));
    await t.pumpAndSettle();
    expect(find.text('Well done! First meal'), findsOneWidget);
    expect(find.textContaining('lovely first step'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
