import 'dart:async';

import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/meal_engine.dart';
import 'package:calorie_app/core/ui.dart';
import 'package:calorie_app/data/community_models.dart';
import 'package:calorie_app/features/community.dart';
import 'package:calorie_app/features/community_friends.dart';
import 'package:calorie_app/features/community_room.dart';
import 'package:calorie_app/services/community_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show prepare, snapshot;

class _Meta extends Fake implements SnapshotMetadata {
  @override
  bool get isFromCache => false;
  @override
  bool get hasPendingWrites => false;
}

// Firestore snapshots are faked only at the widget test boundary.
// ignore: subtype_of_sealed_class
class _Doc extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
  @override
  bool get exists => true;
  @override
  SnapshotMetadata get metadata => _Meta();
}

class _Query extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Query(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  SnapshotMetadata get metadata => _Meta();
}

class TestCommunityService extends CommunityService {
  TestCommunityService() {
    ready = true;
    profile = {
      'inviteCode': 'K-0123456789ABCDEF01234567',
      'joined': ['cal-2000'],
      'shareNutrition': false,
      'shareActivity': false,
    };
  }
  @override
  String? get uid => 'test-me';
  @override
  bool get available => true;
  @override
  Future<List<CommunityGroup>> customGroups() async => const [];
  String? removedPeer;
  @override
  Future<void> unfriend(String pair, String peer) async {
    removedPeer = peer;
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> friendship(String pair) =>
      Stream.value(
        _Doc(pair, {
          'members': ['test-me', 'test-peer'],
        }),
      );
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> friendProgress(String peer) =>
      Stream.value(
        _Doc(peer, {
          'name': 'Maya',
          'date': '2026-10-11',
          'streak': 7,
          'updatedAt': Timestamp.now(),
          'days': List.generate(
            7,
            (i) => {
              'date': DateTime.now()
                  .subtract(Duration(days: i))
                  .toIso8601String()
                  .split('T')
                  .first,
              'nutrition': {
                'calories': 1800,
                'protein': 110,
                'carbs': 190,
                'fat': 65,
              },
              'activity': {'minutes': 35},
            },
          ),
        }),
      );
  final sent = <String>[];
  int cheersSent = 0;
  @override
  Future<void> send(
    String room,
    String text, {
    required bool group,
    Map<String, dynamic>? attachment,
    String? replyTo,
  }) async {
    sent.add(text);
  }

  @override
  Future<void> cheer(
    String room,
    String message, {
    required bool group,
    required bool active,
  }) async {
    cheersSent++;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> cheers(
    String room,
    String message, {
    required bool group,
  }) => Stream.value(_Query([]));
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> friends() => Stream.value(
    _Query([
      _Doc('test-me_test-peer', {
        'members': ['test-me', 'test-peer'],
        'names': {'test-me': 'You', 'test-peer': 'Maya'},
      }),
    ]),
  );
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> conversation(
    String room, {
    required bool group,
  }) => Stream.value(
    _Query([
      _Doc('message-one', {
        'authorId': 'test-peer',
        'authorName': 'Maya',
        'body': 'A little meal prep made today easier.',
        'createdAt': Timestamp.now(),
        'attachment': {
          'title': 'My lunch bowl',
          'calories': 520,
          'protein': 32,
          'carbs': 58,
          'fat': 18,
        },
        'replyTo': null,
      }),
    ]),
  );
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> leaderboard(String group) =>
      Stream.value(
        _Query([
          _Doc('test-peer', {'name': 'Maya', 'streak': 7}),
          _Doc('test-me', {'name': 'Alex', 'streak': 7}),
          _Doc('test-third', {'name': 'Sam', 'streak': 3}),
        ]),
      );
  @override
  Future<void> join(CommunityGroup group) async {
    profile['joined'] = [...joined, group.id];
    notifyListeners();
  }

  @override
  Future<void> leave(CommunityGroup group) async {
    profile['joined'] = joined.where((id) => id != group.id).toList();
    notifyListeners();
  }
}

Future<AppState> freshSocialState() async {
  SharedPreferences.setMockInitialValues({});
  final state = await AppState.load();
  state.onboarded = true;
  state.accountUid = 'test-me';
  return state;
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('only a complete invite code or Kayleo QR payload can connect', () {
    const code = 'K-0123456789ABCDEF01234567';
    expect(FriendInvite.parse('  ${code.toLowerCase()} '), code);
    expect(FriendInvite.parse(FriendInvite.qr(code)), code);
    expect(FriendInvite.pairId('b', 'a'), FriendInvite.pairId('a', 'b'));
    for (final invalid in [
      '',
      'friend-name',
      'K-123',
      'https://example.com/$code',
      'kayleo://other/$code',
      'kayleo://friend/$code/extra',
    ]) {
      expect(() => FriendInvite.parse(invalid), throwsFormatException);
    }
  });
  test(
    'shared summaries omit nutrition and activity until explicitly enabled',
    () async {
      final state = await freshSocialState();
      await state.saveMeal(MealEngine.parse('100 g rice').meal);
      state.activityMinutes[DateTime.now().toIso8601String().split('T').first] =
          30;
      final private = CommunityService.progress(
        state,
        nutrition: false,
        activity: false,
      );
      expect(
        (private['days'] as List).every(
          (day) => day['nutrition'] == null && day['activity'] == null,
        ),
        isTrue,
      );
      final shared = CommunityService.progress(
        state,
        nutrition: true,
        activity: true,
      );
      final today = (shared['days'] as List).first as Map;
      expect(today['nutrition']['calories'], greaterThan(0));
      expect(today['activity']['minutes'], 30);
      expect(shared.keys, isNot(contains('weight')));
      expect(shared.toString(), isNot(contains('photoBase64')));
      expect(shared.toString(), isNot(contains('items')));
      state.dispose();
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'community discovery, friends, and QR fit a phone in ${brightness.name}',
      (t) async {
        final state = await freshSocialState();
        final service = TestCommunityService();
        await prepare(
          t,
          const Size(390, 844),
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: kayleoTheme(brightness: brightness),
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: CommunityScreen(state: state, service: service),
                ),
              ),
            ),
          ),
        );
        await snapshot(t, 'community-live-${brightness.name}');
        await t.enterText(find.byType(TextField).first, 'keto');
        await t.pumpAndSettle();
        expect(find.text('Keto kitchen'), findsOneWidget);
        expect(find.text('Vegan table'), findsNothing);
        await t.ensureVisible(find.text('Friends'));
        await t.tap(find.text('Friends'));
        await t.pumpAndSettle();
        expect(find.text('Your friends'), findsOneWidget);
        expect(find.text('Maya'), findsOneWidget);
        expect(
          t.getTopLeft(find.text('Your friends')).dy,
          lessThan(t.getTopLeft(find.text('Grow together')).dy),
        );
        expect(find.text('Shared with friends'), findsOneWidget);
        await snapshot(t, 'community-friends-${brightness.name}');
        await t.tap(find.text('Maya'));
        await t.pumpAndSettle();
        expect(find.byType(FriendRoomScreen), findsOneWidget);
        Navigator.of(t.element(find.byType(FriendRoomScreen))).pop();
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('My invite'));
        await t.tap(find.text('My invite'));
        await t.pumpAndSettle();
        expect(find.text(service.inviteCode), findsOneWidget);
        await snapshot(t, 'community-invite-${brightness.name}');
        await t.tap(find.byTooltip('Close invite'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        service.dispose();
        state.dispose();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      },
    );
  }
  testWidgets(
    'group chat sends, replies, cheers, shows tied ranks, and leaves',
    (t) async {
      final state = await freshSocialState();
      final service = TestCommunityService();
      final group = communityGroups.firstWhere((g) => g.id == 'cal-2000');
      await prepare(
        t,
        const Size(390, 844),
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: kayleoTheme(),
          home: CommunityRoomScreen(
            state: state,
            service: service,
            group: group,
          ),
        ),
      );
      expect(find.text('My lunch bowl'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Hello circle');
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(service.sent, ['Hello circle']);
      await t.tap(find.text('Reply'));
      await t.pumpAndSettle();
      expect(find.text('Replying to Maya'), findsOneWidget);
      await t.tap(find.text('Cheer'));
      await t.pumpAndSettle();
      expect(service.cheersSent, 1);
      await snapshot(t, 'community-chat-live');
      await t.tap(find.text('Streaks'));
      await t.pumpAndSettle();
      expect(find.text('#1'), findsNWidgets(2));
      expect(find.text('#3'), findsOneWidget);
      await snapshot(t, 'community-streaks-live');
      await t.tap(find.text('Challenge'));
      await t.pumpAndSettle();
      expect(find.text('THE SHOW-UP CLUB'), findsOneWidget);
      await snapshot(t, 'community-challenge-live');
      await t.tap(find.byTooltip('Circle options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Leave circle'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Leave circle'));
      await t.pumpAndSettle();
      expect(service.joined, isEmpty);
      await t.pumpWidget(const SizedBox());
      service.dispose();
      state.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'friends compare nutrition and movement, then remove the connection',
    (t) async {
      final state = await freshSocialState();
      final service = TestCommunityService();
      await prepare(
        t,
        const Size(390, 844),
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: kayleoTheme(),
          home: FriendRoomScreen(
            state: state,
            service: service,
            pair: 'test-pair',
            peer: 'test-peer',
            name: 'Maya',
          ),
        ),
      );
      await t.tap(find.text('Together'));
      await t.pumpAndSettle();
      expect(find.text('1800 kcal'), findsWidgets);
      expect(find.text('35 min movement'), findsWidgets);
      await snapshot(t, 'community-friends-together');
      await t.tap(find.byTooltip('Friend options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove friend'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Remove friend'));
      await t.pumpAndSettle();
      expect(service.removedPeer, 'test-peer');
      await t.pumpWidget(const SizedBox());
      service.dispose();
      state.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    },
  );
  testWidgets('group and friend rooms fit 320px at double text size', (
    t,
  ) async {
    final state = await freshSocialState();
    final service = TestCommunityService();
    final group = communityGroups.firstWhere((g) => g.id == 'cal-2000');
    await prepare(
      t,
      const Size(320, 640),
      MaterialApp(
        theme: kayleoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CommunityRoomScreen(state: state, service: service, group: group),
      ),
    );
    expect(t.takeException(), isNull);
    for (final tab in ['Streaks', 'Challenge']) {
      await t.tap(find.text(tab));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
    await prepare(
      t,
      const Size(320, 640),
      MaterialApp(
        theme: kayleoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: FriendRoomScreen(
          state: state,
          service: service,
          pair: 'test-pair',
          peer: 'test-peer',
          name: 'Maya',
        ),
      ),
    );
    await t.tap(find.text('Together'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    service.dispose();
    state.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
