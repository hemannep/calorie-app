import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/milestones.dart';
import 'package:calorie_app/features/milestones.dart';
import 'package:calorie_app/theme/kayleo_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Milestone celebration screen renders share card and captures PNG image', (
    tester,
  ) async {
    final state = await AppState.load();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: MilestoneCelebrationScreen(
          state: state,
          earned: [milestones.first],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('milestone-celebration')), findsOneWidget);
    expect(find.text('Share your milestone'), findsOneWidget);
    expect(find.text('MILESTONE UNLOCKED'), findsOneWidget);
    expect(find.text('First meal'), findsOneWidget);

    // Verify RepaintBoundary exists for sharing
    final boundaries = find.byType(RepaintBoundary);
    expect(boundaries, findsWidgets);

    // Capture the celebration share card
    Uint8List? capturedBytes;
    await tester.runAsync(() async {
      for (final element in boundaries.evaluate()) {
        final renderObject = element.renderObject;
        if (renderObject is RenderRepaintBoundary && renderObject.hasSize && renderObject.size.width > 200) {
          final image = await renderObject.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null && byteData.lengthInBytes > 1000) {
            capturedBytes = byteData.buffer.asUint8List();
            break;
          }
        }
      }
    });

    expect(capturedBytes, isNotNull);
    // Verify PNG magic bytes: 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A
    expect(capturedBytes!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);

    // Tap share button to verify it executes cleanly without throwing
    await tester.ensureVisible(find.text('Share your milestone'));
    await tester.tap(find.text('Share your milestone'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Milestone detail sheet captures milestone card as PNG and triggers share cleanly', (
    tester,
  ) async {
    final state = await AppState.load();
    state.milestoneUnlocks['meal1'] = DateTime.now().toIso8601String();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: kayleoTheme(),
        home: MilestonesScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll to and tap on the first milestone to open detail sheet
    await tester.ensureVisible(find.byKey(const Key('milestone-meal1')));
    await tester.tap(find.byKey(const Key('milestone-meal1')));
    await tester.pumpAndSettle();

    expect(find.text('Share milestone'), findsOneWidget);
    expect(find.text('First meal'), findsWidgets);

    // Verify RepaintBoundary in sheet
    final boundaries = find.byType(RepaintBoundary);
    Uint8List? capturedBytes;
    await tester.runAsync(() async {
      for (final element in boundaries.evaluate()) {
        final renderObject = element.renderObject;
        if (renderObject is RenderRepaintBoundary && renderObject.hasSize && renderObject.size.height > 200) {
          final image = await renderObject.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null && byteData.lengthInBytes > 1000) {
            capturedBytes = byteData.buffer.asUint8List();
            break;
          }
        }
      }
    });

    expect(capturedBytes, isNotNull);
    expect(capturedBytes!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);

    // Tap share button to verify it executes cleanly without throwing
    await tester.tap(find.text('Share milestone'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
