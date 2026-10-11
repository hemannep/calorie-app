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
          title: Text(widget.group.name),
          actions: [
            if (joined)
              PopupMenuButton<String>(
                tooltip: 'Circle options',
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
                    child: Text('Leave circle'),
                  ),
                ],
              ),
          ],
          bottom: joined
              ? TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Chat'),
                    Tab(text: 'Streaks'),
                    Tab(text: 'Challenge'),
                  ],
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
                    const Text(
                      'Consistency deserves\na little celebration.',
                      style: TextStyle(
                        fontSize: 24,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
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
                        child: Text(
                          'Your current streak',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${widget.state.streak} days',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
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
              Text(
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
            child: Text(
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
            child: Text(
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
          Text('$streak', style: const TextStyle(fontWeight: FontWeight.w800)),
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
                const Text(
                  'THE SHOW-UP CLUB',
                  style: TextStyle(
                    color: lime,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
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
                const Text(
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
                Text(
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
              title: Text(DateFormat('EEEE').format(day)),
              trailing: Text(
                day.isAfter(today)
                    ? 'Coming up'
                    : state.mealsFor(day).isEmpty
                    ? 'A fresh opportunity'
                    : 'You showed up',
                style: TextStyle(fontSize: 11, color: context.kayleoMuted),
              ),
            ),
          const SizedBox(height: 14),
          const Text(
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: context.kayleoSurfaces.soft,
        child: Text(
          widget.isGroup
              ? 'Be kind. Share ideas, meals, and little wins. Your private diary stays yours.'
              : 'Just the two of you. Choose what to share in Friends → sharing controls.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: context.kayleoMuted,
          ),
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
                    child: Text(
                      'Showing cached messages · reconnect to sync',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount:
                        docs.length + (hasOlder && live.length >= 100 ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == docs.length) {
                        return TextButton(
                          onPressed: loadingOlder
                              ? null
                              : () => _loadOlder(docs.last),
                          child: Text(
                            loadingOlder ? 'Loading…' : 'Load earlier messages',
                          ),
                        );
                      }
                      return KeyedSubtree(
                        key: ValueKey(docs[index].id),
                        child: _message(docs[index], byId),
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
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          decoration: BoxDecoration(
            color: context.kayleoSurfaces.card,
            border: Border(
              top: BorderSide(color: context.kayleoSurfaces.border),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: sending ? null : _share,
                tooltip: 'Share a meal or daily check-in',
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Say something kind…',
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: sending ? null : _send,
                tooltip: 'Send message',
                icon: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget _draftBar(String title, VoidCallback clear) => Container(
    color: context.kayleoSurfaces.soft,
    padding: const EdgeInsets.only(left: 20),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: 'Remove attachment or reply',
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
    final stamp = data['createdAt'] as Timestamp?;
    final card = data['attachment'] as Map?;
    final parent = data['replyTo'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        padding: 16,
        color: own ? context.kayleoSurfaces.soft : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SocialAvatar(name, radius: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        own ? '$name · you' : name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        doc.metadata.hasPendingWrites
                            ? 'Sending…'
                            : stamp == null
                            ? 'Syncing…'
                            : DateFormat('MMM d, h:mm a')
                                  .format(stamp.toDate().toLocal()),
                        style: TextStyle(
                          color: context.kayleoMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Message options',
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
                      if (ok && mounted) setState(() => hidden.add(doc.id));
                    } else {
                      setState(() => hidden.add(doc.id));
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'hide',
                      child: Text('Hide for this visit'),
                    ),
                    if (own)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete message'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'report',
                        child: Text('Report message'),
                      ),
                  ],
                ),
              ],
            ),
            if (parent != null)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.kayleoPrimary, width: 3),
                  ),
                ),
                child: Text(
                  byId[parent] == null
                      ? 'Reply to an earlier message'
                      : '${byId[parent]!.data()['authorName']}: ${byId[parent]!.data()['body']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.kayleoMuted, fontSize: 11),
                ),
              ),
            if ((data['body'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  data['body'] as String,
                  style: const TextStyle(fontSize: 13, height: 1.7),
                ),
              ),
            if (card != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.kayleoBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.restaurant_outlined,
                          size: 18,
                          color: context.kayleoPrimary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SHARED MEAL',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      card['title'] as String,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${card['calories']} kcal · P ${card['protein']}g · C ${card['carbs']}g · F ${card['fat']}g',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.kayleoMuted,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() {
                    replyId = doc.id;
                    replyName = name;
                  }),
                  icon: const Icon(Icons.reply_rounded, size: 16),
                  label: const Text('Reply', style: TextStyle(fontSize: 11)),
                ),
                _MessageCheers(
                  key: ValueKey(doc.id),
                  service: widget.service,
                  room: widget.room,
                  message: doc.id,
                  group: widget.isGroup,
                ),
              ],
            ),
          ],
        ),
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
              child: Text(
                'Share a little of your day',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Daily check-in'),
              subtitle: const Text('A moment to reflect and encourage'),
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
                            title: Text(meal.name),
                            subtitle: Text(
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
      return TextButton.icon(
        onPressed: busy || snapshot.hasError
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
        icon: Icon(
          active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 16,
          color: active ? KayleoColors.protein : null,
        ),
        label: Text(
          '${docs.isEmpty ? '' : '${docs.length}${docs.length == 100 ? '+' : ''} '}Cheer',
          style: const TextStyle(fontSize: 11),
        ),
      );
    },
  );
}
