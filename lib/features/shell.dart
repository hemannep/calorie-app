import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import 'dashboard.dart';
import 'diary.dart';
import 'logging.dart';
import 'progress.dart';
import 'settings.dart';
import 'community.dart';

const _nav = [
  ('Today', Icons.grid_view_rounded),
  ('Diary', Icons.menu_book_outlined),
  ('Scan food', Icons.camera_alt_outlined),
  ('Progress', Icons.show_chart_rounded),
  ('Saved meals', Icons.bookmark_border_rounded),
  ('Community', Icons.people_outline_rounded),
  ('You', Icons.tune_rounded),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});
  final AppState state;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selected = 0;
  final scroll = ScrollController();
  void navigate(int index) {
    setState(() => selected = index);
    if (scroll.hasClients) {
      scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final state = widget.state;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _sidebar(),
            Expanded(
              child: Column(
                children: [
                  if (wide || ![0, 1, 3, 6].contains(selected)) _topbar(wide),
                  if (state.storageError != null)
                    MaterialBanner(
                      content: Text(
                        state.storageError!,
                        style: const TextStyle(fontSize: 12),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => exportData(context, state),
                          child: const Text('Export backup'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: EdgeInsets.fromLTRB(
                        wide ? 40 : KayleoSpacing.page,
                        wide ? 34 : 18,
                        wide ? 40 : KayleoSpacing.page,
                        40,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: switch (selected) {
                            0 => DashboardScreen(
                              state: state,
                              navigate: navigate,
                              onReminders: () =>
                                  openSheet(context, InboxSheet(state: state)),
                            ),
                            1 => DiaryScreen(state: state),
                            2 => CaptureScreen(state: state),
                            3 => ProgressScreen(state: state),
                            4 => SavedMealsScreen(state: state),
                            5 => CommunityScreen(state: state),
                            _ => SettingsScreen(
                              state: state,
                              navigate: navigate,
                            ),
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: wide
          ? null
          : FloatingActionButton(
              key: const Key('bottom-camera-button'),
              tooltip: 'Scan food',
              backgroundColor: lime,
              foregroundColor: forest,
              elevation: 0,
              shape: CircleBorder(side: BorderSide(color:context.kayleoBackground,width:4)),
              onPressed: () =>
                  showLogger(context, widget.state, openCamera: true),
              child: const Icon(Icons.camera_alt_rounded, size: 28),
            ),
      bottomNavigationBar: wide ? null : _bottomBar(),
    );
  }

  Widget _bottomBar() {
    var labelHeight = 0.0;
    for (final label in ['Today', 'Diary', 'Progress', 'You']) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: MediaQuery.sizeOf(context).width / 5 - 8);
      if (painter.height > labelHeight) labelHeight = painter.height;
      painter.dispose();
    }
    final rowHeight = (47 + labelHeight).clamp(64.0, double.infinity);
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      padding: EdgeInsets.zero,
      color: context.kayleoSurfaces.card,
      height: rowHeight,
      child: Row(
        children: [
          _bottomItem(0, Icons.grid_view_rounded, 'Today'),
          _bottomItem(1, Icons.menu_book_outlined, 'Diary'),
          const Expanded(child: SizedBox()),
          _bottomItem(3, Icons.show_chart_rounded, 'Progress'),
          _bottomItem(6, Icons.person_outline_rounded, 'You'),
        ],
      ),
    );
  }

  Widget _bottomItem(int index, IconData icon, String label) => Expanded(
    child: InkWell(
      onTap: () => navigate(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected == index
                  ? context.kayleoPrimary
                  : context.kayleoMuted,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: selected == index
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: selected == index
                    ? context.kayleoPrimary
                    : context.kayleoMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _sidebar() => Container(
    width: 236,
    decoration: BoxDecoration(
      color: context.kayleoSurfaces.card,
      border: Border(right: BorderSide(color: context.kayleoSurfaces.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(30, 35, 30, 35),
          child: Brand(size: 32),
        ),
        Padding(
          padding: EdgeInsets.only(left: 30, bottom: 14),
          child: Text(
            'YOUR EVERYDAY',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: context.kayleoMuted,
              letterSpacing: 1.7,
            ),
          ),
        ),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: KayleoSpacing.xs,
            ),
            child: InkWell(
              onTap: () => navigate(i),
              borderRadius: BorderRadius.circular(KayleoRadius.small),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: selected == i
                      ? context.kayleoSurfaces.soft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(KayleoRadius.small),
                ),
                child: Row(
                  children: [
                    Icon(
                      _nav[i].$2,
                      size: 20,
                      color: selected == i
                          ? context.kayleoPrimary
                          : context.kayleoMuted,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nav[i].$1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected == i
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: selected == i
                                  ? context.kayleoPrimary
                                  : context.kayleoMuted,
                            ),
                          ),
                          if (i == 5)
                            Text(
                              'Preview',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.kayleoMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Spacer(),
        if (MediaQuery.sizeOf(context).height >= 820)
          Padding(
            padding: const EdgeInsets.all(KayleoSpacing.page),
            child: Panel(
              padding: 18,
              color: context.kayleoSurfaces.soft,
              border: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.circle_outlined,
                    color: context.kayleoPrimary,
                    size: 22,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Kayleo+',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'More understanding.\nMade for your everyday.',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.kayleoMuted,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          openSheet(context, PremiumSheet(state: widget.state)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.all(KayleoSpacing.md),
                      ),
                      child: Text(
                        widget.state.premium
                            ? 'Premium preview'
                            : 'Explore premium',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KayleoSpacing.page,
            0,
            KayleoSpacing.page,
            KayleoSpacing.page,
          ),
          child: InkWell(
            onTap: () => navigate(6),
            borderRadius: BorderRadius.circular(KayleoRadius.small),
            child: Container(
              padding: const EdgeInsets.all(KayleoSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: context.kayleoSurfaces.border),
                borderRadius: BorderRadius.circular(KayleoRadius.small),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: context.kayleoSurfaces.soft,
                    child: Text(
                      widget.state.profile.name.isEmpty
                          ? 'K'
                          : widget.state.profile.name.substring(0, 1),
                      style: TextStyle(
                        color: context.kayleoPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.state.profile.name,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Your personal space',
                          style: TextStyle(
                            fontSize: 9,
                            color: context.kayleoMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.tune_rounded,
                    color: context.kayleoMuted,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _topbar(bool wide) => Container(
    constraints: BoxConstraints(minHeight: wide ? 78 : 68),
    padding: EdgeInsets.symmetric(horizontal: wide ? 40 : KayleoSpacing.page),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.kayleoSurfaces.border)),
    ),
    child: Row(
      children: [
        if (wide) ...[
          Icon(Icons.circle_outlined, size: 18, color: context.kayleoPrimary),
          const SizedBox(width: 10),
          Text(
            'Understand your nutrition.',
            style: TextStyle(fontSize: 11, color: context.kayleoMuted),
          ),
        ] else
          const Brand(size: 24),
        if (wide || !widget.state.demo)
          const Spacer()
        else
          const SizedBox(width: KayleoSpacing.md),
        if (widget.state.demo)
          Flexible(
            fit: wide ? FlexFit.loose : FlexFit.tight,
            child: const Align(
              alignment: Alignment.centerRight,
              child: Tag(
                'SAMPLE DATA',
                color: KayleoColors.warningSurface,
                textColor: KayleoColors.warning,
              ),
            ),
          ),
        if (wide) ...[
          const SizedBox(width: 18),
          Icon(
            Icons.check_circle_outline_rounded,
            size: 15,
            color: context.kayleoPrimary,
          ),
          const SizedBox(width: 6),
          Text(
            'Saved on this device',
            style: TextStyle(fontSize: 10, color: context.kayleoMuted),
          ),
          const SizedBox(width: KayleoSpacing.md),
        ],
        IconButton(
          onPressed: () => openSheet(context, InboxSheet(state: widget.state)),
          tooltip: 'Your reminders',
          icon: Icon(
            Icons.notifications_none_rounded,
            size: 21,
            color: context.kayleoText,
          ),
        ),
        if (wide) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: () => navigate(6),
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 17,
              backgroundColor: context.kayleoSurfaces.soft,
              child: Text(
                widget.state.profile.name.isEmpty
                    ? 'K'
                    : widget.state.profile.name.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: context.kayleoPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class InboxSheet extends StatelessWidget {
  const InboxSheet({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final messages = <(IconData, String, String)>[
      if (state.preferences['Meal reminders']! && state.mealsFor(now).isEmpty)
        (
          Icons.restaurant_outlined,
          'A meal check-in',
          'Whenever you’re ready, log a meal to start your day.',
        ),
      if (state.preferences['Hydration reminders']! &&
          state.waterFor(now) < state.profile.waterTarget)
        (
          Icons.water_drop_outlined,
          'Time for water?',
          'You’ve logged ${state.waterFor(now)} ml today. Your current target is ${state.profile.waterTarget} ml.',
        ),
      if (state.preferences['Weekly review']! && state.meals.isNotEmpty)
        (
          Icons.show_chart_rounded,
          'Your week has a story',
          'Your weekly review is ready in Progress.',
        ),
    ];
    return SheetFrame(
      title: 'A few gentle nudges',
      subtitle: 'Your in-app reminder inbox.',
      child: Column(
        children: [
          if (messages.isEmpty)
            const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'All caught up',
              subtitle: 'No reminders right now. Choose the nudges you want in Settings.',
            ),
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Panel(
                padding: 18,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBox(m.$1, size: 37),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.$2,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.$3,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.kayleoMuted,
                              height: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: KayleoSpacing.md),
          OutlinedButton(
            onPressed: () => openSheet(context, ReminderSheet(state: state)),
            child: const Text('Manage my reminders'),
          ),
        ],
      ),
    );
  }
}
