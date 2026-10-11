import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../data/community_models.dart';
import '../data/models.dart';
import '../services/community_service.dart';
import 'community_room.dart';
import 'community_widgets.dart';

class FriendsPanel extends StatefulWidget {
  const FriendsPanel({super.key, required this.state, required this.service});
  final AppState state;
  final CommunityService service;
  @override
  State<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends State<FriendsPanel> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: forest,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: lime.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: lime,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Text(
                      'Grow together',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, color: lime, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'INVITE ONLY',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 8,
                            letterSpacing: .7,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Connect with someone you trust, chat privately, and keep each other moving forward.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: lime,
                        foregroundColor: forest,
                      ),
                      onPressed: service.ready
                          ? () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  FriendInviteDialog(service: service),
                            )
                          : null,
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: const Text('My invite'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .25),
                        ),
                      ),
                      onPressed: service.ready && !busy ? _connect : null,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: Text(busy ? 'Connecting…' : 'Add friend'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          padding: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 20),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Shared with friends',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'You decide what appears in your shared 7-day view.',
                style: TextStyle(color: context.kayleoMuted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Nutrition summaries'),
                subtitle: const Text('Calories and macros for the last 7 days'),
                value: service.sharesNutrition,
                onChanged: service.ready
                    ? (value) => socialAction(
                        context,
                        () => service.sharing(nutrition: value),
                      )
                    : null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Activity summaries'),
                subtitle: const Text(
                  'Logged movement minutes for the last 7 days',
                ),
                value: service.sharesActivity,
                onChanged: service.ready
                    ? (value) => socialAction(
                        context,
                        () => service.sharing(activity: value),
                      )
                    : null,
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.kayleoSurfaces.soft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 17,
                      color: context.kayleoPrimary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Weight, diary notes, and meal photos always stay private.',
                        style: TextStyle(
                          color: context.kayleoMuted,
                          fontSize: 10,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your friends',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            if (service.ready)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.kayleoSurfaces.soft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'ACCOUNTABILITY',
                  style: TextStyle(
                    color: context.kayleoMuted,
                    fontSize: 8,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!service.ready)
          const SocialEmpty(
            Icons.people_outline_rounded,
            'Friends, by invitation',
            'Sign in and connect to create your friend code.',
          )
        else
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: service.friends(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SocialSyncError(
                  message: socialError(snapshot.error!),
                  retry: service.retry,
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.data!.docs.isEmpty) {
                return const SocialEmpty(
                  Icons.waving_hand_outlined,
                  'Every journey needs a little company',
                  'Share an invite to chat privately and follow each other’s progress.',
                );
              }
              return Column(
                children: [for (final doc in snapshot.data!.docs) _friend(doc)],
              );
            },
          ),
      ],
    );
  }

  Widget _friend(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final service = widget.service;
    final data = doc.data();
    final peer = (data['members'] as List).cast<String>().firstWhere(
      (id) => id != service.uid,
    );
    final name = (data['names'] as Map)[peer] as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        padding: 16,
        child: Row(
          children: [
            SocialAvatar(name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chat & progress',
                    style: TextStyle(color: context.kayleoMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open chat with $name',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FriendRoomScreen(
                    state: widget.state,
                    service: service,
                    pair: doc.id,
                    peer: peer,
                    name: name,
                  ),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect a friend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste their full invite code, or scan their Kayleo QR. This connects both of you immediately.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 128,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Friend invite code',
                hintText: 'K-…',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final value = await Navigator.push<String>(
                  dialogContext,
                  MaterialPageRoute(builder: (_) => const FriendQRScanner()),
                );
                if (value != null && dialogContext.mounted) {
                  Navigator.pop(dialogContext, value);
                }
              },
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan friend QR'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    // Wait for the dialog route to finish using its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || raw == null) return;
    setState(() => busy = true);
    await socialAction(
      context,
      () async {
        await widget.service.connect(raw);
      },
      success: 'You’re connected. Your friend can now see you on their device.',
    );
    if (mounted) setState(() => busy = false);
  }
}

class FriendInviteDialog extends StatelessWidget {
  const FriendInviteDialog({super.key, required this.service});
  final CommunityService service;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.kayleoSurfaces.soft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      color: context.kayleoPrimary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your friend pass',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.35,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'One scan connects both of you',
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close invite',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  color: forest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, color: lime, size: 13),
                        SizedBox(width: 5),
                        Text(
                          'PRIVATE INVITE',
                          style: TextStyle(
                            color: lime,
                            fontSize: 9,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    if (service.inviteCode.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(
                          data: FriendInvite.qr(service.inviteCode),
                          size: 190,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      'Scan with Kayleo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'or enter the invite code below',
                      style: TextStyle(color: Colors.white60, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: context.kayleoSurfaces.soft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        service.inviteCode,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .7,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copy invite code',
                      onPressed: () => socialAction(
                        context,
                        () => Clipboard.setData(
                          ClipboardData(text: service.inviteCode),
                        ),
                        success: 'Invite code copied',
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => socialAction(context, () async {
                    await SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Join me on Kayleo! Enter my friend invite code: ${service.inviteCode}',
                        sharePositionOrigin: _shareOrigin(context),
                      ),
                    );
                  }),
                  icon: const Icon(Icons.ios_share_rounded, size: 17),
                  label: const Text('Share friend pass'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Only share this with someone you trust.',
                style: TextStyle(color: context.kayleoMuted, fontSize: 10),
              ),
              TextButton.icon(
                onPressed: () async {
                  if (await socialConfirm(
                        context,
                        'Replace your invite?',
                        'Your old code and QR will stop working. Existing friends stay connected.',
                        'Replace code',
                      ) &&
                      context.mounted) {
                    await socialAction(
                      context,
                      service.rotateInvite,
                      success: 'Your new invite is ready',
                    );
                  }
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Create a new code'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Rect _shareOrigin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

class FriendQRScanner extends StatefulWidget {
  const FriendQRScanner({super.key});
  @override
  State<FriendQRScanner> createState() => _FriendQRScannerState();
}

class _FriendQRScannerState extends State<FriendQRScanner>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );
  bool finished = false;
  String? error;
  bool get supported =>
      kIsWeb ||
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (supported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  Future<void> _start() async {
    try {
      await controller.start();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Camera unavailable. Allow camera access in settings, or enter your friend’s code.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!supported || finished) return;
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan friend QR')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Scan your friend’s Kayleo QR to connect both accounts.',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: !supported
              ? const SocialEmpty(
                  Icons.qr_code_rounded,
                  'Use an invite code',
                  'QR scanning is available on supported phones and browsers.',
                )
              : MobileScanner(
                  controller: controller,
                  errorBuilder: (_, _) => const SocialEmpty(
                    Icons.no_photography_outlined,
                    'Camera unavailable',
                    'Allow camera access in settings, or go back and paste the invite code.',
                  ),
                  onDetect: (capture) {
                    if (finished) return;
                    for (final barcode in capture.barcodes) {
                      try {
                        final code = FriendInvite.parse(barcode.rawValue ?? '');
                        finished = true;
                        controller.stop();
                        Navigator.pop(context, code);
                        return;
                      } on FormatException {
                        setState(
                          () => error = 'That isn’t a Kayleo friend QR. Try your friend’s invite QR.',
                        );
                      }
                    }
                  },
                ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(error!, textAlign: TextAlign.center),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Enter a code instead'),
          ),
        ),
      ],
    ),
  );
}

class FriendRoomScreen extends StatelessWidget {
  const FriendRoomScreen({
    super.key,
    required this.state,
    required this.service,
    required this.pair,
    required this.peer,
    required this.name,
  });
  final AppState state;
  final CommunityService service;
  final String pair, peer, name;
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: service.friendship(pair),
        builder: (context, snapshot) {
          final connected = snapshot.hasData && snapshot.data!.exists;
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: Text(name),
                actions: [
                  if (connected)
                    PopupMenuButton<String>(
                      tooltip: 'Friend options',
                      onSelected: (_) async {
                        if (await socialConfirm(
                              context,
                              'Remove $name?',
                              'Your private chat and shared progress will no longer be accessible. Connecting again requires an invite code or QR.',
                              'Remove friend',
                            ) &&
                            context.mounted) {
                          final ok = await socialAction(
                            context,
                            () => service.unfriend(pair, peer),
                          );
                          if (ok && context.mounted) Navigator.pop(context);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove friend'),
                        ),
                      ],
                    ),
                ],
                bottom: connected
                    ? const TabBar(
                        tabs: [
                          Tab(text: 'Chat'),
                          Tab(text: 'Together'),
                        ],
                      )
                    : null,
              ),
              body: snapshot.hasError
                  ? const SocialSyncError()
                  : !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : !connected
                  ? const SocialEmpty(
                      Icons.person_remove_outlined,
                      'This connection has ended',
                      'Shared progress and chat are no longer available.',
                    )
                  : TabBarView(
                      children: [
                        CommunityConversation(
                          state: state,
                          service: service,
                          room: pair,
                          isGroup: false,
                        ),
                        FriendProgressPanel(
                          state: state,
                          service: service,
                          peer: peer,
                          name: name,
                        ),
                      ],
                    ),
            ),
          );
        },
      );
}

class FriendProgressPanel extends StatefulWidget {
  const FriendProgressPanel({
    super.key,
    required this.state,
    required this.service,
    required this.peer,
    required this.name,
  });
  final AppState state;
  final CommunityService service;
  final String peer, name;
  @override
  State<FriendProgressPanel> createState() => _FriendProgressPanelState();
}

class _FriendProgressPanelState extends State<FriendProgressPanel> {
  late final stream = widget.service.friendProgress(widget.peer);
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const SocialSyncError();
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!snapshot.data!.exists) {
        return const SocialEmpty(
          Icons.insights_outlined,
          'Progress will appear here',
          'Your friend’s app will sync their shared summaries when it connects.',
        );
      }
      final peer = snapshot.data!.data()!;
      final days = List<Map<String, dynamic>>.from(
        (peer['days'] as List).map(
          (day) => Map<String, dynamic>.from(day as Map),
        ),
      );
      final updated = peer['updatedAt'] as Timestamp?;
      return ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Panel(
                color: context.kayleoSurfaces.soft,
                border: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'A LITTLE ACCOUNTABILITY',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Two journeys.\nMore encouragement.',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        _streak('You', widget.state.streak),
                        _streak(widget.name, peer['streak'] as int),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                updated == null
                    ? 'Waiting for sync confirmation'
                    : 'Friend synced ${DateFormat('MMM d, h:mm a').format(updated.toDate().toLocal())}',
                style: TextStyle(color: context.kayleoMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                'Compare routines at your own pace. Different bodies have different goals. Dates follow each person’s device.',
                style: TextStyle(
                  color: context.kayleoMuted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              for (final day in days) ...[
                _day(context, day),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
    },
  );
  Widget _streak(String name, int streak) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(
        Icons.local_fire_department_rounded,
        color: KayleoColors.warning,
        size: 18,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          '$name · $streak days',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  Widget _day(BuildContext context, Map<String, dynamic> day) {
    final date = DateTime.parse(day['date'] as String);
    final own = widget.state.totalsFor(date);
    final nutrition = day['nutrition'] as Map?;
    final activity = day['activity'] as Map?;
    return Panel(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMM d').format(date),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _summary(
                  context,
                  'You',
                  {
                    'calories': own.calories.round(),
                    'protein': own.protein.round(),
                    'carbs': own.carbs.round(),
                    'fat': own.fat.round(),
                  },
                  {'minutes': widget.state.activityMinutes[dateKey(date)] ?? 0},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summary(context, widget.name, nutrition, activity),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(
    BuildContext context,
    String name,
    Map? nutrition,
    Map? activity,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        name,
        style: TextStyle(
          color: context.kayleoPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      if (nutrition == null)
        Text(
          'Nutrition is private',
          style: TextStyle(color: context.kayleoMuted, fontSize: 12),
        )
      else ...[
        Text(
          '${nutrition['calories']} kcal',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'P ${nutrition['protein']}g · C ${nutrition['carbs']}g · F ${nutrition['fat']}g',
          style: TextStyle(
            color: context.kayleoMuted,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        activity == null
            ? 'Activity is private'
            : '${activity['minutes']} min movement',
        style: TextStyle(color: context.kayleoMuted, fontSize: 12),
      ),
    ],
  );
}
