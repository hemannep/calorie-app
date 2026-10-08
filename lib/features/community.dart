import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../data/models.dart';

const _groups = [
  (
    'regional',
    'A taste of home',
    'Momo, dal bhat, and everyday regional favorites.',
    Icons.ramen_dining_rounded,
  ),
  (
    'protein',
    'Protein, with care',
    'Simple recipes and satisfying everyday meals.',
    Icons.restaurant_outlined,
  ),
  (
    'walking',
    'Daily movement',
    'Walks, fresh air, and celebrating showing up.',
    Icons.directions_walk_rounded,
  ),
];
const _samplePosts = <Map<String, dynamic>>[
  {
    'id': 'sample-1',
    'author': 'Maya',
    'group': 'A taste of home',
    'title': 'My usual dal bhat, with more greens.',
    'body': 'An extra scoop of dal, seasonal greens, and all the flavors I grew up with. Good food doesn’t have to be complicated.',
    'image': 'salad',
    'likes': 24,
  },
  {
    'id': 'sample-2',
    'author': 'Sam',
    'group': 'Protein, with care',
    'title': 'The lunch bowl I keep coming back to.',
    'body': 'Grilled chicken, crunchy vegetables, and lemon dressing. Saved it as a usual so tomorrow’s lunch takes one tap to log.',
    'image': 'bowl',
    'likes': 18,
  },
  {
    'id': 'sample-3',
    'author': 'Riya',
    'group': 'Daily movement',
    'title': 'Ten minutes outside made my afternoon.',
    'body': 'A walk after lunch gave me a welcome break. Fresh air was enough for today.',
    'image': '',
    'likes': 31,
  },
];

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, required this.state});
  final AppState state;
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  bool myGroups = false;
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final posts = [
      ...state.communityPosts.reversed,
      ..._samplePosts,
    ].where((p) => !state.hiddenPosts.contains(p['id'])).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageTitle(
          'Good things, shared',
          'Better, together.',
          'Recipes and familiar foods in a local community preview.',
          trailing: Tag(
            'LOCAL COMMUNITY PREVIEW',
            icon: Icons.people_outline_rounded,
          ),
        ),
        if (!state.community)
          Panel(
            color: forest,
            border: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBox(
                  Icons.people_outline_rounded,
                  color: KayleoColors.forest,
                  foreground: lime,
                  size: 54,
                ),
                const SizedBox(height: KayleoSpacing.xl),
                Text(
                  'Find your people.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Explore a preview of communities built around habits and the food you love. Your diary, weight, and calorie targets stay private.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .7),
                    fontSize: 13,
                    height: 1.9,
                  ),
                ),
                const SizedBox(height: KayleoSpacing.xl),
                FilledButton.icon(
                  onPressed: () {
                    state.community = true;
                    state.persist();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: lime,
                    foregroundColor: forest,
                  ),
                  icon: Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text('Explore preview'),
                ),
                const SizedBox(height: 18),
                Text(
                  'Sample people and posts. Interactions stay on this device.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(
                        'Discover',
                        style: TextStyle(
                          fontSize: 12,
                          color: !myGroups ? forest : context.kayleoText,
                        ),
                      ),
                      selected: !myGroups,
                      selectedColor: lime,
                      checkmarkColor: forest,
                      onSelected: (_) => setState(() => myGroups = false),
                    ),
                    ChoiceChip(
                      label: Text(
                        'My groups',
                        style: TextStyle(
                          fontSize: 12,
                          color: myGroups ? forest : context.kayleoText,
                        ),
                      ),
                      selected: myGroups,
                      selectedColor: lime,
                      checkmarkColor: forest,
                      onSelected: (_) => setState(() => myGroups = true),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => shareMeal(context),
                tooltip: 'Share a meal in the local preview',
                icon: Icon(Icons.add_rounded, color: context.kayleoPrimary),
              ),
            ],
          ),
          const SizedBox(height: KayleoSpacing.card),
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final group in _groups)
                  if (!myGroups || state.joined.contains(group.$1))
                    SizedBox(
                      width: c.maxWidth > 850
                          ? (c.maxWidth - 32) / 3
                          : c.maxWidth,
                      child: Panel(
                        padding: 20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconBox(group.$4, size: 42),
                            const SizedBox(height: KayleoSpacing.page),
                            Text(
                              group.$2,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: KayleoSpacing.sm),
                            Text(
                              group.$3,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.kayleoMuted,
                                height: 1.8,
                              ),
                            ),
                            const SizedBox(height: KayleoSpacing.page),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () {
                                  if (state.joined.contains(group.$1)) {
                                    state.joined.remove(group.$1);
                                  } else {
                                    state.joined.add(group.$1);
                                  }
                                  state.persist();
                                },
                                child: Text(
                                  state.joined.contains(group.$1)
                                      ? 'Joined · tap to leave'
                                      : 'Join preview group',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          if (myGroups && !_groups.any((g) => state.joined.contains(g.$1)))
            EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'Find your people',
              subtitle: 'Join a preview group from Discover to see it here.',
            ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, c) {
              final feed = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    myGroups ? 'From your groups' : 'Meal inspiration',
                    action: 'Share a meal',
                    onAction: () => shareMeal(context),
                  ),
                  for (final post in posts)
                    if (!myGroups ||
                        _groups.any(
                          (g) =>
                              state.joined.contains(g.$1) &&
                              g.$2 == post['group'],
                        )) ...[
                      _post(post),
                      const SizedBox(height: KayleoSpacing.page),
                    ],
                ],
              );
              final challenge = Panel(
                color: context.kayleoSurfaces.soft,
                border: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBox(Icons.wb_sunny_outlined, color: lime, size: 45),
                    const SizedBox(height: 18),
                    Tag('A GENTLE CHALLENGE', color: Colors.white),
                    const SizedBox(height: KayleoSpacing.lg),
                    Text(
                      '7 days of\nshowing up.',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.7,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: KayleoSpacing.md),
                    Text(
                      'Log one meal each day and build a steady habit at your pace.',
                      style: TextStyle(
                        color: context.kayleoMuted,
                        fontSize: 12,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: KayleoSpacing.card),
                    if (state.joined.contains('challenge')) ...[
                      LinearProgressIndicator(
                        value: _challengeDays(state) / 7,
                        color: context.kayleoPrimary,
                        backgroundColor: context.kayleoSurfaces.card,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      const SizedBox(height: KayleoSpacing.md),
                      Text(
                        '${_challengeDays(state)} / 7 days logged this week',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.kayleoPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: KayleoSpacing.lg),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (state.joined.contains('challenge')) {
                            state.joined.remove('challenge');
                          } else {
                            state.joined.add('challenge');
                          }
                          state.persist();
                        },
                        child: Text(
                          state.joined.contains('challenge')
                              ? 'Leave challenge'
                              : 'Join the challenge',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              );
              return c.maxWidth > 850
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: feed),
                        const SizedBox(width: KayleoSpacing.xl),
                        Expanded(flex: 4, child: challenge),
                      ],
                    )
                  : Column(
                      children: [
                        challenge,
                        const SizedBox(height: KayleoSpacing.xl),
                        feed,
                      ],
                    );
            },
          ),
          const SizedBox(height: KayleoSpacing.lg),
          TextButton(
            onPressed: () {
              state.community = false;
              state.persist();
            },
            child: Text(
              'Leave community preview',
              style: TextStyle(color: context.kayleoMuted, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  int _challengeDays(AppState state) => List.generate(
    7,
    (i) => DateTime.now().subtract(Duration(days: i)),
  ).where((d) => state.mealsFor(d).isNotEmpty).length;
  Widget _post(Map<String, dynamic> post) {
    final state = widget.state;
    final id = post['id'] as String;
    final author = post['author'] as String;
    return Panel(
      padding: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: context.kayleoSurfaces.soft,
                child: Text(
                  author.isEmpty ? 'K' : author.characters.first,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.kayleoPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      post['group'],
                      style: TextStyle(
                        fontSize: 12,
                        color: context.kayleoMuted,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Post options',
                onSelected: (v) async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        v == 'report'
                            ? 'Hide and flag this sample post?'
                            : 'Hide this post?',
                      ),
                      content: Text(
                        v == 'report'
                            ? 'It will be hidden locally. No report is sent to a moderator in this preview.'
                            : 'You won’t see this post in the local preview.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('Hide'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    state.hiddenPosts.add(id);
                    await state.persist();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'hide', child: Text('Hide post')),
                  PopupMenuItem(value: 'report', child: Text('Report preview')),
                ],
              ),
            ],
          ),
          const SizedBox(height: KayleoSpacing.md),
          Tag(id.startsWith('sample') ? 'SAMPLE POST' : 'ON THIS DEVICE'),
          const SizedBox(height: KayleoSpacing.page),
          Text(
            post['title'],
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            post['body'],
            style: TextStyle(
              fontSize: 12,
              color: context.kayleoMuted,
              height: 1.8,
            ),
          ),
          if ((post['image'] as String).isNotEmpty) ...[
            const SizedBox(height: 18),
            FoodPhoto(
              image: post['image'],
              height: 220,
              width: double.infinity,
            ),
          ],
          const SizedBox(height: KayleoSpacing.lg),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () {
                  if (state.liked.contains(id)) {
                    state.liked.remove(id);
                  } else {
                    state.liked.add(id);
                  }
                  state.persist();
                },
                icon: Icon(
                  state.liked.contains(id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 17,
                  color: state.liked.contains(id)
                      ? orange
                      : context.kayleoPrimary,
                ),
                label: Text(
                  '${(post['likes'] as int) + (state.liked.contains(id) ? 1 : 0)} cheers',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () =>
                    openSheet(context, CommentsSheet(state: state, postId: id)),
                icon: Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: Text(
                  '${state.comments[id]?.length ?? 0} comments',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> shareMeal(BuildContext context) async {
    if (widget.state.templates.isEmpty) {
      toast(context, 'Save a meal as a usual first, then share it here.');
      return;
    }
    var selected = widget.state.templates.first;
    final note = TextEditingController();
    final ok = await showManagedDialog<bool>(
      controllers: [note],
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Share a meal'),
        scrollable: true,
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Saved meal'),
                items: widget.state.templates
                    .map(
                      (m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          m.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => selected = widget.state.templates.firstWhere(
                  (m) => m.id == v,
                ),
              ),
              const SizedBox(height: KayleoSpacing.lg),
              TextField(
                controller: note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'What makes it a favorite?',
                ),
              ),
              const SizedBox(height: KayleoSpacing.md),
              Text(
                'Your post is stored on this device only. No weight, calorie targets, or uploaded photos are included.',
                style: TextStyle(fontSize: 12, color: context.kayleoMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Save preview post'),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.state.communityPosts.add({
        'id': newId(),
        'author': widget.state.profile.name,
        'group': 'A taste of home',
        'title': selected.name,
        'body': note.text.trim().isEmpty
            ? 'One of my familiar favorites.'
            : note.text.trim(),
        'image': selected.image,
        'likes': 0,
      });
      await widget.state.persist();
    }
  }
}

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.state, required this.postId});
  final AppState state;
  final String postId;
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => SheetFrame(
      title: 'Comments',
      subtitle: 'Preview comments stay on this device.',
      footer: Row(
        children: [
          Expanded(
            child: TextField(
              controller: input,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'A kind word or a recipe idea…',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: KayleoSpacing.md),
          IconButton.filled(
            onPressed: () async {
              if (input.text.trim().isEmpty) {
                return;
              }
              widget.state.comments
                  .putIfAbsent(widget.postId, () => [])
                  .add(input.text.trim());
              input.clear();
              await widget.state.persist();
            },
            tooltip: 'Save comment locally',
            icon: Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
      child: Column(
        children: [
          if ((widget.state.comments[widget.postId] ?? []).isEmpty)
            EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Start with a kind word',
              subtitle: 'Share encouragement or a recipe idea.',
            ),
          for (final comment
              in widget.state.comments[widget.postId] ?? <String>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Panel(
                padding: 16,
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.state.profile.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(comment, style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
