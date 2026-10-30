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
  static const _tabs = ['Discover', 'My circles', 'Friends'];
  CommunityService get service => widget.service ?? CommunityService.instance;
  String tab = 'Discover', category = 'All', search = '';
  late final PageController _pageController = PageController();
  final Set<String> _busy = {};
  Future<List<CommunityGroup>>? _customGroups;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      'YOUR PEOPLE. YOUR PACE.',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                        color: context.kayleoMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const LocalizedText(
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
                    child: LocalizedText(
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
          _CommunitySectionNav(
            selected: tab,
            joinedCount: service.joined.length,
            controller: _pageController,
            onSelected: _selectTab,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: (MediaQuery.sizeOf(context).height - 280).clamp(
              420.0,
              760.0,
            ),
            child: PageView(
              controller: _pageController,
              physics: const _FastPageScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              onPageChanged: _pageChanged,
              children: [
                _circlePage('Discover'),
                _circlePage('My circles'),
                SingleChildScrollView(
                  key: const PageStorageKey('community-friends'),
                  child: FriendsPanel(state: widget.state, service: service),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _circlePage(String section) {
    final groups = communityGroups
        .where(
          (group) =>
              (section == 'Discover'
                  ? !service.joined.contains(group.id)
                  : service.joined.contains(group.id)) &&
              (category == 'All' || group.category == category) &&
              '${group.name} ${group.description}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return SingleChildScrollView(
      key: PageStorageKey('community-$section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: ValueKey('search-$section'),
            onChanged: (value) => setState(() => search = value),
            decoration: InputDecoration(
              hintText: context.l10n.translate('Find a community'),
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
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
                      label: LocalizedText(
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
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: LocalizedText(
                  section == 'My circles' ? 'Your circles' : 'Find your people',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              LocalizedText(
                '${groups.length} circles',
                style: TextStyle(fontSize: 12, color: context.kayleoMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (groups.isEmpty && section == 'Discover')
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
          if (section == 'My circles')
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
                    retry: () =>
                        setState(() => _customGroups = service.customGroups()),
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
          if (section == 'My circles') ...[
            const SizedBox(height: 20),
            _privateCircleActions(),
          ],
          const SizedBox(height: 20),
          LocalizedText(
            'Circles are for support and meal inspiration. Calorie circles don’t change your personal targets. Your diary stays private unless you choose to share.',
            style: TextStyle(
              color: context.kayleoMuted,
              fontSize: 12,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _pageChanged(int index) {
    final name = _tabs[index];
    if (name == tab) return;
    setState(() {
      tab = name;
      if (name == 'My circles') _customGroups ??= service.customGroups();
    });
  }

  void _selectTab(String name) {
    if (tab == name) return;
    final next = _tabs.indexOf(name);
    setState(() {
      tab = name;
      if (name == 'My circles') _customGroups ??= service.customGroups();
    });
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutQuart,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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
                    LocalizedText(
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
                    LocalizedText(
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
          const SizedBox(height: 14),
          _groupFooter(group, joined: joined, busy: busy),
        ],
      ),
    );
  }

  Widget _groupFooter(
    CommunityGroup group, {
    required bool joined,
    required bool busy,
  }) {
    final category = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: context.kayleoSurfaces.soft,
        borderRadius: BorderRadius.circular(9),
      ),
      child: LocalizedText(
        group.category.toUpperCase(),
        style: TextStyle(
          fontSize: 8,
          letterSpacing: .75,
          fontWeight: FontWeight.w800,
          color: context.kayleoMuted,
        ),
      ),
    );
    final primary = _GroupAction(
      filled: joined,
      busy: busy,
      icon: joined ? Icons.arrow_forward_rounded : Icons.add_rounded,
      label: joined ? 'Open circle' : 'Join circle',
      onPressed: joined
          ? () => _open(group)
          : !service.ready || busy
          ? null
          : () => _join(group),
    );
    final invite = group.isCustom
        ? IconButton.outlined(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CommunityInviteDialog(group: group),
            ),
            tooltip: context.l10n.translate('Invite to ${group.name}'),
            icon: const Icon(Icons.ios_share_rounded, size: 17),
          )
        : null;
    final stack =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: category),
          const SizedBox(height: 10),
          Row(
            children: [
              if (invite != null) ...[invite, const SizedBox(width: 8)],
              Expanded(child: primary),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        category,
        const Spacer(),
        if (invite != null) ...[invite, const SizedBox(width: 8)],
        primary,
      ],
    );
  }

  Future<void> _join(CommunityGroup group) async {
    setState(() => _busy.add(group.id));
    await socialAction(context, () => service.join(group));
    if (mounted) setState(() => _busy.remove(group.id));
  }

  Widget _privateCircleActions() => Panel(
    padding: 16,
    color: context.kayleoSurfaces.soft,
    border: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocalizedText(
          'Your own circle',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        LocalizedText(
          'Create a private space or join one with an invite.',
          style: TextStyle(
            color: context.kayleoMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final create = FilledButton.icon(
              onPressed: service.ready ? _createCommunity : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const LocalizedText('Create community'),
            );
            final join = OutlinedButton.icon(
              onPressed: service.ready ? _joinPrivateCommunity : null,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
              label: const LocalizedText('Join private'),
            );
            if (constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [create, const SizedBox(height: 8), join],
              );
            }
            return Row(
              children: [
                Expanded(child: create),
                const SizedBox(width: 10),
                Expanded(child: join),
              ],
            );
          },
        ),
      ],
    ),
  );

  Future<void> _createCommunity() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Create a private community'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LocalizedText(
              'Only people with your code or QR can join.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: context.l10n.translate('Community name'),
              ),
            ),
            TextField(
              controller: description,
              maxLength: 180,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.l10n.translate(
                  'What is this community for?',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LocalizedText('Create'),
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

class _FastPageScrollPhysics extends PageScrollPhysics {
  const _FastPageScrollPhysics({super.parent});

  @override
  _FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _FastPageScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: .5, stiffness: 220, damping: 22);
}

class _GroupAction extends StatelessWidget {
  const _GroupAction({
    required this.filled,
    required this.busy,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool filled;
  final bool busy;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final iconWidget = busy
        ? const SizedBox.square(
            dimension: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 16);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14),
      ),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    if (filled) {
      return FilledButton.icon(
        style: style,
        onPressed: onPressed,
        icon: iconWidget,
        label: LocalizedText(label),
      );
    }
    return OutlinedButton.icon(
      style: style,
      onPressed: onPressed,
      icon: iconWidget,
      label: LocalizedText(label),
    );
  }
}

class _CommunitySectionNav extends StatelessWidget {
  const _CommunitySectionNav({
    required this.selected,
    required this.joinedCount,
    required this.controller,
    required this.onSelected,
  });

  final String selected;
  final int joinedCount;
  final PageController controller;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Discover', Icons.explore_outlined),
      ('My circles', Icons.groups_2_outlined),
      ('Friends', Icons.people_outline_rounded),
    ];
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selectedIndex = items.indexWhere((item) => item.$1 == selected);
        final page = controller.hasClients
            ? controller.page ?? selectedIndex.toDouble()
            : selectedIndex.toDouble();
        return Container(
          width: double.infinity,
          height: 52,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: context.kayleoSurfaces.soft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.kayleoSurfaces.border),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment(-1.0 + page.clamp(0.0, 2.0), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / 3,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.kayleoSurfaces.card,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < items.length; index++)
                    Expanded(
                      child: Semantics(
                        selected: selected == items[index].$1,
                        button: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onSelected(items[index].$1),
                          child: Center(
                            child: _CommunityNavLabel(
                              icon: items[index].$2,
                              label: items[index].$1,
                              badgeCount:
                                  items[index].$1 == 'My circles' &&
                                      joinedCount > 0
                                  ? joinedCount
                                  : null,
                              emphasis: (1 - (page - index).abs()).clamp(0, 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CommunityNavLabel extends StatelessWidget {
  const _CommunityNavLabel({
    required this.icon,
    required this.label,
    required this.emphasis,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final double emphasis;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final isSelected = emphasis > 0.5;
    final activeTextColor = context.kayleoText;
    final inactiveTextColor = context.kayleoMuted;
    final textColor = Color.lerp(inactiveTextColor, activeTextColor, emphasis)!;

    final iconColor = Color.lerp(
      context.kayleoMuted,
      context.kayleoPrimary,
      emphasis,
    )!;
    final compact = MediaQuery.textScalerOf(context).scale(1) >= 1.5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!compact) ...[
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: LocalizedText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.2,
                color: textColor,
              ),
            ),
          ),
          if (!compact && badgeCount != null && badgeCount! > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Color.lerp(
                  context.kayleoSurfaces.border,
                  context.kayleoPrimary.withValues(alpha: .15),
                  emphasis,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: LocalizedText(
                '$badgeCount',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
