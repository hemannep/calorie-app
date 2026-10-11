import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../data/community_models.dart';
import '../services/community_service.dart';
import 'community_friends.dart';
import 'community_room.dart';
import 'community_widgets.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, required this.state, this.service});
  final AppState state;
  final CommunityService? service;
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  CommunityService get service => widget.service ?? CommunityService.instance;
  String tab = 'Discover', category = 'All', search = '';
  final Set<String> _busy = {};
  Future<List<CommunityGroup>>? _customGroups;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final groups = communityGroups
          .where(
            (g) =>
                (tab == 'Discover'
                    ? !service.joined.contains(g.id)
                    : service.joined.contains(g.id)) &&
                (category == 'All' || g.category == category) &&
                ('${g.name} ${g.description}'.toLowerCase().contains(
                  search.toLowerCase(),
                )),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR PEOPLE. YOUR PACE.',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                        color: context.kayleoMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Better, together.',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ],
                ),
              ),
              IconBox(Icons.people_alt_outlined, size: 48),
            ],
          ),
          const SizedBox(height: 18),
          if (!service.available)
            Panel(
              padding: 16,
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Browse the circles below. Sign in with a real account and use your own diary to join, chat, and connect with friends. Sample diaries stay private.',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          if (service.available && !service.ready && service.error == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: LinearProgressIndicator(),
            ),
          if (service.error != null)
            SocialSyncError(message: service.error, retry: service.retry),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
              for (final name in ['Discover', 'My circles', 'Friends'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(
                      name == 'Discover'
                          ? Icons.explore_outlined
                          : name == 'My circles'
                          ? Icons.groups_2_outlined
                          : Icons.people_outline_rounded,
                      size: 16,
                    ),
                    label: Text(
                      name == 'My circles' && service.joined.isNotEmpty
                          ? '$name · ${service.joined.length}'
                          : name,
                    ),
                    selected: tab == name,
                    onSelected: (_) => setState(() {
                      tab = name;
                      category = 'All';
                      search = '';
                      if (name == 'My circles') {
                        _customGroups = service.customGroups();
                      }
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (tab == 'Friends')
            FriendsPanel(state: widget.state, service: service)
          else ...[
            if (tab == 'My circles') ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: service.ready ? _createCommunity : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Create community'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: service.ready ? _joinPrivateCommunity : null,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                      label: const Text('Join private'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final value in [
                    'All',
                    'Goals',
                    'Food styles',
                    'Movement',
                    'Habits',
                    'Calorie circles',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          value,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: category == value,
                        onSelected: (_) => setState(() => category = value),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey(tab),
              onChanged: (value) => setState(() => search = value),
              decoration: const InputDecoration(
                hintText: 'Find a community',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tab == 'My circles' ? 'Your circles' : 'Find your people',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${groups.length} circles',
                  style: TextStyle(fontSize: 12, color: context.kayleoMuted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (groups.isEmpty)
              if (tab != 'My circles')
                const SocialEmpty(
                  Icons.search_off_rounded,
                  'You found them all',
                  'Every matching circle is already in My circles.',
                ),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 3
                    : constraints.maxWidth >= 650
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 14) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final group in groups)
                      SizedBox(width: width, child: _group(group)),
                  ],
                );
              },
            ),
            if (tab == 'My circles')
              FutureBuilder<List<CommunityGroup>>(
                future: _customGroups ??= service.customGroups(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return SocialSyncError(
                      message: socialError(snapshot.error!),
                      retry: () => setState(
                        () => _customGroups = service.customGroups(),
                      ),
                    );
                  }
                  final custom = snapshot.data ?? const [];
                  if (groups.isEmpty && custom.isEmpty) {
                    return const SocialEmpty(
                      Icons.groups_2_outlined,
                      'Your first circle starts here',
                      'Join a public circle or create a private community for your people.',
                    );
                  }
                  return Column(
                    children: [
                      for (final group in custom) ...[
                        const SizedBox(height: 12),
                        _group(group),
                      ],
                    ],
                  );
                },
              ),
            const SizedBox(height: 20),
            Text(
              'Circles are for support and meal inspiration. Calorie circles don’t change your personal targets. Your diary stays private unless you choose to share.',
              style: TextStyle(
                color: context.kayleoMuted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ],
        ],
      );
    },
  );

  Widget _group(CommunityGroup group) {
    final joined = service.joined.contains(group.id);
    final busy = _busy.contains(group.id);
    return Panel(
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: group.color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(group.icon, color: group.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      group.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.kayleoMuted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                group.category.toUpperCase(),
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w800,
                  color: context.kayleoMuted,
                ),
              ),
              const Spacer(),
              if (joined)
                FilledButton.icon(
                  onPressed: () => _open(group),
                  icon: const Icon(Icons.forum_outlined, size: 14),
                  label: const Text('Open'),
                )
              else
                OutlinedButton.icon(
                  onPressed: !service.ready || busy
                      ? null
                      : () async {
                          setState(() => _busy.add(group.id));
                          final success = await socialAction(
                            context,
                            () => service.join(group),
                          );
                          if (mounted) {
                            setState(() => _busy.remove(group.id));
                            if (success) {
                              setState(() {});
                            }
                          }
                        },
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, size: 16),
                  label: Text(busy ? 'Joining…' : 'Join'),
                ),
              if (group.isCustom) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => CommunityInviteDialog(group: group),
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 14),
                  label: const Text('Invite'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _createCommunity() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create a private community'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Only people with your code or QR can join.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Community name'),
            ),
            TextField(
              controller: description,
              maxLength: 180,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'What is this community for?',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (create != true || !mounted) {
      name.dispose();
      description.dispose();
      return;
    }
    CommunityGroup? group;
    await socialAction(context, () async {
      group = await service.createCommunity(name.text, description.text);
    }, success: 'Your private community is ready');
    name.dispose();
    description.dispose();
    if (!mounted || group == null) return;
    setState(() => _customGroups = service.customGroups());
    await showDialog<void>(
      context: context,
      builder: (_) => CommunityInviteDialog(group: group!),
    );
  }

  Future<void> _joinPrivateCommunity() async {
    final group = await showDialog<CommunityGroup>(
      context: context,
      builder: (_) => CommunityJoinDialog(service: service),
    );
    if (!mounted || group == null) return;
    setState(() => _customGroups = service.customGroups());
    _open(group);
  }

  void _open(CommunityGroup group) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CommunityRoomScreen(
        state: widget.state,
        service: service,
        group: group,
      ),
    ),
  );
}
