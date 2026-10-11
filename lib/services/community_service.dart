import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/app_state.dart';
import '../data/community_models.dart';
import '../data/models.dart';

/// All social reads are listeners; Firestore rules enforce membership and invites.
/// The private diary is never exposed to a social query.
class CommunityService extends ChangeNotifier {
  CommunityService({this.firestore});
  static final instance = CommunityService();
  final FirebaseFirestore? firestore;
  FirebaseFirestore get db => firestore ?? FirebaseFirestore.instance;
  AppState? _state;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  Timer? _debounce, _clock;
  int _generation = 0;
  bool ready = false;
  String? error;
  Map<String, dynamic> profile = {};
  String? get uid => _state?.accountUid;
  bool get available =>
      uid != null && _state?.demo == false && _state?.signedOut == false;
  String get inviteCode => profile['inviteCode'] as String? ?? '';
  List<String> get joined => List<String>.from(profile['joined'] ?? []);
  bool get sharesNutrition => profile['shareNutrition'] == true;
  bool get sharesActivity => profile['shareActivity'] == true;
  String _lastProgress = '';

  void attach(AppState? state) {
    if (identical(state, _state)) return;
    _state?.removeListener(_changed);
    _profileSub?.cancel();
    _debounce?.cancel();
    _clock?.cancel();
    _state = state;
    final generation = ++_generation;
    ready = false;
    error = null;
    profile = {};
    _lastProgress = '';
    notifyListeners();
    if (!available) return;
    state!.addListener(_changed);
    unawaited(_initialize(state, generation));
  }

  String _code([String prefix = 'K']) {
    final random = Random.secure();
    return '$prefix-${List.generate(12, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  }

  Future<void> _initialize(AppState state, int generation) async {
    try {
      final ref = db.collection('socialUsers').doc(state.accountUid!);
      await db.runTransaction((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) return;
        final code = _code();
        final invite = db.collection('friendInvites').doc(code);
        if ((await tx.get(invite)).exists) {
          throw StateError('Please retry creating your invite.');
        }
        tx.set(ref, {
          'name': _name(state),
          'inviteCode': code,
          'joined': <String>[],
          'shareNutrition': false,
          'shareActivity': false,
        });
        tx.set(invite, {'uid': state.accountUid!, 'name': _name(state)});
      });
      if (generation != _generation) return;
      _profileSub = ref.snapshots().listen((snapshot) {
        if (generation != _generation) return;
        profile = snapshot.data() ?? {};
        ready = snapshot.exists;
        error = null;
        notifyListeners();
        _changed();
      }, onError: (Object e) => _failed(e, generation));
      _clock = Timer.periodic(const Duration(minutes: 1), (_) => _changed());
    } catch (e) {
      _failed(e, generation);
    }
  }

  String _name(AppState state) {
    final value = state.profile.name.trim();
    return value.isEmpty
        ? 'Kayleo member'
        : value.substring(0, min(60, value.length));
  }

  void _failed(Object e, int generation) {
    if (generation != _generation) return;
    error = socialError(e);
    notifyListeners();
  }

  void retry() {
    final state = _state;
    attach(null);
    attach(state);
  }

  void _changed() {
    if (_state?.signedOut == true) {
      attach(null);
      return;
    }
    _debounce?.cancel();
    if (!ready || !available) return;
    final generation = _generation;
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        await publishProgress();
      } catch (e) {
        _failed(e, generation);
      }
    });
  }

  static Map<String, dynamic> progress(
    AppState state, {
    required bool nutrition,
    required bool activity,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    return {
      'name': state.profile.name.trim().isEmpty
          ? 'Kayleo member'
          : state.profile.name.trim().substring(
              0,
              min(60, state.profile.name.trim().length),
            ),
      'date': dateKey(today),
      'streak': state.streak,
      'days': List.generate(7, (i) {
        final day = DateTime(today.year, today.month, today.day - i);
        final totals = state.totalsFor(day);
        return {
          'date': dateKey(day),
          'nutrition': nutrition
              ? {
                  'calories': totals.calories.round(),
                  'protein': totals.protein.round(),
                  'carbs': totals.carbs.round(),
                  'fat': totals.fat.round(),
                }
              : null,
          'activity': activity
              ? {'minutes': state.activityMinutes[dateKey(day)] ?? 0}
              : null,
        };
      }),
    };
  }

  Future<void> publishProgress() async {
    if (!available || !ready) return;
    final state = _state!;
    final id = uid!;
    final generation = _generation;
    final payload = progress(
      state,
      nutrition: sharesNutrition,
      activity: sharesActivity,
    );
    final fingerprint = jsonEncode([payload, joined]);
    if (fingerprint == _lastProgress) return;
    final batch = db.batch();
    batch.set(db.collection('socialProgress').doc(id), {
      ...payload,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final group in joined) {
      batch.update(
        db.collection('communities').doc(group).collection('members').doc(id),
        {
          'name': _name(state),
          'streak': state.streak,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    }
    await batch.commit();
    if (generation == _generation) _lastProgress = fingerprint;
  }

  Future<void> sharing({bool? nutrition, bool? activity}) async {
    _require();
    final batch = db.batch();
    batch.update(db.collection('socialUsers').doc(uid!), {
      'shareNutrition': ?nutrition,
      'shareActivity': ?activity,
    });
    batch.set(db.collection('socialProgress').doc(uid!), {
      ...progress(
        _state!,
        nutrition: nutrition ?? sharesNutrition,
        activity: activity ?? sharesActivity,
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    _lastProgress = '';
    _changed();
  }

  void _require() {
    if (!available || !ready) {
      throw StateError(
        'Sign in to your account and connect to use the community.',
      );
    }
  }

  Future<void> join(CommunityGroup group) async {
    _require();
    final batch = db.batch();
    batch.update(db.collection('socialUsers').doc(uid!), {
      'joined': FieldValue.arrayUnion([group.id]),
    });
    batch.set(
      db
          .collection('communities')
          .doc(group.id)
          .collection('members')
          .doc(uid!),
      {
        'name': _name(_state!),
        'streak': _state!.streak,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  Future<void> leave(CommunityGroup group) async {
    _require();
    final batch = db.batch();
    batch.update(db.collection('socialUsers').doc(uid!), {
      'joined': FieldValue.arrayRemove([group.id]),
    });
    batch.delete(
      db
          .collection('communities')
          .doc(group.id)
          .collection('members')
          .doc(uid!),
    );
    if (group.isCustom) {
      batch.delete(
        db
            .collection('communityAccess')
            .doc(group.id)
            .collection('users')
            .doc(uid!),
      );
    }
    await batch.commit();
  }

  Future<List<CommunityGroup>> customGroups() async {
    if (!available || !ready) return const [];
    final customIds = joined
        .where((id) => !communityGroups.any((group) => group.id == id))
        .toList();
    if (customIds.isEmpty) return const [];
    final snapshots = await Future.wait(
      customIds.map((id) => db.collection('communities').doc(id).get()),
    );
    return [
      for (final snapshot in snapshots)
        if (snapshot.exists)
          CommunityGroup.custom(snapshot.id, snapshot.data()!),
    ];
  }

  Future<CommunityGroup> createCommunity(
    String rawName,
    String rawDescription,
  ) async {
    _require();
    final name = rawName.trim();
    final description = rawDescription.trim();
    if (name.isEmpty || name.length > 60) {
      throw const FormatException('Use a community name of 1–60 characters.');
    }
    if (description.isEmpty || description.length > 180) {
      throw const FormatException(
        'Use a short description of 1–180 characters.',
      );
    }
    if (joined.length >= 40) {
      throw const FormatException(
        'Leave a circle before creating another one.',
      );
    }
    final groupId = 'c-${_code('').replaceAll('-', '').toLowerCase()}';
    final code = _code('C');
    final groupData = {
      'name': name,
      'description': description,
      'ownerId': uid!,
      'inviteCode': code,
    };
    final group = CommunityGroup.custom(groupId, groupData);
    final batch = db.batch();
    batch.set(db.collection('communities').doc(groupId), {
      ...groupData,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(db.collection('communityInvites').doc(code), {
      'groupId': groupId,
      'name': name,
      'description': description,
      'ownerId': uid!,
    });
    batch.update(db.collection('socialUsers').doc(uid!), {
      'joined': FieldValue.arrayUnion([groupId]),
    });
    batch.set(
      db.collection('communities').doc(groupId).collection('members').doc(uid!),
      {
        'name': _name(_state!),
        'streak': _state!.streak,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      db
          .collection('communityAccess')
          .doc(groupId)
          .collection('users')
          .doc(uid!),
      {'inviteCode': code},
    );
    await batch.commit();
    return group;
  }

  Future<CommunityGroup> joinCommunity(String rawInvite) async {
    _require();
    final code = CommunityInvite.parse(rawInvite);
    if (joined.length >= 40) {
      throw const FormatException('Leave a circle before joining another one.');
    }
    return db.runTransaction((tx) async {
      final invitation = await tx.get(
        db.collection('communityInvites').doc(code),
      );
      if (!invitation.exists) {
        throw const FormatException(
          'This community invite is invalid or no longer available.',
        );
      }
      final groupId = invitation.data()!['groupId'] as String;
      if (joined.contains(groupId)) {
        throw const FormatException('You already belong to this community.');
      }
      final groupRef = db.collection('communities').doc(groupId);
      tx.update(db.collection('socialUsers').doc(uid!), {
        'joined': FieldValue.arrayUnion([groupId]),
      });
      tx.set(
        db
            .collection('communityAccess')
            .doc(groupId)
            .collection('users')
            .doc(uid!),
        {'inviteCode': code},
      );
      tx.set(groupRef.collection('members').doc(uid!), {
        'name': _name(_state!),
        'streak': _state!.streak,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return CommunityGroup.custom(groupId, {
        ...invitation.data()!,
        'inviteCode': code,
      });
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> leaderboard(String group) => db
      .collection('communities')
      .doc(group)
      .collection('members')
      .orderBy('streak', descending: true)
      .limit(100)
      .snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> friends() => db
      .collection('friendships')
      .where('members', arrayContains: uid!)
      .snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>> friendship(String pair) =>
      db.collection('friendships').doc(pair).snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>> friendProgress(String peer) =>
      db.collection('socialProgress').doc(peer).snapshots();
  CollectionReference<Map<String, dynamic>> messages(
    String room, {
    required bool group,
  }) => db
      .collection(group ? 'communities' : 'friendships')
      .doc(room)
      .collection('messages');
  Stream<QuerySnapshot<Map<String, dynamic>>> conversation(
    String room, {
    required bool group,
  }) => messages(
    room,
    group: group,
  ).orderBy('createdAt', descending: true).limit(100).snapshots();

  Future<String> connect(String raw) async {
    _require();
    final code = FriendInvite.parse(raw);
    final me = uid!;
    return db.runTransaction((tx) async {
      final invitation = await tx.get(db.collection('friendInvites').doc(code));
      if (!invitation.exists) {
        throw const FormatException(
          'This invite is invalid or has been replaced.',
        );
      }
      final data = invitation.data()!;
      final peer = data['uid'] as String;
      if (peer == me) {
        throw const FormatException(
          'This is your own invite. Ask your friend for theirs.',
        );
      }
      final pair = FriendInvite.pairId(me, peer);
      final ref = db.collection('friendships').doc(pair);
      if ((await tx.get(ref)).exists) {
        throw const FormatException('You are already friends.');
      }
      tx.set(ref, {
        'members': [me, peer],
        'from': me,
        'to': peer,
        'inviteCode': code,
        'names': {me: _name(_state!), peer: data['name']},
        'createdAt': FieldValue.serverTimestamp(),
      });
      for (final entry in [(me, peer), (peer, me)]) {
        tx.set(
          db
              .collection('socialUsers')
              .doc(entry.$1)
              .collection('friends')
              .doc(entry.$2),
          {'pairId': pair},
        );
      }
      return pair;
    });
  }

  Future<void> unfriend(String pair, String peer) async {
    _require();
    final batch = db.batch();
    batch.delete(db.collection('friendships').doc(pair));
    batch.delete(
      db.collection('socialUsers').doc(uid!).collection('friends').doc(peer),
    );
    batch.delete(
      db.collection('socialUsers').doc(peer).collection('friends').doc(uid!),
    );
    await batch.commit();
  }

  Future<void> rotateInvite() async {
    _require();
    final old = inviteCode;
    final code = _code();
    final batch = db.batch();
    batch.delete(db.collection('friendInvites').doc(old));
    batch.set(db.collection('friendInvites').doc(code), {
      'uid': uid!,
      'name': _name(_state!),
    });
    batch.update(db.collection('socialUsers').doc(uid!), {'inviteCode': code});
    await batch.commit();
  }

  Future<void> send(
    String room,
    String text, {
    required bool group,
    Map<String, dynamic>? attachment,
    String? replyTo,
  }) async {
    _require();
    if (text.trim().isEmpty && attachment == null) return;
    if (text.trim().length > 2000) {
      throw const FormatException('Keep your message under 2,000 characters.');
    }
    await messages(room, group: group).add({
      'authorId': uid!,
      'authorName': _name(_state!),
      'body': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'attachment': attachment,
      'replyTo': replyTo,
    });
  }

  Future<void> deleteMessage(
    String room,
    String message, {
    required bool group,
  }) => messages(room, group: group).doc(message).delete();
  Future<void> cheer(
    String room,
    String message, {
    required bool group,
    required bool active,
  }) async {
    _require();
    final ref = messages(
      room,
      group: group,
    ).doc(message).collection('cheers').doc(uid!);
    if (active) {
      await ref.delete();
    } else {
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> cheers(
    String room,
    String message, {
    required bool group,
  }) => messages(
    room,
    group: group,
  ).doc(message).collection('cheers').limit(100).snapshots();
  Future<void> report(
    String room,
    String message, {
    required bool group,
  }) async {
    _require();
    await db.collection('socialReports').add({
      'reporter': uid!,
      'room': room,
      'message': message,
      'group': group,
      'reason': 'Inappropriate or harmful content',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    attach(null);
    super.dispose();
  }
}

String socialError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => 'Access is unavailable. Check your membership, or retry after community setup is deployed.',
      'unavailable' || 'network-request-failed' =>
        'You’re offline. Reconnect to sync conversations.',
      _ => 'Community could not sync. Check your connection and retry.',
    };
  }
  return error.toString().replaceFirst(
    RegExp(r'^(Bad state|FormatException):\s*'),
    '',
  );
}
