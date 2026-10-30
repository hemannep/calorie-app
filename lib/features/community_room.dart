import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../data/community_models.dart';
import '../data/models.dart';
import '../data/food_database.dart';
import '../services/community_service.dart';
import 'community_widgets.dart';

class CommunityRoomScreen extends StatefulWidget {
  const CommunityRoomScreen({
    super.key,
    required this.state,
    required this.service,
    required this.group,
  });
  final AppState state;
  final CommunityService service;
  final CommunityGroup group;
  @override
  State<CommunityRoomScreen> createState() => _CommunityRoomScreenState();
}

class _CommunityRoomScreenState extends State<CommunityRoomScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final joined =
          widget.service.joined.contains(widget.group.id) &&
          widget.service.available;
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 4,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.group.color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.group.icon,
                  size: 19,
                  color: widget.group.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      widget.group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    LocalizedText(
                      widget.group.category,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: context.kayleoMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (joined)
              PopupMenuButton<String>(
                tooltip: context.l10n.translate('Circle options'),
                onSelected: (_) async {
                  if (await socialConfirm(
                        context,
                        'Leave this circle?',
                        'You can join again at any time. Your previous messages remain in the conversation.',
                        'Leave circle',
                      ) &&
                      context.mounted) {
                    final ok = await socialAction(
                      context,
                      () => widget.service.leave(widget.group),
                    );
                    if (ok && context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'leave',
                    child: LocalizedText('Leave circle'),
                  ),
                ],
              ),
          ],
          bottom: joined
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(52),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: context.kayleoSurfaces.soft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: context.kayleoSurfaces.card,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                        unselectedLabelColor: context.kayleoMuted,
                        tabs: const [
                          Tab(
                            child: _RoomTab(
                              Icons.chat_bubble_outline_rounded,
                              'Chat',
                            ),
                          ),
                          Tab(
                            child: _RoomTab(
                              Icons.local_fire_department_outlined,
                              'Streaks',
                            ),
                          ),
                          Tab(
                            child: _RoomTab(Icons.flag_outlined, 'Challenge'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
        ),
        body: !joined
            ? const SocialEmpty(
                Icons.people_outline_rounded,
                'You’ve left this circle',
                'Join again from Discover to see the conversation.',
              )
            : TabBarView(
                controller: _tabController,
                children: [
                  CommunityConversation(
                    state: widget.state,
                    service: widget.service,
                    room: widget.group.id,
                    isGroup: true,
                  ),
                  CommunityLeaderboard(
                    state: widget.state,
                    service: widget.service,
                    group: widget.group,
                  ),
                  _Challenge(state: widget.state, group: widget.group),
                ],
              ),
      );
    },
  );
}

class _RoomTab extends StatelessWidget {
  const _RoomTab(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Three tabs are intentionally kept visible at once. At accessibility text
    // sizes, dropping the decorative icon leaves the label readable instead of
    // squeezing or overflowing the tab strip on compact phones.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (textScale < 1.5) ...[
          Icon(icon, size: 15),
          const SizedBox(width: 5),
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

class CommunityLeaderboard extends StatefulWidget {
  const CommunityLeaderboard({
    super.key,
    required this.state,
    required this.service,
    required this.group,
  });
  final AppState state;
  final CommunityService service;
  final CommunityGroup group;
  @override
  State<CommunityLeaderboard> createState() => _CommunityLeaderboardState();
}

class _CommunityLeaderboardState extends State<CommunityLeaderboard> {
  late final stream = widget.service.leaderboard(widget.group.id);
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SocialSyncError(message: socialError(snapshot.error!));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Panel(
                color: context.kayleoSurfaces.soft,
                border: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: widget.group.color,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    const LocalizedText(
                      'Consistency deserves\na little celebration.',
                      style: TextStyle(
                        fontSize: 24,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LocalizedText(
                      'Ranked by consecutive days logging a meal. Keep showing up at your pace. Streaks sync when each member opens Kayleo; tied streaks share a rank.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.7,
                        color: context.kayleoMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ListenableBuilder(
                listenable: widget.state,
                builder: (context, _) => Panel(
                  padding: 16,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        color: KayleoColors.carbs,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: LocalizedText(
                          'Your current streak',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      LocalizedText(
                        '${widget.state.streak} days',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const LocalizedText(
                'Circle streaks · top 100',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (docs.isEmpty)
                const SocialEmpty(
                  Icons.emoji_events_outlined,
                  'Start the first streak',
                  'Log a meal and build your next good habit.',
                ),
              for (var i = 0; i < docs.length; i++) ...[
                _row(docs, i),
                const SizedBox(height: 10),
              ],
              LocalizedText(
                'Streaks reflect member logs, not verified competition scores. No rankings by weight loss or calorie restriction.',
                style: TextStyle(
                  color: context.kayleoMuted,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ],
          );
        },
      );
  Widget _row(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int index,
  ) {
    final doc = docs[index];
    final data = doc.data();
    final streak = data['streak'] as int;
    final rank =
        docs.indexWhere((d) => (d.data()['streak'] as int) == streak) + 1;
    final name = data['name'] as String;
    final own = doc.id == widget.service.uid;
    return Panel(
      padding: 16,
      color: own ? context.kayleoSurfaces.soft : null,
      child: Row(
        children: [
          SizedBox(
            width: 35,
            child: LocalizedText(
              '#$rank',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: rank == 1 ? KayleoColors.warning : context.kayleoMuted,
              ),
            ),
          ),
          SocialAvatar(name, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: LocalizedText(
              own ? '$name · you' : name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.local_fire_department_rounded,
            color: KayleoColors.carbs,
            size: 20,
          ),
          const SizedBox(width: 4),
          LocalizedText(
            '$streak',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Challenge extends StatelessWidget {
  const _Challenge({required this.state, required this.group});
  final AppState state;
  final CommunityGroup group;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final days = List.generate(7, (i) => monday.add(Duration(days: i)));
      final complete = days
          .where((day) => !day.isAfter(today) && state.mealsFor(day).isNotEmpty)
          .length;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Panel(
            color: forest,
            border: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.wb_sunny_outlined, color: lime, size: 36),
                const SizedBox(height: 18),
                const LocalizedText(
                  'THE SHOW-UP CLUB',
                  style: TextStyle(
                    color: lime,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const LocalizedText(
                  '7 days.\nOne gentle habit.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 14),
                const LocalizedText(
                  'Log a meal each day this week. Share a check-in, cheer someone on, and let small steps add up.',
                  style: TextStyle(color: Colors.white70, height: 1.7),
                ),
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: complete / 7,
                  backgroundColor: Colors.white24,
                  color: lime,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 12),
                LocalizedText(
                  '$complete of 7 days · ${DateFormat('MMM d').format(monday)} week',
                  style: const TextStyle(
                    color: lime,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final day in days)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(
                !day.isAfter(today) && state.mealsFor(day).isNotEmpty
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: !day.isAfter(today) && state.mealsFor(day).isNotEmpty
                    ? context.kayleoPrimary
                    : context.kayleoMuted,
              ),
              title: LocalizedText(DateFormat('EEEE').format(day)),
              trailing: LocalizedText(
                day.isAfter(today)
                    ? 'Coming up'
                    : state.mealsFor(day).isEmpty
                    ? 'A fresh opportunity'
                    : 'You showed up',
                style: TextStyle(fontSize: 11, color: context.kayleoMuted),
              ),
            ),
          const SizedBox(height: 14),
          const LocalizedText(
            'Your checklist is personal and updates from your diary. There’s no calorie target to compete for. Use the Chat tab to share a check-in.',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
        ],
      );
    },
  );
}

class CommunityConversation extends StatefulWidget {
  const CommunityConversation({
    super.key,
    required this.state,
    required this.service,
    required this.room,
    required this.isGroup,
  });
  final AppState state;
  final CommunityService service;
  final String room;
  final bool isGroup;
  @override
  State<CommunityConversation> createState() => _CommunityConversationState();
}

class _CommunityConversationState extends State<CommunityConversation> {
  final text = TextEditingController();
  late Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final scroll = ScrollController();
  final hidden = <String>{};
  final older = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool sending = false, loadingOlder = false, hasOlder = true;
  String? replyId, replyName;
  Map<String, dynamic>? attachment;
  @override
  void initState() {
    super.initState();
    stream = widget.service.conversation(widget.room, group: widget.isGroup);
  }

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: context.kayleoSurfaces.soft.withValues(alpha: .6),
        child: Row(
          children: [
            Icon(
              widget.isGroup
                  ? Icons.lock_outline_rounded
                  : Icons.shield_outlined,
              size: 14,
              color: context.kayleoMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LocalizedText(
                widget.isGroup
                    ? 'Circle chat · Your private calorie diary and weights remain private.'
                    : 'Direct message · End-to-end private between you two.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: context.kayleoMuted,
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SocialSyncError(
                message: socialError(snapshot.error!),
                retry: () => setState(() {
                  stream = widget.service.conversation(
                    widget.room,
                    group: widget.isGroup,
                  );
                  older.clear();
                  hasOlder = true;
                }),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final live = snapshot.data!.docs;
            final byId = {
              for (final doc in [...older, ...live]) doc.id: doc,
            };
            final docs =
                byId.values.where((doc) => !hidden.contains(doc.id)).toList()
                  ..sort((a, b) {
                    final at = a.data()['createdAt'] as Timestamp?;
                    final bt = b.data()['createdAt'] as Timestamp?;
                    return (bt?.millisecondsSinceEpoch ?? 8640000000000000)
                        .compareTo(
                          at?.millisecondsSinceEpoch ?? 8640000000000000,
                        );
                  });
            if (docs.isEmpty) {
              return const SingleChildScrollView(
                child: SocialEmpty(
                  Icons.forum_outlined,
                  'Be the first to say hello',
                  'Share a meal, ask a question, or celebrate a little win.',
                ),
              );
            }
            return Column(
              children: [
                if (snapshot.data!.metadata.isFromCache)
                  const Padding(
                    padding: EdgeInsets.all(6),
                    child: LocalizedText(
                      'Showing cached messages · reconnect to sync',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount:
                        docs.length + (hasOlder && live.length >= 100 ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == docs.length) {
                        return Center(
                          child: TextButton(
                            onPressed: loadingOlder
                                ? null
                                : () => _loadOlder(docs.last),
                            child: LocalizedText(
                              loadingOlder
                                  ? 'Loading…'
                                  : 'Load earlier messages',
                            ),
                          ),
                        );
                      }
                      final doc = docs[index];
                      final stamp = (doc.data()['createdAt'] as Timestamp?)
                          ?.toDate()
                          .toLocal();

                      // Check if we need to show a date separator above this message
                      // (Since ListView is reverse: true, earlier chronological message is at index + 1)
                      bool showDateHeader = false;
                      if (stamp != null) {
                        if (index == docs.length - 1) {
                          showDateHeader = true;
                        } else {
                          final prevStamp =
                              (docs[index + 1].data()['createdAt']
                                      as Timestamp?)
                                  ?.toDate()
                                  .toLocal();
                          if (prevStamp != null) {
                            showDateHeader =
                                stamp.year != prevStamp.year ||
                                stamp.month != prevStamp.month ||
                                stamp.day != prevStamp.day;
                          }
                        }
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showDateHeader && stamp != null)
                            _dateHeader(stamp),
                          KeyedSubtree(
                            key: ValueKey(doc.id),
                            child: _message(doc, byId),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      if (replyId != null)
        _draftBar(
          'Replying to $replyName',
          () => setState(() {
            replyId = null;
            replyName = null;
          }),
        ),
      if (attachment != null)
        _draftBar(
          'Sharing: ${attachment!['title']}',
          () => setState(() => attachment = null),
        ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: context.kayleoSurfaces.card,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
            border: Border(
              top: BorderSide(color: context.kayleoSurfaces.border),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: sending ? null : _share,
                tooltip: context.l10n.translate(
                  'Share a meal or daily check-in',
                ),
                icon: Icon(
                  Icons.add_circle_rounded,
                  color: context.kayleoPrimary,
                  size: 26,
                ),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.kayleoSurfaces.soft,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TextField(
                    controller: text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: context.l10n.translate(
                        widget.isGroup
                            ? 'Message #${widget.room}…'
                            : 'Message…',
                      ),
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: context.kayleoMuted,
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: text,
                builder: (context, val, _) {
                  final canSend =
                      val.text.trim().isNotEmpty || attachment != null;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: canSend
                          ? context.kayleoPrimary
                          : context.kayleoSurfaces.soft,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      // Keep the control callable while empty and let _send's
                      // guard no-op. This avoids a stale disabled button during
                      // the frame in which keyboard input updates the field.
                      onPressed: sending ? null : _send,
                      tooltip: context.l10n.translate('Send message'),
                      iconSize: 18,
                      color: canSend ? Colors.white : context.kayleoMuted,
                      icon: sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget _dateHeader(DateTime date) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;

    final String text = isToday
        ? 'Today'
        : isYesterday
        ? 'Yesterday'
        : DateFormat('EEEE, MMM d').format(date);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: context.kayleoSurfaces.soft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LocalizedText(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.kayleoMuted,
          ),
        ),
      ),
    );
  }

  Widget _draftBar(String title, VoidCallback clear) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: context.kayleoSurfaces.soft,
      border: Border(top: BorderSide(color: context.kayleoSurfaces.border)),
    ),
    child: Row(
      children: [
        Icon(Icons.reply_rounded, size: 16, color: context.kayleoPrimary),
        const SizedBox(width: 8),
        Expanded(
          child: LocalizedText(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: context.l10n.translate('Cancel'),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: clear,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  );

  Widget _message(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> byId,
  ) {
    final data = doc.data();
    final own = data['authorId'] == widget.service.uid;
    final name = data['authorName'] as String;
    final photo = data['authorPhoto'] as String?;
    final stamp = data['createdAt'] as Timestamp?;
    final card = data['attachment'] as Map?;
    final parent = data['replyTo'] as String?;
    final body = (data['body'] as String?)?.trim() ?? '';
    final timeStr = stamp == null
        ? (doc.metadata.hasPendingWrites ? 'Sending…' : 'Syncing…')
        : DateFormat('h:mm a').format(stamp.toDate().toLocal());

    final bubbleBg = own ? context.kayleoPrimary : context.kayleoSurfaces.card;
    final bubbleTextColor = own ? Colors.white : context.kayleoText;
    final metaColor = own
        ? Colors.white.withValues(alpha: .75)
        : context.kayleoMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: own
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!own) ...[
            SocialAvatar(name, radius: 13, photoBase64: photo),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.76,
              ),
              child: Column(
                crossAxisAlignment: own
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!own && widget.isGroup)
                    Padding(
                      padding: const EdgeInsets.only(left: 3, bottom: 2),
                      child: LocalizedText(
                        name,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: context.kayleoMuted,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(own ? 16 : 4),
                        bottomRight: Radius.circular(own ? 4 : 16),
                      ),
                      border: own
                          ? null
                          : Border.all(
                              color: context.kayleoSurfaces.border.withValues(
                                alpha: .5,
                              ),
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: own ? .08 : .04,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: own
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (parent != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: own
                                  ? Colors.black.withValues(alpha: .15)
                                  : context.kayleoSurfaces.soft,
                              borderRadius: BorderRadius.circular(10),
                              border: Border(
                                left: BorderSide(
                                  color: own
                                      ? Colors.white
                                      : context.kayleoPrimary,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: LocalizedText(
                              byId[parent] == null
                                  ? 'Reply to an earlier message'
                                  : '${byId[parent]!.data()['authorName']}: ${byId[parent]!.data()['body']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: own
                                    ? Colors.white.withValues(alpha: .85)
                                    : context.kayleoMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        if (body.isNotEmpty)
                          SelectableText(
                            body,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.28,
                              color: bubbleTextColor,
                            ),
                          ),
                        if (card != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: own
                                  ? Colors.white.withValues(alpha: .15)
                                  : context.kayleoSurfaces.soft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.restaurant_outlined,
                                      size: 15,
                                      color: own
                                          ? Colors.white
                                          : context.kayleoPrimary,
                                    ),
                                    const SizedBox(width: 6),
                                    LocalizedText(
                                      'SHARED MEAL',
                                      style: TextStyle(
                                        fontSize: 9,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w800,
                                        color: own
                                            ? Colors.white
                                            : context.kayleoPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                LocalizedText(
                                  card['title'] as String,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: bubbleTextColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                LocalizedText(
                                  '${card['calories']} kcal · P ${card['protein']}g · C ${card['carbs']}g · F ${card['fat']}g',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: metaColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            LocalizedText(
                              timeStr,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                                color: metaColor,
                              ),
                            ),
                            if (own) ...[
                              const SizedBox(width: 4),
                              Icon(
                                doc.metadata.hasPendingWrites
                                    ? Icons.access_time_rounded
                                    : Icons.done_all_rounded,
                                size: 12,
                                color: metaColor,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MessageCheers(
                        key: ValueKey(doc.id),
                        service: widget.service,
                        room: widget.room,
                        message: doc.id,
                        group: widget.isGroup,
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          minimumSize: const Size(40, 28),
                        ),
                        onPressed: () => setState(() {
                          replyId = doc.id;
                          replyName = name;
                        }),
                        icon: Icon(
                          Icons.reply_rounded,
                          size: 15,
                          color: context.kayleoMuted,
                        ),
                        label: LocalizedText(
                          'Reply',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.kayleoMuted,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: context.l10n.translate('Message options'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 28,
                        ),
                        splashRadius: 16,
                        iconSize: 15,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: context.kayleoMuted,
                        ),
                        onSelected: (value) async {
                          if (value == 'delete') {
                            if (await socialConfirm(
                                  context,
                                  'Delete your message?',
                                  'This removes the message for everyone in this conversation.',
                                  'Delete',
                                ) &&
                                mounted) {
                              await socialAction(
                                context,
                                () => widget.service.deleteMessage(
                                  widget.room,
                                  doc.id,
                                  group: widget.isGroup,
                                ),
                              );
                            }
                          } else if (value == 'report') {
                            final ok = await socialAction(
                              context,
                              () => widget.service.report(
                                widget.room,
                                doc.id,
                                group: widget.isGroup,
                              ),
                              success: 'Report submitted. This message is hidden for this visit.',
                            );
                            if (ok && mounted) {
                              setState(() => hidden.add(doc.id));
                            }
                          } else {
                            setState(() => hidden.add(doc.id));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'hide',
                            child: LocalizedText('Hide for this visit'),
                          ),
                          if (own)
                            const PopupMenuItem(
                              value: 'delete',
                              child: LocalizedText('Delete message'),
                            )
                          else
                            const PopupMenuItem(
                              value: 'report',
                              child: LocalizedText('Report message'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (own) ...[
            const SizedBox(width: 6),
            SocialAvatar(name, radius: 13, photoBase64: photo),
          ],
        ],
      ),
    );
  }

  Future<void> _loadOlder(
    QueryDocumentSnapshot<Map<String, dynamic>> cursor,
  ) async {
    setState(() => loadingOlder = true);
    await socialAction(context, () async {
      final page = await widget.service
          .messages(widget.room, group: widget.isGroup)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(cursor)
          .limit(100)
          .get();
      if (mounted) {
        setState(() {
          older.addAll(page.docs);
          hasOlder = page.docs.length == 100;
        });
      }
    });
    if (mounted) setState(() => loadingOlder = false);
  }

  Future<void> _send() async {
    if (text.text.trim().isEmpty && attachment == null) return;
    setState(() => sending = true);
    final body = text.text;
    final ok = await socialAction(
      context,
      () => widget.service.send(
        widget.room,
        body,
        group: widget.isGroup,
        attachment: attachment,
        replyTo: replyId,
      ),
    );
    if (mounted) {
      setState(() {
        sending = false;
        if (ok) {
          if (text.text == body) text.clear();
          attachment = null;
          replyId = null;
          replyName = null;
        }
      });
    }
    if (mounted && ok && scroll.hasClients) {
      scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _share() async {
    final meals = [
      ...widget.state.meals.reversed.take(20),
      ...widget.state.templates.take(20),
    ];
    final selected = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: LocalizedText(
                'Share a little of your day',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const LocalizedText('Daily check-in'),
              subtitle: const LocalizedText(
                'A moment to reflect and encourage',
              ),
              onTap: () => Navigator.pop(context, 'check-in'),
            ),
            Expanded(
              child: meals.isEmpty
                  ? const SocialEmpty(
                      Icons.restaurant_outlined,
                      'Your meals will appear here',
                      'Log or save a meal to share its nutrition card.',
                    )
                  : ListView(
                      children: [
                        for (final meal in meals)
                          ListTile(
                            leading: const Icon(Icons.restaurant_outlined),
                            title: LocalizedText(meal.name),
                            subtitle: LocalizedText(
                              '${mealNutrition(meal).calories.round()} kcal · share a nutrition card',
                            ),
                            onTap: () => Navigator.pop(context, meal),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'check-in') {
      text.text = 'Today’s little win: \nOne thing I’m working on: \nA little encouragement for the circle: ';
      return;
    }
    final meal = selected as Meal;
    final nutrition = mealNutrition(meal);
    setState(
      () => attachment = {
        'title': meal.name.substring(0, meal.name.length.clamp(0, 120)),
        'calories': nutrition.calories.round(),
        'protein': nutrition.protein.round(),
        'carbs': nutrition.carbs.round(),
        'fat': nutrition.fat.round(),
      },
    );
  }
}

class _MessageCheers extends StatefulWidget {
  const _MessageCheers({
    super.key,
    required this.service,
    required this.room,
    required this.message,
    required this.group,
  });
  final CommunityService service;
  final String room, message;
  final bool group;
  @override
  State<_MessageCheers> createState() => _MessageCheersState();
}

class _MessageCheersState extends State<_MessageCheers> {
  late final stream = widget.service.cheers(
    widget.room,
    widget.message,
    group: widget.group,
  );
  bool busy = false;
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      final docs = snapshot.data?.docs ?? [];
      final active = docs.any((doc) => doc.id == widget.service.uid);
      final count = docs.length;

      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy || snapshot.hasError
            ? null
            : () async {
                setState(() => busy = true);
                await socialAction(
                  context,
                  () => widget.service.cheer(
                    widget.room,
                    widget.message,
                    group: widget.group,
                    active: active,
                  ),
                );
                if (mounted) setState(() => busy = false);
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 28),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: active
                ? KayleoColors.protein.withValues(alpha: .12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 14,
                color: active ? KayleoColors.protein : context.kayleoMuted,
              ),
              const SizedBox(width: 4),
              LocalizedText(
                count == 0 ? 'Cheer' : '$count${count >= 100 ? '+' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active ? KayleoColors.protein : context.kayleoMuted,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
