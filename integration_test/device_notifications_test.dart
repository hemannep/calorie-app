import 'package:calorie_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/timezone.dart' as tz;

/// Uses reserved IDs and never reads or changes diary data or reminder preferences.
/// Background the app at the readiness marker to validate OS tray delivery.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Real device notifications arrive while the app is paused', (
    tester,
  ) async {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Checking Kayleo notifications…')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final driver = DeviceNotificationDriver();
    await driver.initialize();
    expect(driver.supported, isTrue);
    expect(await driver.requestPermission(), isTrue);
    expect(await driver.permitted(), isTrue);
    final now = tz.TZDateTime.now(tz.local);
    await driver.schedule(
      ReminderRequest(
        9001,
        'Kayleo scheduled check',
        'Your offline scheduled notification arrived.',
        now.add(const Duration(seconds: 20)),
        repeat: false,
      ),
    );
    expect(
      (await driver.plugin.pendingNotificationRequests()).any(
        (r) => r.id == 9001,
      ),
      isTrue,
    );
    debugPrint(
      'KAYLEO_BACKGROUND_NOTIFICATION_TEST_READY zone=${tz.local.name}',
    );
    await Future<void>.delayed(const Duration(seconds: 15));
    expect(WidgetsBinding.instance.lifecycleState, AppLifecycleState.paused);
    await driver.show(
      9002,
      'Kayleo background check',
      'Your device notification works outside the app.',
    );
    await Future<void>.delayed(const Duration(seconds: 15));
    final active = await driver.plugin.getActiveNotifications();
    expect(active.map((n) => n.id), containsAll([9001, 9002]));
    debugPrint(
      'KAYLEO_NOTIFICATION_TEST_PASSED active_ids=${active.map((n) => n.id).join(',')}',
    );
  });
}
