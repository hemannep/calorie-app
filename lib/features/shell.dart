import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/milestones.dart';
import '../core/ui.dart';
import 'dashboard.dart';
import 'diary.dart';
import 'logging.dart';
import 'progress.dart';
import 'settings.dart';
import 'profile_avatar.dart';
import 'community.dart';
import 'milestones.dart';

const _nav = [
  ('today', Icons.grid_view_rounded),
  ('community', Icons.people_outline_rounded),
  ('progress', Icons.show_chart_rounded),
  ('scanFood', Icons.camera_alt_outlined),
  ('savedMeals', Icons.bookmark_border_rounded),
  ('you', Icons.tune_rounded),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});
  final AppState state;
  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => _buildShell(context),
  );

  Widget _buildShell(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final useIosGlassBar =
        !wide && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final state = widget.state;
    return MilestoneCelebrationHost(
      state: state,
      child: PopScope<void>(
        canPop: selected != 6,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && selected == 6) navigate(2);
        },
        child: Scaffold(
          extendBody: useIosGlassBar,
          body: SafeArea(
            child: Row(
              children: [
                if (wide) _sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      if (selected != 6 &&
                          (wide || ![0, 1, 2, 5].contains(selected)))
                        _topbar(wide),
                      if (state.storageError != null)
                        MaterialBanner(
                          content: LocalizedText(
                            state.storageError!,
                            style: const TextStyle(fontSize: 12),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => exportData(context, state),
                              child: const LocalizedText('Export backup'),
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
                                  onReminders: () => openSheet(
                                    context,
                                    InboxSheet(state: state),
                                  ),
                                ),
                                1 => CommunityScreen(state: state),
                                2 => ProgressScreen(
                                  state: state,
                                  onOpenDiary: () => navigate(6),
                                ),
                                3 => CaptureScreen(state: state),
                                4 => SavedMealsScreen(state: state),
                                6 => DiaryScreen(state: state),
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
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          floatingActionButton: wide
              ? null
              : useIosGlassBar
              ? null
              : SizedBox.square(
                  dimension: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: context.kayleoPrimary.withValues(alpha: .18),
                          blurRadius: 18,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: FloatingActionButton(
                      key: const Key('bottom-camera-button'),
                      tooltip: context.l10n.t('scanFood'),
                      backgroundColor: context.kayleoPrimary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      elevation: 0,
                      focusElevation: 0,
                      hoverElevation: 0,
                      highlightElevation: 0,
                      shape: const CircleBorder(),
                      onPressed: () =>
                          showLogger(context, widget.state, openCamera: true),
                      child: const Icon(Icons.camera_alt_outlined, size: 26),
                    ),
                  ),
                ),
          bottomNavigationBar: wide
              ? null
              : useIosGlassBar
              ? _iosGlassBottomBar()
              : _bottomBar(),
        ),
      ),
    );
  }

  Widget _iosGlassBottomBar() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = context.kayleoText;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SizedBox(
        height: 80,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? .34 : .16),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: dark ? .06 : .34),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(34),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dark
                              ? [
                                  const Color(0xFF26382D)
                                      .withValues(alpha: .78),
                                  const Color(0xFF101713)
                                      .withValues(alpha: .52),
                                ]
                              : [
                                  Colors.white.withValues(alpha: .82),
                                  const Color(0xFFF5FAF2)
                                      .withValues(alpha: .54),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          width: 1.25,
                          color: Colors.white.withValues(
                            alpha: dark ? .27 : .88,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          _iosGlassItem(
                            0,
                            Icons.grid_view_rounded,
                            context.l10n.t('today'),
                            foreground,
                          ),
                          _iosGlassItem(
                            1,
                            Icons.people_outline_rounded,
                            context.l10n.t('community'),
                            foreground,
                          ),
                          const Expanded(child: SizedBox()),
                          _iosGlassItem(
                            2,
                            Icons.show_chart_rounded,
                            context.l10n.t('progress'),
                            foreground,
                          ),
                          _iosGlassItem(
                            5,
                            Icons.person_outline_rounded,
                            context.l10n.t('you'),
                            foreground,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Semantics(
                button: true,
                label: context.l10n.t('scanFood'),
                child: Tooltip(
                  message: context.l10n.t('scanFood'),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(context.kayleoPrimary, Colors.white, .14)!,
                          context.kayleoPrimary,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.kayleoPrimary.withValues(alpha: .34),
                          blurRadius: 20,
                          offset: const Offset(0, 7),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: dark ? .34 : .16,
                          ),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: const Key('bottom-camera-button'),
                        customBorder: const CircleBorder(),
                        onTap: () =>
                            showLogger(context, widget.state, openCamera: true),
                        child: Icon(
                          Icons.camera_alt_outlined,
                          size: 26,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iosGlassItem(
    int index,
    IconData icon,
    String label,
    Color foreground,
  ) {
    final active = selected == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => navigate(index),
              customBorder: const CircleBorder(),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOut,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? context.kayleoSurfaces.soft.withValues(alpha: .72)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: active ? context.kayleoPrimary : foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    var labelHeight = 0.0;
    for (final label in [
      context.l10n.t('today'),
      context.l10n.t('community'),
      context.l10n.t('progress'),
      context.l10n.t('you'),
    ]) {
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
    final rowHeight = (41 + labelHeight).clamp(56.0, double.infinity);
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      color: context.kayleoSurfaces.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: rowHeight,
      child: Row(
        children: [
          _bottomItem(0, Icons.grid_view_rounded, context.l10n.t('today')),
          _bottomItem(
            1,
            Icons.people_outline_rounded,
            context.l10n.t('community'),
          ),
          const Expanded(child: SizedBox()),
          _bottomItem(2, Icons.show_chart_rounded, context.l10n.t('progress')),
          _bottomItem(5, Icons.person_outline_rounded, context.l10n.t('you')),
        ],
      ),
    );
  }

  Widget _bottomItem(int index, IconData icon, String label) => Expanded(
    child: InkWell(
      onTap: () => navigate(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
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
            LocalizedText(
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
          child: LocalizedText(
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
                          LocalizedText(
                            context.l10n.t(_nav[i].$1),
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
                          if (i == 1)
                            LocalizedText(
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
                  const LocalizedText(
                    'Kayleo+',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const SizedBox(height: 7),
                  LocalizedText(
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
                      child: LocalizedText(
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
            onTap: () => navigate(5),
            borderRadius: BorderRadius.circular(KayleoRadius.small),
            child: Container(
              padding: const EdgeInsets.all(KayleoSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: context.kayleoSurfaces.border),
                borderRadius: BorderRadius.circular(KayleoRadius.small),
              ),
              child: Row(
                children: [
                  ProfileAvatar(profile: widget.state.profile, radius: 17),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LocalizedText(
                          widget.state.profile.name,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        LocalizedText(
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
        if (selected == 6)
          LocalizedText(
            'Diary',
            style: TextStyle(
              fontSize: wide ? 20 : 18,
              fontWeight: FontWeight.w800,
            ),
          )
        else if (wide) ...[
          Icon(Icons.circle_outlined, size: 18, color: context.kayleoPrimary),
          const SizedBox(width: 10),
          LocalizedText(
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
          LocalizedText(
            'Saved on this device',
            style: TextStyle(fontSize: 10, color: context.kayleoMuted),
          ),
          const SizedBox(width: KayleoSpacing.md),
        ],
        if (selected != 6)
          IconButton(
            onPressed: () =>
                openSheet(context, InboxSheet(state: widget.state)),
            tooltip: context.l10n.translate('Your reminders'),
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
            child: ProfileAvatar(profile: widget.state.profile, radius: 17),
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => _content(context),
  );
  Widget _content(BuildContext context) {
    final now = DateTime.now();
    final messages = <(IconData, String, String)>[
      for (final id in state.milestoneNotices.reversed)
        for (final m in milestones.where((m) => m.id == id))
          (Icons.emoji_events_outlined, 'Well done! ${m.title}', m.compliment),
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
                    const KayleoIcon(size: 37, radius: 10),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: LocalizedText(
                                  m.$2,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                m.$1,
                                size: 16,
                                color: context.kayleoPrimary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LocalizedText(
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
            child: const LocalizedText('Manage my reminders'),
          ),
        ],
      ),
    );
  }
}
