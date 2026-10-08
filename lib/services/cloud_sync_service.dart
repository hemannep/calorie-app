import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/app_state.dart';

/// Small independent records avoid a single oversized diary document.
/// Photos, device permissions, sample data and entitlement flags stay local.
class CloudDiaryCodec {
  static Map<String, String> encode(AppState state) {
    if (!state.onboarded || state.demo) return {};
    final j = state.toJson();
    final records = <String, String>{
      'profile': jsonEncode({'profile': j['profile'], 'onboarded': true}),
    };
    for (final kind in ['meals', 'templates', 'drinks', 'weights']) {
      for (final raw in j[kind] as List) {
        final value = Map<String, dynamic>.from(raw);
        value.remove('photo');
        value.remove('photoPath');
        final id = value['id'] ?? value['time'] ?? value['date'];
        records['$kind:${Uri.encodeComponent(id.toString())}'] = jsonEncode(
          value,
        );
      }
    }
    for (final kind in ['activityMinutes', 'milestoneUnlocks']) {
      for (final entry in (j[kind] as Map).entries) {
        records['$kind:${Uri.encodeComponent(entry.key.toString())}'] =
            jsonEncode(entry.value);
      }
    }
    return records;
  }

  static Map<String, dynamic> merge(
    AppState state,
    Map<String, String> records,
  ) {
    final j = jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>;
    final profile = records['profile'];
    if (profile != null) {
      final p = jsonDecode(profile) as Map;
      j['profile'] = p['profile'];
      j['onboarded'] = p['onboarded'];
    } else {
      j['onboarded'] = false;
    }
    for (final kind in ['meals', 'templates', 'drinks', 'weights']) {
      final existing = <String, Map<String, dynamic>>{};
      for (final raw in j[kind] as List) {
        final value = Map<String, dynamic>.from(raw);
        final id = value['id'] ?? value['time'] ?? value['date'];
        existing['$kind:${Uri.encodeComponent(id.toString())}'] = value;
      }
      j[kind] = records.entries.where((e) => e.key.startsWith('$kind:')).map((
        e,
      ) {
        final value = Map<String, dynamic>.from(jsonDecode(e.value));
        final photo = existing[e.key]?['photo'];
        if (photo != null) value['photo'] = photo;
        return value;
      }).toList();
    }
    for (final kind in ['activityMinutes', 'milestoneUnlocks']) {
      j[kind] = {
        for (final e in records.entries.where(
          (e) => e.key.startsWith('$kind:'),
        ))
          Uri.decodeComponent(e.key.substring(kind.length + 1)): jsonDecode(
            e.value,
          ),
      };
    }
    j['water'] =
        <String, int>{}; // Rebuilt from the hydration ledger by AppState.
    return j;
  }
}

class CloudDiarySnapshot {
  const CloudDiarySnapshot(
    this.records, {
    this.fromCache = false,
    this.pendingWrites = false,
  });
  final Map<String, String> records;
  final bool fromCache, pendingWrites;
}

abstract interface class CloudDiaryBackend {
  String? get currentUid;
  Stream<CloudDiarySnapshot> watch(String uid);
  Future<void> write(String uid, Map<String, String?> records);
}

class FirestoreDiaryBackend implements CloudDiaryBackend {
  @override
  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;
  CollectionReference<Map<String, dynamic>> collection(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('kayleoRecords');
  @override
  Stream<CloudDiarySnapshot> watch(String uid) =>
      collection(uid)
          .snapshots(includeMetadataChanges: true)
          .map(
            (snapshot) => CloudDiarySnapshot(
              {
                for (final doc in snapshot.docs)
                  if (doc.data()['deleted'] != true)
                    doc.id: doc.data()['payload'] as String,
              },
              fromCache: snapshot.metadata.isFromCache,
              pendingWrites: snapshot.metadata.hasPendingWrites,
            ),
          );
  @override
  Future<void> write(String uid, Map<String, String?> records) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final e in records.entries) {
      if ((e.value?.length ?? 0) > 450000) {
        throw StateError('Record too large');
      }
      batch.set(collection(uid).doc(e.key), {
        'payload': e.value ?? '',
        'deleted': e.value == null,
        'updatedAt': FieldValue.serverTimestamp(),
        'schemaVersion': 1,
      });
    }
    await batch.commit();
  }
}

class CloudSyncService {
  CloudSyncService({CloudDiaryBackend? backend})
    : _backend = backend ?? FirestoreDiaryBackend();
  static final instance = CloudSyncService();
  final CloudDiaryBackend _backend;
  Future<void> get settled => _queue;
  AppState? _state;
  StreamSubscription<CloudDiarySnapshot>? _subscription;
  Timer? _timer;
  Map<String, String> _baseline = {};
  Map<String, String?> _pending = {};
  Map<String, String> _remote = {};
  bool _applying = false;
  bool _serverConfirmed = false;
  Future<void> _queue = Future.value();
  int _generation = 0;
  String get _outboxKey => 'kayleo_cloud_outbox_${_state!.accountUid}_v1';

  void attach(AppState? state) {
    _state?.removeListener(_changed);
    _subscription?.cancel();
    _timer?.cancel();
    _generation++;
    _state = state;
    _baseline = {};
    _pending = {};
    _remote = {};
    _serverConfirmed = false;
    if (state?.accountUid == null || state!.signedOut) return;
    try {
      final raw = state.storage.getString(_outboxKey);
      if (raw != null) {
        final saved = jsonDecode(raw) as Map;
        _baseline = Map<String, String>.from(saved['baseline']);
        _pending = Map<String, String?>.from(saved['pending']);
      }
    } catch (_) {
      state.setCloudStatus(
        'Cloud backup needs attention. Your local diary is safe.',
      );
      return; // Preserve a damaged outbox instead of overwriting it.
    }
    final generation = _generation;
    state.addListener(_changed);
    _enqueue(() => _collect(state, generation));
    _subscription = _backend
        .watch(state.accountUid!)
        .listen(
          (snapshot) {
            _enqueue(() async {
              if (!_active(state, generation) || state.demo) return;
              await _collect(state, generation);
              if (snapshot.fromCache || snapshot.pendingWrites) {
                _serverConfirmed = false;
                state.setCloudStatus(
                  'Waiting for cloud confirmation. Your local diary is safe.',
                );
                return;
              }
              _serverConfirmed = true;
              _remote = Map<String, String>.from(snapshot.records);
              final merged = Map<String, String>.from(_remote);
              for (final e in _pending.entries) {
                if (e.value == null) {
                  merged.remove(e.key);
                } else {
                  merged[e.key] = e.value!;
                }
              }
              _applying = true;
              try {
                await state.applyCloudSnapshot(
                  CloudDiaryCodec.merge(state, merged),
                );
                _baseline = CloudDiaryCodec.encode(state);
                await _save(state, generation);
              } finally {
                _applying = false;
              }
              await _upload(state, generation);
            });
          },
          onError: (Object error) {
            if (_active(state, generation)) {
              _serverConfirmed = false;
              state.setCloudStatus(
                'Cloud unavailable. Changes are saved on this device.',
              );
            }
          },
        );
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    refresh();
  }

  bool _active(AppState state, int generation) =>
      generation == _generation &&
      identical(state, _state) &&
      !state.signedOut &&
      _backend.currentUid == state.accountUid;

  void _enqueue(Future<void> Function() action) {
    final target = _state;
    final generation = _generation;
    _queue = _queue.then((_) => action()).catchError((Object error) {
      if (target != null && _active(target, generation)) {
        target.setCloudStatus(
          'Cloud unavailable. Your local diary is safe; retry when connected.',
        );
      }
    });
  }

  void _changed() {
    final state = _state;
    if (state == null || _applying) return;
    if (state.signedOut) {
      attach(null);
      return;
    }
    if (!state.demo &&
        jsonEncode(CloudDiaryCodec.encode(state)) == jsonEncode(_baseline)) {
      return;
    }
    final generation = _generation;
    _enqueue(() async {
      await _collect(state, generation);
      await _upload(state, generation);
    });
  }

  Future<void> _collect(AppState state, int generation) async {
    if (!_active(state, generation)) return;
    if (state.demo) {
      state.setCloudStatus('Sample diary stays on this device.');
      return;
    }
    final current = CloudDiaryCodec.encode(state);
    for (final id in {..._baseline.keys, ...current.keys}) {
      if (_baseline[id] != current[id]) _pending[id] = current[id];
    }
    _baseline = current;
    await _save(state, generation);
  }

  Future<void> _save(AppState state, int generation) async {
    if (!_active(state, generation)) return;
    if (!await state.storage.setString(
      _outboxKey,
      jsonEncode({'baseline': _baseline, 'pending': _pending}),
    )) {
      throw StateError('Could not save the cloud outbox.');
    }
  }

  Future<void> _upload(AppState state, int generation) async {
    if (!_active(state, generation) || state.demo) return;
    if (_pending.isEmpty) {
      state.setCloudStatus(
        _serverConfirmed
            ? 'Cloud backup up to date'
            : 'Waiting for cloud confirmation. Your local diary is safe.',
      );
      return;
    }
    state.setCloudStatus('Backing up changes…');
    while (_pending.isNotEmpty && _active(state, generation)) {
      final portion = Map<String, String?>.fromEntries(
        _pending.entries.take(200),
      );
      await _backend
          .write(state.accountUid!, portion)
          .timeout(const Duration(seconds: 8));
      if (!_active(state, generation)) return;
      for (final e in portion.entries) {
        if (_pending.containsKey(e.key) && _pending[e.key] == e.value) {
          _pending.remove(e.key);
        }
      }
      await _save(state, generation);
    }
    if (_active(state, generation)) {
      state.setCloudStatus('Cloud backup up to date');
    }
  }

  /// Save the latest edits to the UID-scoped outbox before ending the session.
  Future<void> prepareSignOut() async {
    final state = _state;
    if (state == null) return;
    await state.writesComplete;
    await _collect(state, _generation);
  }

  void refresh() {
    final state = _state;
    if (state == null) return;
    final generation = _generation;
    _enqueue(() async {
      await _collect(state, generation);
      await _upload(state, generation);
    });
  }
}
