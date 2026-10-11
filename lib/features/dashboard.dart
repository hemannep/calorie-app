import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/nutrition_view.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../data/food_database.dart';
import '../services/health_service.dart';
import 'logging.dart';
import 'hydration.dart';
import 'milestones.dart';
export 'hydration.dart' show WaterPanel;

String kayleoGreeting(DateTime time) => time.hour < 12
    ? 'Good morning'
    : time.hour < 17
    ? 'Good afternoon'
    : 'Good evening';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.state,
    required this.navigate,
    this.onReminders,
  });
  final AppState state;
  final ValueChanged<int> navigate;
  final VoidCallback? onReminders;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  HealthActivityData _activityData = const HealthActivityData();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_onStateChanged);
    _loadHealthData();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_onStateChanged);
      widget.state.addListener(_onStateChanged);
      _loadHealthData();
    }
  }

  Future<void> _loadHealthData() async {
    final data = await HealthService.instance.fetchActivityData(
      DateTime.now(),
      state: widget.state,
    );
    if (mounted) {
      setState(() => _activityData = data);
    }
  }

  Future<void> _connectHealth() async {
    final appName = HealthService.instance.platformHealthAppName;
    if (_activityData.isAuthorized) {
      await _loadHealthData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced with $appName!'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final granted = await HealthService.instance.requestPermissions();
    if (mounted) {
      if (granted) {
        await _loadHealthData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to $appName! Activity data synced.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not connect to $appName. Please check health permissions in device settings.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _promptStepGoal(BuildContext context, AppState state) async {
    await showStepGoalDialog(context, state);
    if (mounted) setState(() {});
  }

  Future<void> _chooseHealthSource() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Activity data source',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Kayleo reads activity from your phone’s health system. On Android, Health Connect combines supported sources such as Samsung Health, HONOR Health, Fitbit, and Google Fit. On iPhone, Kayleo uses Apple Health.',
                style: TextStyle(fontSize: 12, color: context.kayleoMuted),
              ),
              const SizedBox(height: 16),
              _HealthSourceOption(
                icon: Icons.favorite_outline_rounded,
                title: HealthService.instance.phoneHealthSourceLabel,
                subtitle:
                    'Uses the health sources you allow in your phone settings',
                selected: true,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 12),
              Text(
                'To choose Samsung Health, HONOR Health, Google Fit, or another provider, enable that app’s Health Connect sharing and set its data priority in Health Connect settings.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: context.kayleoMuted,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    final opened = await HealthService.instance
                        .openHealthSourceSettings();
                    if (!opened) await _connectHealth();
                  },
                  icon: const Icon(Icons.settings_outlined, size: 17),
                  label: const Text('Manage health app sharing'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _loadHealthData();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final today = DateTime.now();
    final date = today;
    final meals = state.mealsFor(date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Brand(size: 34),
                  const SizedBox(height: 3),
                  Text(
                    kayleoGreeting(today),
                    key: const Key('home-time-greeting'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.kayleoPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: context.kayleoSurfaces.card,
              borderRadius: BorderRadius.circular(30),
              child: InkWell(
                onTap: () => openMilestones(context, state),
                borderRadius: BorderRadius.circular(30),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        color: badgeColor('streak'),
                        size: 23,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${state.streak}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.onReminders != null)
              IconButton(
                tooltip: 'Your reminders',
                onPressed: widget.onReminders,
                icon: const Icon(Icons.notifications_none_rounded, size: 23),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('EEEE, d MMMM').format(date),
                style: TextStyle(fontSize: 12, color: context.kayleoMuted),
              ),
            ),
            if (state.demo)
              Text(
                'Sample data',
                style: TextStyle(fontSize: 10, color: context.kayleoMuted),
              ),
          ],
        ),
        const SizedBox(height: 20),
        DashboardRingsSection(
          state: state,
          date: date,
          activity: _activityData,
          onConnectHealth: _connectHealth,
          onSelectHealthSource: _chooseHealthSource,
          onSetStepGoal: () => _promptStepGoal(context, state),
        ),
        const SizedBox(height: 10),
        _LoggingHero(state: state),
        const SizedBox(height: 16),
        SectionTitle(
          'Your meals',
          action: 'View diary',
          onAction: () => widget.navigate(1),
        ),
        if (meals.isEmpty)
          Panel(
            padding: 14,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.kayleoSurfaces.soft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.restaurant_outlined,
                    size: 27,
                    color: context.kayleoMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'No meals logged yet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add your first meal to get started.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.kayleoMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      showLogger(context, state, initialDate: date),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Add food', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          )
        else
          Panel(
            padding: 16,
            child: Column(
              children: [
                for (var i = 0; i < meals.length; i++) ...[
                  MealRow(meal: meals[i], state: state),
                  if (i < meals.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1),
                    ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 20),
        WaterPanel(state: state, date: date),
        const SizedBox(height: 20),
        StreakSummary(state: state),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LoggingHero extends StatelessWidget {
  const _LoggingHero({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: context.kayleoSurfaces.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('home-food-search'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => showLogger(context, state, mode: 'Search'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: context.kayleoMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search food, dish, or brand',
                    style: TextStyle(fontSize: 12, color: context.kayleoMuted),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: context.kayleoMuted,
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _LoggingTile(
              key: const Key('home-scan'),
              icon: Icons.camera_alt_outlined,
              label: 'Scan food',
              primary: true,
              onTap: () => showLogger(context, state, openCamera: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LoggingTile(
              icon: Icons.edit_note_rounded,
              label: 'Type it',
              onTap: () => showLogger(context, state, mode: 'Text'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _LoggingTile(
              icon: Icons.mic_none_rounded,
              label: 'Tell Kayleo',
              onTap: () => showLogger(context, state, mode: 'Voice'),
            ),
          ),
        ],
      ),
    ],
  );
}

class _HealthSourceOption extends StatelessWidget {
  const _HealthSourceOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? context.kayleoPrimary.withValues(alpha: .1)
        : context.kayleoSurfaces.soft,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: context.kayleoPrimary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: context.kayleoMuted),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? context.kayleoPrimary : context.kayleoMuted,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

class _LoggingTile extends StatelessWidget {
  const _LoggingTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final surfaces = Theme.of(context).extension<KayleoSurfaces>()!;
    return Material(
      color: primary ? colors.primary : surfaces.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(
              color: primary ? colors.primary : surfaces.border,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: primary ? colors.onPrimary : colors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: primary ? colors.onPrimary : colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalorieSummary extends StatelessWidget {
  const _CalorieSummary({required this.state, required this.date});
  final AppState state;
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final nutrition = state.totalsFor(date);
    final target = state.profile.calorieTarget;
    final remaining = target - nutrition.calories;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final consumed = state.showConsumedCalories;
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          number(consumed ? nutrition.calories : remaining.abs()),
          style: const TextStyle(
            fontSize: 38,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          consumed
              ? 'Calories consumed'
              : remaining >= 0
              ? 'Calories left'
              : 'Calories over',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        Text(
          '${number(nutrition.calories)} / ${number(target)} kcal · Tap to switch',
          style: TextStyle(fontSize: 11, color: context.kayleoMuted),
        ),
      ],
    );
    final ring = KayleoRing(
      progress: target > 0 ? nutrition.calories / target : 0,
      key: const Key('today-calorie-ring'),
      segmented: true,
      size: 112,
      stroke: 9,
      highlight: false,
      color: context.kayleoPrimary,
      track: context.kayleoSurfaces.soft,
      semanticLabel:
          '${number(nutrition.calories)} calories consumed of $target target',
      child: Container(
        margin: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: context.kayleoBackground,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.local_fire_department_rounded,
          size: 26,
          color: context.kayleoPrimary,
        ),
      ),
    );
    return Semantics(
      button: true,
      label: 'Switch calorie display',
      child: InkWell(
        key: const Key('calorie-display-toggle'),
        borderRadius: BorderRadius.circular(KayleoRadius.large),
        onTap: () {
          state.showConsumedCalories = !state.showConsumedCalories;
          state.persist();
        },
        child: Panel(
          padding: 20,
          child: large
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: 16),
                    Center(child: ring),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 12),
                    ring,
                  ],
                ),
        ),
      ),
    );
  }
}

class _MacroProgress extends StatelessWidget {
  const _MacroProgress({
    required this.state,
    required this.date,
    this.compact = false,
  });
  final AppState state;
  final DateTime date;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final nutrition = state.totalsFor(date);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final consumed = state.showConsumedCalories;
    return LayoutBuilder(
      builder: (context, c) {
        final width = large ? c.maxWidth : (c.maxWidth - 20) / 3;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in [
              NutritionMetric.protein,
              NutritionMetric.carbs,
              NutritionMetric.fats,
            ])
              SizedBox(
                width: width,
                child: _DashboardMetricCard(
                  key: Key('today-${metric.name}-card'),
                  onTap: () {
                    state.showConsumedCalories = !state.showConsumedCalories;
                    state.persist();
                  },
                  amount: consumed
                      ? '${number(metric.amount(nutrition))}g'
                      : '${number((metric.target(state.profile) - metric.amount(nutrition)).abs())}g',
                  label: consumed
                      ? '${metric.label} consumed'
                      : '${metric.label} ${metric.amount(nutrition) <= metric.target(state.profile) ? 'left' : 'over'}',
                  ring: KayleoRing(
                    progress: metric.target(state.profile) > 0
                        ? metric.amount(nutrition) /
                              metric.target(state.profile)
                        : 0,
                    size: 50,
                    stroke: 5,
                    highlight: false,
                    color: metric.color,
                    track: context.kayleoSurfaces.soft,
                    semanticLabel:
                        '${metric.label}: ${number(metric.amount(nutrition))} of ${metric.target(state.profile)} grams',
                    child:
                        !consumed &&
                            metric.amount(nutrition) >
                                metric.target(state.profile)
                        ? Padding(
                            padding: const EdgeInsets.all(9),
                            child: FittedBox(
                              child: Text(
                                '${number(metric.amount(nutrition))}g',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            margin: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: metric.color.withValues(alpha: .08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              metric.icon,
                              color: metric.color,
                              size: 18,
                            ),
                          ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class DashboardRingsSection extends StatefulWidget {
  const DashboardRingsSection({super.key,
    required this.state,
    required this.date,
    required this.activity,
    required this.onConnectHealth,
    required this.onSelectHealthSource,
    required this.onSetStepGoal,
  });

  final AppState state;
  final DateTime date;
  final HealthActivityData activity;
  final VoidCallback onConnectHealth;
  final VoidCallback onSelectHealthSource;
  final VoidCallback onSetStepGoal;

  @override
  State<DashboardRingsSection> createState() => _DashboardRingsSectionState();
}

class _DashboardRingsSectionState extends State<DashboardRingsSection> {
  late final PageController _pageController;
  int _currentPage = 0;
  final _pageKeys = [GlobalKey(), GlobalKey()];
  final _pageHeights = <int, double>{};

  void _measurePages() {
    if (!mounted) return;
    var changed = false;
    for (var index = 0; index < _pageKeys.length; index++) {
      final box = _pageKeys[index].currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final height = box.size.height;
        if (height > 0 && ((_pageHeights[index] ?? 0) - height).abs() > .5) {
          _pageHeights[index] = height;
          changed = true;
        }
      }
    }
    if (changed) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measurePages());
    final pageHeight = _pageHeights[_currentPage] ?? 325.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: pageHeight,
            child: PageView(
              key: const Key('today-rings-pageview'),
              controller: _pageController,
              clipBehavior: Clip.hardEdge,
              pageSnapping: true,
              physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
              onPageChanged: (idx) => setState(() => _currentPage = idx),
              children: [
                // Page 0: Nutrition overview
                OverflowBox(
                  minHeight: 0,
                  maxHeight: double.infinity,
                  alignment: Alignment.topCenter,
                  child: Column(
                    key: _pageKeys[0],
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CalorieSummary(state: widget.state, date: widget.date),
                      const SizedBox(height: 12),
                      _MacroProgress(
                        state: widget.state,
                        date: widget.date,
                        compact: true,
                      ),
                    ],
                  ),
                ),
                // Page 1: Health & Activity overview
                OverflowBox(
                  minHeight: 0,
                  maxHeight: double.infinity,
                  alignment: Alignment.topCenter,
                  child: Column(
                    key: _pageKeys[1],
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepSummary(
                        state: widget.state,
                        date: widget.date,
                        activity: widget.activity,
                        onTap: widget.onSetStepGoal,
                        onConnectHealth: widget.onConnectHealth,
                        onSelectHealthSource: widget.onSelectHealthSource,
                      ),
                      const SizedBox(height: 12),
                      _ActivityProgress(
                        state: widget.state,
                        activity: widget.activity,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            2,
            (index) => InkWell(
              key: Key(
                index == 0 ? 'rings-pill-nutrition' : 'rings-pill-activity',
              ),
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                width: _currentPage == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? context.kayleoPrimary
                      : context.kayleoSurfaces.border,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepSummary extends StatelessWidget {
  const _StepSummary({
    required this.state,
    required this.date,
    required this.activity,
    required this.onTap,
    required this.onConnectHealth,
    required this.onSelectHealthSource,
  });

  final AppState state;
  final DateTime date;
  final HealthActivityData activity;
  final VoidCallback onTap;
  final VoidCallback onConnectHealth;
  final VoidCallback onSelectHealthSource;

  @override
  Widget build(BuildContext context) {
    final target = state.stepTarget;
    final steps = activity.steps;
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final reached = target > 0 && steps >= target;
    final isAuthorized = activity.isAuthorized;
    final appName = HealthService.instance.platformHealthAppName;
    final sourceLabel = HealthService.instance.shortHealthSourceLabel;
    final hasHealthData =
        steps > 0 ||
        activity.activeMinutes > 0 ||
        activity.activeCalories > 0 ||
        activity.motionKm > 0;

    // Build a concise subtitle showing steps + calories burned
    String buildSubtitle() {
      if (!hasHealthData) return 'No data shared · Check Health Connect';
      final parts = <String>['${number(steps)} / ${number(target)} steps'];
      if (activity.activeCalories > 0) {
        parts.add('${number(activity.activeCalories)} kcal burned');
      }
      parts.add(sourceLabel);
      return parts.join(' · ');
    }

    const stepColor = Color(0xFF10B981);
    final ring = KayleoRing(
      progress: target > 0 ? steps / target : 0,
      key: const Key('today-step-ring'),
      size: 112,
      stroke: 9,
      highlight: false,
      color: stepColor,
      track: context.kayleoSurfaces.soft,
      semanticLabel: '$steps steps taken of $target target',
      child: Container(
        margin: const EdgeInsets.all(23),
        decoration: BoxDecoration(
          color: context.kayleoBackground,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.directions_walk_rounded,
          size: 24,
          color: stepColor,
        ),
      ),
    );

    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          number(steps),
          style: const TextStyle(
            fontSize: 38,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          reached ? 'Step goal reached!' : 'Steps today',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        if (isAuthorized)
          InkWell(
            key: const Key('sync-health-button'),
            onTap: onSelectHealthSource,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync_rounded, size: 13, color: stepColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    buildSubtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: stepColor,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          InkWell(
            key: const Key('connect-health-button'),
            onTap: onConnectHealth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_rounded, size: 13, color: stepColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Not connected · Connect $appName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: stepColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Semantics(
      button: true,
      label: isAuthorized ? 'Set step goal' : 'Connect health and set goal',
      child: InkWell(
        key: const Key('step-goal-trigger'),
        borderRadius: BorderRadius.circular(KayleoRadius.large),
        onTap: onTap,
        child: Panel(
          padding: 20,
          child: large
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: 16),
                    Center(child: ring),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 12),
                    ring,
                  ],
                ),
        ),
      ),
    );
  }
}

class _ActivityProgress extends StatelessWidget {
  const _ActivityProgress({required this.state, required this.activity});

  final AppState state;
  final HealthActivityData activity;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    // Format active time as hours + minutes when >= 60 min
    final activeTimeLabel = activity.activeMinutes >= 60
        ? '${activity.activeMinutes ~/ 60}h ${activity.activeMinutes % 60}m'
        : '${activity.activeMinutes}m';

    final metrics = [
      _ActivityMetricItem(
        key: const ValueKey('today-active-time-ring'),
        label: 'Active time',
        amount: activeTimeLabel,
        targetLabel: '${state.activeMinutesTarget}m',
        progress: state.activeMinutesTarget > 0
            ? activity.activeMinutes / state.activeMinutesTarget
            : 0.0,
        color: const Color(0xFF10B981),
        icon: Icons.timer_outlined,
        reached: activity.activeMinutes >= state.activeMinutesTarget,
        isEstimated: !activity.rawActiveMinutes && activity.steps > 0,
      ),
      _ActivityMetricItem(
        key: const ValueKey('today-activity-calorie-ring'),
        label: 'Calories burned',
        amount: '${activity.activeCalories}',
        targetLabel: '${state.activeCaloriesTarget} kcal',
        progress: state.activeCaloriesTarget > 0
            ? activity.activeCalories / state.activeCaloriesTarget
            : 0.0,
        color: const Color(0xFFFF5722),
        icon: Icons.local_fire_department_rounded,
        reached: activity.activeCalories >= state.activeCaloriesTarget,
        isEstimated: !activity.rawActiveCalories && activity.steps > 0,
      ),
      _ActivityMetricItem(
        key: const ValueKey('today-motion-ring'),
        label: 'Distance',
        amount: '${activity.motionKm.toStringAsFixed(1)} km',
        targetLabel: '${state.motionKmTarget.toStringAsFixed(1)} km',
        progress: state.motionKmTarget > 0
            ? activity.motionKm / state.motionKmTarget
            : 0.0,
        color: const Color(0xFF06B6D4),
        icon: Icons.directions_walk_rounded,
        reached: activity.motionKm >= state.motionKmTarget,
        isEstimated: !activity.rawDistance && activity.steps > 0,
      ),
    ];

    // Show extra health stats when we have richer data from the health app
    final hasExtraStats =
        activity.basalCalories > 0 ||
        activity.floorsClimbed > 0 ||
        activity.heartRateAvg > 0;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final width = large ? c.maxWidth : (c.maxWidth - 20) / 3;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in metrics)
                  SizedBox(
                    width: width,
                    child: _DashboardMetricCard(
                      key: Key('${m.key.value}-card'),
                      amount: m.amount,
                      label: m.label,
                      isEstimated: m.isEstimated,
                      ring: KayleoRing(
                        key: m.key,
                        progress: m.progress,
                        size: 50,
                        stroke: 5,
                        highlight: false,
                        color: m.color,
                        track: context.kayleoSurfaces.soft,
                        semanticLabel:
                            '${m.label}: ${m.amount} of ${m.targetLabel}',
                        child: m.reached
                            ? Padding(
                                padding: const EdgeInsets.all(9),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: m.color,
                                ),
                              )
                            : Container(
                                margin: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: m.color.withValues(alpha: .08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(m.icon, color: m.color, size: 18),
                              ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        // Extra health stats row (heart rate, floors, total burn)
        if (hasExtraStats) ...[
          const SizedBox(height: 10),
          Panel(
            padding: 14,
            child: Row(
              children: [
                if (activity.totalCaloriesBurned > 0)
                  Expanded(
                    child: _ExtraStatChip(
                      icon: Icons.whatshot_rounded,
                      color: const Color(0xFFFF5722),
                      label: 'Total burn',
                      value: '${number(activity.totalCaloriesBurned)} kcal',
                    ),
                  ),
                if (activity.heartRateAvg > 0)
                  Expanded(
                    child: _ExtraStatChip(
                      icon: Icons.favorite_rounded,
                      color: const Color(0xFFE91E63),
                      label: 'Avg HR',
                      value: '${activity.heartRateAvg} bpm',
                    ),
                  ),
                if (activity.floorsClimbed > 0)
                  Expanded(
                    child: _ExtraStatChip(
                      icon: Icons.stairs_rounded,
                      color: const Color(0xFF9C27B0),
                      label: 'Floors',
                      value: '${activity.floorsClimbed}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Shared sizing keeps both carousel pages aligned, including estimated data.
class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({
    super.key,
    required this.amount,
    required this.label,
    required this.ring,
    this.isEstimated = false,
    this.onTap,
  });

  final String amount, label;
  final Widget ring;
  final bool isEstimated;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = Panel(
      padding: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 20 : 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
          Visibility(
            visible: isEstimated,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'from steps',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                  color: context.kayleoMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(child: ring),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (onTap == null) return panel;
    return InkWell(
      borderRadius: BorderRadius.circular(KayleoRadius.large),
      onTap: onTap,
      child: panel,
    );
  }
}

class _ExtraStatChip extends StatelessWidget {
  const _ExtraStatChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 6),
      Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: -.3,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: context.kayleoMuted,
        ),
      ),
    ],
  );
}

class _ActivityMetricItem {
  const _ActivityMetricItem({
    required this.key,
    required this.label,
    required this.amount,
    required this.targetLabel,
    required this.progress,
    required this.color,
    required this.icon,
    required this.reached,
    this.isEstimated = false,
  });

  final ValueKey<String> key;
  final String label;
  final String amount;
  final String targetLabel;
  final double progress;
  final Color color;
  final IconData icon;
  final bool reached;

  /// Whether this metric was estimated from step count rather than coming directly from HealthKit / Health Connect.
  final bool isEstimated;
}

Future<void> showStepGoalDialog(BuildContext context, AppState state) async {
  final controller = TextEditingController(text: '${state.stepTarget}');
  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KayleoRadius.large),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.directions_walk_rounded,
                  color: Color(0xFF10B981),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Daily Step Goal',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set your daily step target. Steps will be tracked automatically from your health app.',
                    style: TextStyle(fontSize: 13, color: context.kayleoMuted),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('step-goal-input'),
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Target steps',
                      suffixText: 'steps',
                    ),
                    validator: (val) {
                      final n = int.tryParse(val?.trim() ?? '');
                      if (n == null || n < 500 || n > 100000) {
                        return 'Enter between 500 and 100,000 steps';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [6000, 8000, 10000, 12000].map((preset) {
                      final selected = controller.text == '$preset';
                      return ChoiceChip(
                        label: Text('$preset'),
                        selected: selected,
                        onSelected: (_) {
                          controller.text = '$preset';
                          setModalState(() {});
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('save-step-goal-button'),
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final parsed = int.parse(controller.text.trim());
                  await state.updateStepTarget(parsed);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }
              },
              child: const Text('Save goal'),
            ),
          ],
        );
      },
    ),
  );
}

class EnergyPanel extends StatelessWidget {
  const EnergyPanel({super.key, required this.state, required this.date});
  final AppState state;
  final DateTime date;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      children: [
        _CalorieSummary(state: state, date: date),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Divider(height: 1),
        ),
        _MacroProgress(state: state, date: date),
      ],
    ),
  );
}

class MealRow extends StatelessWidget {
  const MealRow({super.key, required this.meal, required this.state});
  final Meal meal;
  final AppState state;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => showLogger(context, state, meal: meal),
    borderRadius: BorderRadius.circular(13),
    child: Row(
      children: [
        FoodPhoto(
          image: meal.image,
          meal: meal,
          width: 54,
          height: 54,
          radius: 13,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meal.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: 5),
              Text(
                '${meal.category}  ·  ${DateFormat('h:mm a').format(meal.time)}',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: KayleoSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${number(mealNutrition(meal).calories)} kcal',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            const SizedBox(height: KayleoSpacing.xs),
            Text(
              '${mealNutrition(meal).protein.round()}g protein',
              style: TextStyle(
                fontSize: 9,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'Meal options',
          icon: Icon(
            Icons.more_horiz_rounded,
            size: 19,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit meal')),
            const PopupMenuItem(value: 'save', child: Text('Save as a usual')),
            const PopupMenuItem(value: 'repeat', child: Text('Log again')),
            const PopupMenuItem(value: 'delete', child: Text('Delete meal')),
          ],
          onSelected: (value) async {
            if (value == 'edit') {
              showLogger(context, state, meal: meal);
            }
            if (value == 'save') {
              await state.saveTemplate(meal);
              if (context.mounted) {
                toast(context, 'Added to your saved meals');
              }
            }
            if (value == 'repeat') {
              if (!context.mounted) {
                return;
              }
              showLogger(
                context,
                state,
                meal: meal.copy(id: newId(), time: DateTime.now()),
              );
            }
            if (value == 'delete') {
              if (!context.mounted) {
                return;
              }
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Delete this meal?'),
                  content: Text(
                    '“${meal.name}” will be removed from your diary.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Keep meal'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await state.deleteMeal(meal.id);
                if (context.mounted) {
                  toast(
                    context,
                    'Meal removed',
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: lime,
                      onPressed: () => state.saveMeal(meal),
                    ),
                  );
                }
              }
            }
          },
        ),
      ],
    ),
  );
}
