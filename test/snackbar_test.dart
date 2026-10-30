import 'package:calorie_app/core/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('action snackbars dismiss after the standard timeout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => toast(
                    context,
                    '500 ml added',
                    action: SnackBarAction(label: 'Undo', onPressed: () {}),
                  ),
                  child: const Text('Add water'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add water'));
    await tester.pump();
    expect(find.text('500 ml added'), findsOneWidget);

    await tester.pump(kayleoSnackBarDuration);
    await tester.pumpAndSettle();
    expect(find.text('500 ml added'), findsNothing);
  });
}
