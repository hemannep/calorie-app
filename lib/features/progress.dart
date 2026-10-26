import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import 'milestones.dart';
import '../core/nutrition_view.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../data/food_database.dart';
import 'settings.dart';
import 'logging.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.state, this.onOpenDiary});
  final AppState state;
  final VoidCallback? onOpenDiary;
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int range = 7;
  NutritionMetric metric = NutritionMetric.calories;
  final nutritionKey = GlobalKey();
  final weightKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final dates = List.generate(
      range,
      (i) => DateTime.now().subtract(Duration(days: range - 1 - i)),
    );
    final active = dates.where((d) => state.mealsFor(d).isNotEmpty).toList();
    final average = active.isEmpty
        ? Nutrients.zero
        : active
              .fold(Nutrients.zero, (sum, day) => sum + state.totalsFor(day))
              .scaled(1 / active.length);
    final weightData =
        state.weights
            .where(
              (w) => !w.date.isBefore(
                DateTime(dates.first.year, dates.first.month, dates.first.day),
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final todayMeals = state.mealsFor(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Text(
                'Progress',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              OutlinedButton.icon(
                onPressed: widget.onOpenDiary,
                icon: const Icon(Icons.calendar_month_rounded, size: 17),
                label: const Text('Full diary'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        AchievementOverview(state: state),
        const SizedBox(height: 24),
        _BmiCard(profile: state.profile),
        const SizedBox(height: 24),
        Panel(
          border: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Today’s diary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showLogger(context, state),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Log meal'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (todayMeals.isEmpty)
                Text(
                  'No meals logged today yet.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...todayMeals
                    .take(4)
                    .map(
                      (meal) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          Icons.restaurant_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          meal.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${meal.category} · ${DateFormat('h:mm a').format(meal.time)}',
                        ),
                        trailing: Text(
                          '${number(mealNutrition(meal).calories)} kcal',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
              if (todayMeals.length > 4)
                Text(
                  '+ ${todayMeals.length - 4} more meals',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          runSpacing: 8,
          children: [
            for (final days in [7, 30])
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text('$days days', style: TextStyle(fontSize: 11)),
                  selected: range == days,
                  selectedColor: Theme.of(context)
                      .extension<KayleoSurfaces>()!
                      .soft,
                  side: BorderSide(
                    color: Theme.of(context)
                        .extension<KayleoSurfaces>()!
                        .border,
                  ),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => range = days),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Panel(
          key: nutritionKey,
          padding: 16,
          border: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                range == 7 ? 'Weekly overview' : 'Monthly overview',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                'Logged meals, day by day.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final nutrient in NutritionMetric.values)
                    ChoiceChip(
                      key: Key('chart-${nutrient.name}'),
                      label: Text(
                        nutrient.label,
                        style: TextStyle(fontSize: 11),
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.all(4),
                      visualDensity: VisualDensity.compact,
                      selected: metric == nutrient,
                      selectedColor: nutrient.color.withValues(alpha: .15),
                      side: BorderSide(
                        color: Theme.of(context)
                            .extension<KayleoSurfaces>()!
                            .border,
                      ),
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        metric = nutrient;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: KayleoSpacing.page),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    '${metric.label} intake · ${metric.unit}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Daily target: ${number(metric.target(state.profile))} ${metric.unit}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _NutritionChart(state: state, dates: dates, metric: metric),
            ],
          ),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final nutrient in NutritionMetric.values)
                _stat(
                  c,
                  'Average ${nutrient.label.toLowerCase()}',
                  '${number(nutrient.amount(average))} ${nutrient.unit}',
                  'Daily target: ${number(nutrient.target(state.profile))} ${nutrient.unit}',
                  nutrient.icon,
                  nutrient == NutritionMetric.calories
                      ? Theme.of(context).colorScheme.primary
                      : nutrient.color,
                  progress:
                      (nutrient.amount(average) /
                              math.max(nutrient.target(state.profile), 1))
                          .clamp(0, 1),
                  progressKey: Key('average-${nutrient.name}-progress'),
                ),
            ],
          ),
        ),
        const SizedBox(height: KayleoSpacing.lg),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            Text(
              '${active.length} of $range days logged',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              '${state.streak}-day streak',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: KayleoSpacing.sm),
        Text(
          'Averages use days with food logged. Bars compare intake with your daily targets.',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        LayoutBuilder(
          builder: (context, c) {
            final weight = Panel(
              key: weightKey,
              border: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    'Weight trend',
                    action: 'Log weight',
                    onAction: () => logWeightDialog(context, state),
                  ),
                  if (weightData.isEmpty)
                    const EmptyState(
                      icon: Icons.monitor_weight_outlined,
                      title: 'Start your trend',
                      subtitle: 'Log your weight to start a trend.',
                    )
                  else ...[
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          _weight(weightData.last.kg, state),
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            state.profile.units == 'Metric' ? 'kg' : 'lb',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      weightData.length < 2
                          ? 'Add another entry to see a trend.'
                          : '${(weightData.last.kg - weightData.first.kg).abs().toStringAsFixed(1)} kg ${weightData.last.kg >= weightData.first.kg ? 'increase' : 'decrease'} across ${weightData.length} entries',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: KayleoSpacing.page),
                    SizedBox(
                      height: 130,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _WeightPainter(
                          weightData,
                          color: Theme.of(context).colorScheme.primary,
                          border: Theme.of(context)
                              .extension<KayleoSurfaces>()!
                              .border,
                          surface: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                    ),
                    const SizedBox(height: KayleoSpacing.md),
                    Row(
                      children: [
                        Text(
                          DateFormat('d MMM').format(weightData.first.date),
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('d MMM').format(weightData.last.date),
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Day-to-day changes are normal. Look for a longer-term pattern.',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            );
            final review = _WeeklyReviewEntry(state: state);
            return c.maxWidth > 720
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: weight),
                      const SizedBox(width: KayleoSpacing.xl),
                      Expanded(flex: 5, child: review),
                    ],
                  )
                : Column(
                    children: [
                      weight,
                      const SizedBox(height: KayleoSpacing.card),
                      review,
                    ],
                  );
          },
        ),
        const SizedBox(height: KayleoSpacing.xl),
      ],
    );
  }

  String _weight(double kg, AppState state) =>
      (state.profile.units == 'Metric' ? kg : kg * 2.20462).toStringAsFixed(1);
  Widget _stat(
    BoxConstraints c,
    String label,
    String value,
    String subtitle,
    IconData icon,
    Color color, {
    double? progress,
    Key? progressKey,
  }) => SizedBox(
    width: c.maxWidth >= 900 && MediaQuery.textScalerOf(context).scale(1) < 1.5
        ? (c.maxWidth - 48) / 4
        : c.maxWidth >= 260 && MediaQuery.textScalerOf(context).scale(1) <= 1.3
        ? (c.maxWidth - 16) / 2
        : c.maxWidth,
    child: Panel(
      border: false,
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              height: 1.3,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              height: 1.25,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              height: 1.35,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                key: progressKey,
                value: progress,
                minHeight: 4,
                color: color,
                backgroundColor: color.withValues(alpha: .13),
              ),
            ),
        ],
      ),
    ),
  );
}

class _BmiCard extends StatelessWidget {
  const _BmiCard({required this.profile});
  final BodyProfile profile;

  @override
  Widget build(BuildContext context) {
    final bmi = profile.bmi;
    final position = ((bmi - 15) / 25).clamp(0.03, 0.97).toDouble();
    final label = profile.bmiCategory;
    final color = bmi < 18.5
        ? Colors.lightBlue
        : bmi < 25
        ? Colors.green
        : bmi < 30
        ? Colors.amber
        : Colors.redAccent;
    return Panel(
      border: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BMI snapshot',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'A simple context for your current weight and height.',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                bmi.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) => Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 14,
                        child: Container(height: 10, color: Colors.lightBlue),
                      ),
                      Expanded(
                        flex: 65,
                        child: Container(height: 10, color: Colors.green),
                      ),
                      Expanded(
                        flex: 25,
                        child: Container(height: 10, color: Colors.amber),
                      ),
                      Expanded(
                        flex: 30,
                        child: Container(height: 10, color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: c.maxWidth * position - 2,
                  top: -5,
                  child: Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('18.5', style: TextStyle(fontSize: 10)),
              Text('25', style: TextStyle(fontSize: 10)),
              Text('30', style: TextStyle(fontSize: 10)),
              Text('40+', style: TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyReviewEntry extends StatelessWidget {
  const _WeeklyReviewEntry({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final dates = List.generate(
      7,
      (i) => DateTime.now().subtract(Duration(days: 6 - i)),
    );
    final loggedDays = dates
        .where((date) => state.mealsFor(date).isNotEmpty)
        .length;
    final mealCount = dates.fold<int>(
      0,
      (count, date) => count + state.mealsFor(date).length,
    );
    return Panel(
      color: Theme.of(context).extension<KayleoSurfaces>()!.soft,
      border: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.insights_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
          const SizedBox(height: KayleoSpacing.lg),
          Text(
            'Your weekly review',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: KayleoSpacing.sm),
          Text(
            loggedDays == 0
                ? 'Your review will grow with your food log.'
                : '$mealCount meals across $loggedDays logged days in the past week.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KayleoSpacing.page),
          FilledButton.icon(
            onPressed: () => openSheet(context, WeeklyReview(state: state)),
            icon: Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text('View review'),
          ),
        ],
      ),
    );
  }
}

class _NutritionChart extends StatelessWidget {
  const _NutritionChart({
    required this.state,
    required this.dates,
    required this.metric,
  });
  final AppState state;
  final List<DateTime> dates;
  final NutritionMetric metric;
  @override
  Widget build(BuildContext context) {
    final values = dates.map((d) => metric.amount(state.totalsFor(d))).toList();
    final target = metric.target(state.profile);
    final color = metric == NutritionMetric.calories
        ? Theme.of(context).colorScheme.primary
        : metric.color;
    final axisWidth =
        36.0 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final maxValue = math.max(target * 1.2, values.fold<double>(1, math.max));
    return SizedBox(
      height: 186,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: axisWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  number(maxValue),
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.25,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: KayleoSpacing.sm),
                Text(
                  number(maxValue / 2),
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.25,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: KayleoSpacing.sm),
                Text(
                  '0',
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.25,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: KayleoSpacing.xl),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  for (var i = 0; i < 4; i++)
                    Positioned(
                      top: i * 50,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 1,
                        color: Theme.of(context)
                            .extension<KayleoSurfaces>()!
                            .border,
                      ),
                    ),
                  Positioned(
                    top: 150 * (1 - target / maxValue),
                    left: 0,
                    right: 0,
                    child: Row(
                      children: List.generate(
                        40,
                        (_) => Expanded(
                          child: Container(
                            height: 1,
                            margin: const EdgeInsets.only(
                              right: KayleoSpacing.xs,
                            ),
                            color: color.withValues(alpha: .4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(
                        dates.length,
                        (i) => Expanded(
                          child: Tooltip(
                            message:
                                '${friendlyDate(dates[i])}: ${number(values[i])} ${metric.unit} ${metric.label.toLowerCase()}',
                            child: Semantics(
                              label:
                                  '${DateFormat('d MMM').format(dates[i])}: ${number(values[i])} ${metric.unit} ${metric.label.toLowerCase()}',
                              excludeSemantics: true,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: dates.length == 7
                                      ? math.min(
                                          10,
                                          c.maxWidth / dates.length * .14,
                                        )
                                      : math.min(
                                          2,
                                          c.maxWidth / dates.length * .12,
                                        ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      key: Key(
                                        'nutrition-bar-${dateKey(dates[i])}',
                                      ),
                                      height: math.max(
                                        values[i] > 0 ? 4 : 0,
                                        150 * values[i] / maxValue,
                                      ),
                                      width: dates.length == 7 ? 40 : 12,
                                      decoration: BoxDecoration(
                                        color: i == dates.length - 1
                                            ? color
                                            : color.withValues(alpha: .35),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(7),
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: KayleoSpacing.md),
                                    SizedBox(
                                      height: 24,
                                      child: OverflowBox(
                                        minWidth: 0,
                                        maxWidth: 40,
                                        minHeight: 0,
                                        maxHeight: 24,
                                        alignment: Alignment.topCenter,
                                        child: Text(
                                          dates.length == 7
                                              ? DateFormat('E').format(dates[i])
                                              : (i % 5 == 0 ||
                                                    i == dates.length - 1)
                                              ? '${dates[i].day}'
                                              : '',
                                          style: TextStyle(
                                            fontSize: 9,
                                            height: 1.25,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          softWrap: false,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
          ),
        ],
      ),
    );
  }
}

class _WeightPainter extends CustomPainter {
  _WeightPainter(
    this.entries, {
    required this.color,
    required this.border,
    required this.surface,
  });
  final Color color, border, surface;
  final List<WeightEntry> entries;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(0, i * size.height / 3),
        Offset(size.width, i * size.height / 3),
        Paint()..color = border,
      );
    }
    if (entries.isEmpty) {
      return;
    }
    final min = entries.map((w) => w.kg).reduce(math.min) - .3;
    final max = entries.map((w) => w.kg).reduce(math.max) + .3;
    final timeSpan = math.max(
      1,
      entries.last.date.difference(entries.first.date).inSeconds,
    );
    final points = entries
        .map(
          (w) => Offset(
            entries.length == 1
                ? size.width / 2
                : 8 +
                      (size.width - 16) *
                          w.date.difference(entries.first.date).inSeconds /
                          timeSpan,
            10 + (size.height - 20) * (1 - (w.kg - min) / (max - min)),
          ),
        )
        .toList();
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .13), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final p in points) {
      canvas.drawCircle(p, 3.5, Paint()..color = color);
      canvas.drawCircle(p, 1.6, Paint()..color = surface);
    }
  }

  @override
  bool shouldRepaint(_WeightPainter old) => true;
}

class WeeklyReview extends StatelessWidget {
  const WeeklyReview({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final dates = List.generate(
      7,
      (i) => DateTime.now().subtract(Duration(days: 6 - i)),
    );
    final active = dates.where((d) => state.mealsFor(d).isNotEmpty).toList();
    final totalMeals = active.fold<int>(
      0,
      (s, d) => s + state.mealsFor(d).length,
    );
    final avg = active.isEmpty
        ? 0
        : active.fold<double>(0, (s, d) => s + state.totalsFor(d).calories) /
              active.length;
    final protein = active.isEmpty
        ? 0
        : active.fold<double>(0, (s, d) => s + state.totalsFor(d).protein) /
              active.length;
    final counts = <String, int>{};
    for (final d in active) {
      for (final m in state.mealsFor(d)) {
        counts[m.name] = (counts[m.name] ?? 0) + 1;
      }
    }
    final favorites = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shareText =
        'My week with Kayleo\n${active.length} of 7 days logged · $totalMeals meals logged.\nConsistency over perfection.';
    return SheetFrame(
      title: 'Your weekly review',
      subtitle:
          '${DateFormat('d MMM').format(dates.first)} – ${DateFormat('d MMM').format(dates.last)}',
      footer: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            try {
              final box = context.findRenderObject() as RenderBox?;
              await SharePlus.instance.share(
                ShareParams(
                  text: shareText,
                  sharePositionOrigin: box == null
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size,
                ),
              );
            } catch (_) {
              if (context.mounted) {
                toast(
                  context,
                  'Sharing isn’t supported on this device. Your review is still available here.',
                );
              }
            }
          },
          icon: Icon(Icons.ios_share_rounded, size: 17),
          label: Text('Share my consistency · no weight or calories'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Panel(
            color: Theme.of(context).extension<KayleoSurfaces>()!.soft,
            border: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tag(
                  'THIS WEEK',
                  color: Theme.of(context).extension<KayleoSurfaces>()!.card,
                  textColor: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: KayleoSpacing.page),
                Text(
                  '${active.length} days logged.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$totalMeals meals logged over the past 7 days.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: KayleoSpacing.xl),
          if (active.isEmpty)
            const EmptyState(
              icon: Icons.spa_outlined,
              title: 'Your review starts with a meal',
              subtitle:
                  'Log food this week to see a review of your own records.',
            )
          else ...[
            const SectionTitle('What your logs tell us'),
            _reviewItem(
              context,
              Icons.local_fire_department_outlined,
              '${number(avg)} kcal average',
              'Across days with a meal logged. Incomplete days can lower this average.',
            ),
            _reviewItem(
              context,
              Icons.restaurant_outlined,
              '${protein.round()}g protein per logged day',
              'Your current daily target is ${state.profile.proteinTarget}g.',
            ),
            if (favorites.isNotEmpty)
              _reviewItem(
                context,
                Icons.bookmark_border_rounded,
                'A familiar favorite',
                '${favorites.first.key} appeared ${favorites.first.value} times this week.',
              ),
            const SizedBox(height: KayleoSpacing.page),
            const SectionTitle('A next step'),
            Panel(
              color: Theme.of(context).extension<KayleoSurfaces>()!.soft,
              border: false,
              child: Text(
                protein < state.profile.proteinTarget
                    ? 'Add a protein source you enjoy to one regular meal. Lentils, yogurt, eggs, or tofu can make the habit easy to repeat.'
                    : 'Save your most frequent meal as a usual. A familiar meal can turn tomorrow’s logging into a single tap.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  height: 1.8,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'This review uses your local meal records and simple rules. Estimates are general guidance, not medical advice.',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewItem(
    BuildContext context,
    IconData icon,
    String title,
    String sub,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: KayleoSpacing.page),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBox(icon, size: 36),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 5),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
