import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/data/models.dart';
import 'package:calorie_app/services/home_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'publishes daily nutrition, routes actions, and hides signed-out data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final updates = <Map<Object?, Object?>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HomeWidgetService.channel, (
        call,
      ) async {
        if (call.method == 'getInitialAction') return 'barcode';
        if (call.method == 'update') {
          updates.add(Map<Object?, Object?>.from(call.arguments as Map));
        }
        return null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(HomeWidgetService.channel, null),
      );

      final service = HomeWidgetService.instance;
      final actions = <String>[];
      await service.initialize();
      service.onAction = actions.add;
      service.dispatchPending();
      expect(actions, ['barcode']);

      final state = await AppState.load();
      addTearDown(() {
        service.attach(null);
        service.onAction = null;
        state.dispose();
      });
      await state.completeOnboarding(state.profile);
      service.attach(state);
      await state.saveMeal(
        Meal(
          id: 'widget-test',
          name: 'Lunch',
          time: DateTime.now(),
          category: 'Lunch',
          items: [],
          manual: const Nutrients(420, 24, 45, 16),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(updates.last['ready'], true);
      expect(updates.last['calories'], 420);
      expect(updates.last['protein'], 24);
      expect(updates.last['carbs'], 45);
      expect(updates.last['fat'], 16);
      expect(updates.last['streak'], 1);
      expect(updates.last['loggedToday'], true);
      final week = updates.last['weekLogged'] as String;
      expect(week.length, 7);
      expect(week[DateTime.now().weekday - 1], '1');

      // Theme changes must publish even when nutrition data is unchanged.
      for (final appearance in ['dark', 'light', 'system', 'dark', 'light']) {
        final before = updates.length;
        await state.setAppearance(appearance);
        await Future<void>.delayed(Duration.zero);
        expect(updates.length, greaterThan(before));
        expect(updates.last['appearance'], appearance);
        expect(updates.last['calories'], 420);
      }

      state.markSignedOut();
      await Future<void>.delayed(Duration.zero);
      expect(updates.last['ready'], false);
      expect(updates.last['calories'], 0);
      expect(updates.last['streak'], 0);
      expect(updates.last['weekLogged'], '0000000');
    },
  );
}
