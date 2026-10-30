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
  Stream<QuerySnapshot<Map<String, dynamic>>>? _friendsStream;
  String? _friendsUid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _getFriendsStream() {
    final uid = widget.service.uid;
    if (_friendsStream == null || _friendsUid != uid) {
      _friendsUid = uid;
      _friendsStream = widget.service.friends().asBroadcastStream();
    }
    return _friendsStream!;
  }

  @override
  void didUpdateWidget(FriendsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _friendsStream = null;
      _friendsUid = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (service.ready) ...[_friendsSection(onlyWhenHasFriends: true)],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: forest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: lime.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: lime,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: LocalizedText(
                      'Grow together',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
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
                        LocalizedText(
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
              const SizedBox(height: 8),
              const LocalizedText(
                'Connect with someone you trust, chat privately, and keep each other moving forward.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
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
                      icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                      label: const LocalizedText('My invite'),
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
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                      label: LocalizedText(busy ? 'Connecting…' : 'Add friend'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!service.ready)
          const SocialEmpty(
            Icons.people_outline_rounded,
            'Friends, by invitation',
            'Sign in and connect to create your friend code.',
          )
        else
          _friendsSection(onlyWhenHasFriends: false),
      ],
    );
  }

  Widget _friendsSection({required bool onlyWhenHasFriends}) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getFriendsStream(),
        builder: (context, snapshot) {
          final hasFriends = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
          if (hasFriends != onlyWhenHasFriends) return const SizedBox.shrink();
          if (snapshot.hasError) {
            return SocialSyncError(
              message: socialError(snapshot.error!),
              retry: () {
                setState(() => _friendsStream = null);
                widget.service.retry();
              },
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LocalizedText(
                'Your friends',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (hasFriends)
                for (final doc in snapshot.data!.docs) _friend(doc)
              else
                const SocialEmpty(
                  Icons.waving_hand_outlined,
                  'Every journey needs a little company',
                  'Share an invite to chat privately and follow each other’s progress.',
                ),
              const SizedBox(height: 12),
            ],
          );
        },
      );

  Widget _friend(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final service = widget.service;
    final data = doc.data();
    final peer = (data['members'] as List).cast<String>().firstWhere(
      (id) => id != service.uid,
    );
    final name = (data['names'] as Map)[peer] as String;
    void openRoom() => Navigator.push(
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
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        padding: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(KayleoRadius.large),
          onTap: openRoom,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SocialAvatar(name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LocalizedText(
                        'Chat & progress',
                        style: TextStyle(
                          color: context.kayleoMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.translate('Open chat with $name'),
                  onPressed: openRoom,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Connect a friend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LocalizedText(
              'Paste their full invite code, or scan their Kayleo QR. This connects both of you immediately.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 128,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: context.l10n.translate('Friend invite code'),
                hintText: context.l10n.translate('K-…'),
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
              label: const LocalizedText('Scan friend QR'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const LocalizedText('Connect'),
          ),
        ],
      ),
    );
    // Wait for the dialog route to finish using its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || raw == null) return;
    final sharingConfirmed = await showFriendSharingSettings(
      context,
      widget.service,
      connecting: true,
    );
    if (!mounted || !sharingConfirmed) return;
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
                        LocalizedText(
                          'Your friend pass',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.35,
                          ),
                        ),
                        SizedBox(height: 2),
                        LocalizedText(
                          'One scan connects both of you',
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.translate('Close invite'),
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
                        LocalizedText(
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
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const LocalizedText(
                      'Scan with Kayleo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const LocalizedText(
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
                      tooltip: context.l10n.translate('Copy invite code'),
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
                  label: const LocalizedText('Share friend pass'),
                ),
              ),
              const SizedBox(height: 8),
              LocalizedText(
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
                label: const LocalizedText('Create a new code'),
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

class CommunityInviteDialog extends StatelessWidget {
  const CommunityInviteDialog({super.key, required this.group});
  final CommunityGroup group;

  @override
  Widget build(BuildContext context) {
    final code = group.inviteCode!;
    return Dialog(
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
                  IconBox(Icons.groups_2_outlined, size: 40),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalizedText(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const LocalizedText(
                          'Private community invite',
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.translate('Close community invite'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: forest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: QrImageView(
                        data: CommunityInvite.qr(code),
                        size: 185,
                        backgroundColor: Colors.white,
                        dataModuleStyle: const QrDataModuleStyle(
                          color: Colors.black,
                        ),
                        eyeStyle: const QrEyeStyle(color: Colors.black),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const LocalizedText(
                      'Scan to join this community',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.kayleoSurfaces.soft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        code,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .7,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.translate('Copy community code'),
                      onPressed: () => socialAction(
                        context,
                        () => Clipboard.setData(ClipboardData(text: code)),
                        success: 'Community code copied',
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
                            'Join my ${group.name} community on Kayleo with this private code: $code',
                        sharePositionOrigin: _dialogShareOrigin(context),
                      ),
                    );
                  }),
                  icon: const Icon(Icons.ios_share_rounded, size: 17),
                  label: const LocalizedText('Share community invite'),
                ),
              ),
              const SizedBox(height: 8),
              LocalizedText(
                'Only people with this code or QR can join.',
                style: TextStyle(color: context.kayleoMuted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityJoinDialog extends StatefulWidget {
  const CommunityJoinDialog({super.key, required this.service});
  final CommunityService service;

  @override
  State<CommunityJoinDialog> createState() => _CommunityJoinDialogState();
}

class _CommunityJoinDialogState extends State<CommunityJoinDialog> {
  final code = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const LocalizedText('Join a private community'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocalizedText(
          'Enter its private code or scan the creator’s QR.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: code,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: context.l10n.translate('Community invite code'),
            hintText: context.l10n.translate('C-…'),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final value = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FriendQRScanner(community: true),
                    ),
                  );
                  if (value != null) {
                    code.text = value;
                  }
                },
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const LocalizedText('Scan community QR'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const LocalizedText('Cancel'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                CommunityGroup? group;
                final success = await socialAction(context, () async {
                  group = await widget.service.joinCommunity(code.text);
                }, success: 'Community joined');
                if (!mounted) return;
                setState(() => busy = false);
                if (success) Navigator.pop(this.context, group);
              },
        child: LocalizedText(busy ? 'Joining…' : 'Join'),
      ),
    ],
  );
}

Rect _dialogShareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

class FriendQRScanner extends StatefulWidget {
  const FriendQRScanner({super.key, this.community = false});
  final bool community;
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
    appBar: AppBar(
      title: LocalizedText(
        widget.community ? 'Scan community QR' : 'Scan friend QR',
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: LocalizedText(
            widget.community
                ? 'Scan a private Kayleo community QR to join.'
                : 'Scan your friend’s Kayleo QR to connect both accounts.',
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
                        final code = widget.community
                            ? CommunityInvite.parse(barcode.rawValue ?? '')
                            : FriendInvite.parse(barcode.rawValue ?? '');
                        finished = true;
                        controller.stop();
                        Navigator.pop(context, code);
                        return;
                      } on FormatException {
                        setState(
                          () => error = widget.community
                              ? 'That isn’t a Kayleo community QR.'
                              : 'That isn’t a Kayleo friend QR. Try your friend’s invite QR.',
                        );
                      }
                    }
                  },
                ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: LocalizedText(error!, textAlign: TextAlign.center),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LocalizedText('Enter a code instead'),
          ),
        ),
      ],
    ),
  );
}

Future<bool> showFriendSharingSettings(
  BuildContext context,
  CommunityService service, {
  bool connecting = false,
}) async {
  var nutrition = service.sharesNutrition;
  var activity = service.sharesActivity;
  final save = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: LocalizedText(
          connecting ? 'Choose sharing access' : 'Sharing settings',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                connecting
                    ? 'Before connecting, choose what your friends can see. These choices apply to this friend and your existing friends.'
                    : 'Choose what all of your connected friends can see in the Together tab.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const LocalizedText('Nutrition summaries'),
                subtitle: const LocalizedText(
                  'Calories and macros from the last 7 days',
                ),
                value: nutrition,
                onChanged: (value) => setDialogState(() => nutrition = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const LocalizedText('Activity summaries'),
                subtitle: const LocalizedText(
                  'Logged movement minutes from the last 7 days',
                ),
                value: activity,
                onChanged: (value) => setDialogState(() => activity = value),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.kayleoSurfaces.soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                      color: context.kayleoPrimary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: LocalizedText(
                        'Weight, diary notes, meal details, and photos always stay private.',
                        style: TextStyle(fontSize: 11, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: LocalizedText(connecting ? 'Save & connect' : 'Save'),
          ),
        ],
      ),
    ),
  );
  if (save != true || !context.mounted) return false;
  if (nutrition == service.sharesNutrition &&
      activity == service.sharesActivity) {
    return true;
  }
  return socialAction(
    context,
    () => service.sharing(nutrition: nutrition, activity: activity),
    success: connecting ? null : 'Sharing settings updated',
  );
}

class FriendRoomScreen extends StatefulWidget {
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
  State<FriendRoomScreen> createState() => _FriendRoomScreenState();
}

class _FriendRoomScreenState extends State<FriendRoomScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _friendshipStream = widget
      .service
      .friendship(widget.pair);

  @override
  void didUpdateWidget(FriendRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service || oldWidget.pair != widget.pair) {
      _friendshipStream = widget.service.friendship(widget.pair);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _friendshipStream,
        builder: (context, snapshot) {
          final connected = snapshot.hasData && snapshot.data!.exists;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Row(
                children: [
                  SocialAvatar(widget.name, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalizedText(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        LocalizedText(
                          connected ? 'Direct Message' : 'Offline',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: context.kayleoMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                if (connected)
                  PopupMenuButton<String>(
                    tooltip: context.l10n.translate('Friend options'),
                    onSelected: (value) async {
                      if (value == 'sharing') {
                        await showFriendSharingSettings(
                          context,
                          widget.service,
                        );
                        return;
                      }
                      if (await socialConfirm(
                            context,
                            'Remove ${widget.name}?',
                            'Your private chat and shared progress will no longer be accessible. Connecting again requires an invite code or QR.',
                            'Remove friend',
                          ) &&
                          context.mounted) {
                        final ok = await socialAction(
                          context,
                          () =>
                              widget.service.unfriend(widget.pair, widget.peer),
                        );
                        if (ok && context.mounted) Navigator.pop(context);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'sharing',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.visibility_outlined),
                          title: LocalizedText('Sharing settings'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.person_remove_outlined),
                          title: LocalizedText('Remove friend'),
                        ),
                      ),
                    ],
                  ),
              ],
              bottom: connected
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(48),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: context.kayleoSurfaces.soft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          dividerColor: Colors.transparent,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicator: BoxDecoration(
                            color: context.kayleoSurfaces.card,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .04),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          unselectedLabelColor: context.kayleoMuted,
                          tabs: [
                            _FriendRoomTab(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: 'Chat',
                            ),
                            _FriendRoomTab(
                              icon: Icons.insights_rounded,
                              label: 'Together',
                            ),
                          ],
                        ),
                      ),
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
                    controller: _tabController,
                    children: [
                      CommunityConversation(
                        state: widget.state,
                        service: widget.service,
                        room: widget.pair,
                        isGroup: false,
                      ),
                      FriendProgressPanel(
                        state: widget.state,
                        service: widget.service,
                        peer: widget.peer,
                        name: widget.name,
                      ),
                    ],
                  ),
          );
        },
      );
}

class _FriendRoomTab extends StatelessWidget {
  const _FriendRoomTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (textScale < 1.5) ...[
          Icon(icon, size: 15),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: LocalizedText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
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
                    const LocalizedText(
                      'A LITTLE ACCOUNTABILITY',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const LocalizedText(
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
              LocalizedText(
                updated == null
                    ? 'Waiting for sync confirmation'
                    : 'Friend synced ${DateFormat('MMM d, h:mm a').format(updated.toDate().toLocal())}',
                style: TextStyle(color: context.kayleoMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              LocalizedText(
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
        child: LocalizedText(
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
          LocalizedText(
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
      LocalizedText(
        name,
        style: TextStyle(
          color: context.kayleoPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      if (nutrition == null)
        LocalizedText(
          'Nutrition is private',
          style: TextStyle(color: context.kayleoMuted, fontSize: 12),
        )
      else ...[
        LocalizedText(
          '${nutrition['calories']} kcal',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        LocalizedText(
          'P ${nutrition['protein']}g · C ${nutrition['carbs']}g · F ${nutrition['fat']}g',
          style: TextStyle(
            color: context.kayleoMuted,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      ],
      const SizedBox(height: 8),
      LocalizedText(
        activity == null
            ? 'Activity is private'
            : '${activity['minutes']} min movement',
        style: TextStyle(color: context.kayleoMuted, fontSize: 12),
      ),
    ],
  );
}
