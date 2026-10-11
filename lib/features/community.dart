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
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final groups = communityGroups
          .where(
            (g) =>
                (tab != 'My circles' || service.joined.contains(g.id)) &&
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
          const SizedBox(height: 22),
          Panel(
            color: forest,
            border: false,
            padding: 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: lime.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: lime,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good habits grow with good company.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.25,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Share, support, and celebrate progress.',
                        style: TextStyle(
                          color: Colors.white70,
                          height: 1.45,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.people_alt_outlined,
                    color: Colors.white70,
                    size: 17,
                  ),
                ),
              ],
            ),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in ['Discover', 'My circles', 'Friends'])
                ChoiceChip(
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
                  }),
                ),
            ],
          ),
          const SizedBox(height: 22),
          if (tab == 'Friends')
            FriendsPanel(state: widget.state, service: service)
          else ...[
            TextField(
              key: ValueKey(tab),
              onChanged: (value) => setState(() => search = value),
              decoration: const InputDecoration(
                hintText: 'Find a community',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 20),
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
              SocialEmpty(
                Icons.search_off_rounded,
                tab == 'My circles'
                    ? 'Your circle starts here'
                    : 'No circles found',
                'Try another search or explore Discover to join a community.',
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
      padding: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: group.color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(group.icon, color: group.color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  group.category.toUpperCase(),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: context.kayleoMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            group.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.description,
            style: TextStyle(
              fontSize: 12,
              color: context.kayleoMuted,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: joined
                ? FilledButton.icon(
                    onPressed: () => _open(group),
                    icon: const Icon(Icons.forum_outlined, size: 16),
                    label: const Text('Open circle'),
                  )
                : OutlinedButton.icon(
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
                              if (success) _open(group);
                            }
                          },
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(busy ? 'Joining…' : 'Join circle'),
                  ),
          ),
        ],
      ),
    );
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
