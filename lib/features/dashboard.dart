import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/nutrition_view.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../data/food_database.dart';
import 'logging.dart';
import 'hydration.dart';
export 'hydration.dart' show WaterPanel;

class DashboardScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nutrition = state.totalsFor(now);
    final meals = state.mealsFor(now);
    final colors = Theme.of(context).colorScheme;
    final surfaces = Theme.of(context).extension<KayleoSurfaces>()!;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
        ? 'Good afternoon'
        : 'Good evening';
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
                    greeting,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${state.profile.name}.',
                    style: TextStyle(
                      fontSize: 25,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (state.demo && !largeText)
              Tag(
                'SAMPLE DATA',
                color: surfaces.soft,
                textColor: colors.onSurfaceVariant,
              ),
            if (onReminders != null)
              IconButton(
                tooltip: 'Your reminders',
                onPressed: onReminders,
                icon: Icon(
                  Icons.notifications_none_rounded,
                  color: colors.primary,
                ),
              ),
          ],
        ),
        if (state.demo && largeText) ...[
          const SizedBox(height: 8),
          Tag(
            'SAMPLE DATA',
            color: surfaces.soft,
            textColor: colors.onSurfaceVariant,
          ),
        ],
        const SizedBox(height: 10),
        _CalorieSummary(state: state, date: now),
        const SizedBox(height: 18),
        _LoggingHero(state: state),
        const SizedBox(height: 14),
        Panel(
          padding: 14,
          border: false,
          child: _MacroProgress(state: state, date: now, compact: true),
        ),
        const SizedBox(height: 24),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                'Today’s meals',
                action: 'View diary',
                onAction: () => navigate(1),
              ),
              if (meals.isEmpty)
                EmptyState(
                  icon: Icons.restaurant_outlined,
                  title: 'Your first meal starts here',
                  subtitle: 'Scan your food or tell Kayleo what you ate.',
                  action: FilledButton.icon(
                    onPressed: () => showLogger(context, state),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add food'),
                  ),
                )
              else ...[
                for (var i = 0; i < meals.length; i++) ...[
                  MealRow(meal: meals[i], state: state),
                  if (i < meals.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1),
                    ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => showLogger(context, state),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add food'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final hydration = WaterPanel(state: state, date: now);
            final consistency = _ConsistencyPanel(
              state: state,
              onTap: () => navigate(3),
            );
            return constraints.maxWidth >= 700
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: hydration),
                      const SizedBox(width: 20),
                      Expanded(child: consistency),
                    ],
                  )
                : Column(
                    children: [
                      hydration,
                      const SizedBox(height: 20),
                      consistency,
                    ],
                  );
          },
        ),
        if (meals.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DailyNote(state: state, nutrition: nutrition),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LoggingHero extends StatelessWidget {
  const _LoggingHero({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => Panel(
    border: false,
    padding: 14,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What did you eat?',
          style: TextStyle(
            fontSize: 18,
            height: 1.25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 14),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('home-barcode'),
              onPressed: () => showLogger(context, state, mode: 'Barcode'),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text('Barcode'),
            ),
            OutlinedButton.icon(
              key: const Key('home-food-search'),
              onPressed: () => showLogger(context, state, mode: 'Search'),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Food search'),
            ),
          ],
        ),
      ],
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
      color: primary ? lime : Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: primary ? lime : surfaces.border.withValues(alpha: .45),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: primary ? forest : colors.primary),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: primary ? forest : colors.onSurface,
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
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final colors = Theme.of(context).colorScheme;
    final surfaces = Theme.of(context).extension<KayleoSurfaces>()!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseSize = constraints.maxWidth < 330 ? 180.0 : 196.0;
        final ringSize = (baseSize + (scale - 1).clamp(0.0, 1.0) * 56).clamp(
          0.0,
          constraints.maxWidth,
        );
        return Column(
          children: [
            Center(
              child: KayleoRing(
                progress: target > 0 ? nutrition.calories / target : 0,
                size: ringSize,
                stroke: 11,
                color: colors.primary,
                track: surfaces.soft,
                semanticLabel:
                    '${number(nutrition.calories)} calories consumed of $target daily target; ${number(remaining.abs())} calories ${remaining >= 0 ? 'remaining' : 'over target'}',
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          number(nutrition.calories),
                          style: TextStyle(
                            fontSize: scale > 1.3 ? 28 : 38,
                            height: 1.15,
                            letterSpacing: -1.1,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        'kcal',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${number(remaining.abs())} ${remaining >= 0 ? 'remaining' : 'over target'}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Daily target: ${number(target)} kcal',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compact ? 'Today’s macros' : 'Your macros',
          style: TextStyle(
            fontSize: compact ? 15 : 16,
            height: 1.25,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        LayoutBuilder(
          builder: (context, c) {
            final width = (c.maxWidth - 24) / 3;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final metric in [
                  NutritionMetric.protein,
                  NutritionMetric.carbs,
                  NutritionMetric.fats,
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          KayleoRing(
                            progress: metric.target(state.profile) > 0
                                ? metric.amount(nutrition) /
                                      metric.target(state.profile)
                                : 0,
                            size: width.clamp(50, 104),
                            stroke: 6,
                            highlight: false,
                            color: metric.color,
                            track: context.kayleoSurfaces.soft,
                            semanticLabel:
                                '${metric.label}: ${number(metric.amount(nutrition))} g of ${metric.target(state.profile)} g daily target',
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: FittedBox(
                                child: Text(
                                  '${number(metric.amount(nutrition))}g',
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            metric.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '/ ${metric.target(state.profile)} g',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.kayleoMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
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

class _DailyNote extends StatelessWidget {
  const _DailyNote({required this.state, required this.nutrition});
  final AppState state;
  final Nutrients nutrition;
  @override
  Widget build(BuildContext context) {
    final proteinLeft = (state.profile.proteinTarget - nutrition.protein)
        .clamp(0, 500)
        .round();
    return Panel(
      color: Theme.of(context).extension<KayleoSurfaces>()!.soft,
      border: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBox(Icons.insights_outlined, size: 36, color: lime),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From today’s food',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Text(
                  proteinLeft > 0
                      ? '${number(nutrition.protein)}g protein logged. ${proteinLeft}g remains to your daily target.'
                      : '${number(nutrition.protein)}g protein logged. You’ve reached your daily target.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.primary,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsistencyPanel extends StatelessWidget {
  const _ConsistencyPanel({required this.state, required this.onTap});
  final AppState state;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final dates = List.generate(
      7,
      (i) => DateTime.now().subtract(Duration(days: 6 - i)),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your week',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
              const Spacer(),
              Icon(Icons.wb_sunny_outlined, size: 19, color: orange),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: dates
                .map(
                  (d) => Column(
                    children: [
                      Container(
                        width: 27,
                        height: 27,
                        decoration: BoxDecoration(
                          color: state.mealsFor(d).isNotEmpty
                              ? Theme.of(context)
                                    .extension<KayleoSurfaces>()!
                                    .soft
                              : Theme.of(context).scaffoldBackgroundColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          state.mealsFor(d).isNotEmpty
                              ? Icons.check_rounded
                              : Icons.remove_rounded,
                          size: 13,
                          color: state.mealsFor(d).isNotEmpty
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                    .extension<KayleoSurfaces>()!
                                    .border,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        DateFormat('E').format(d).substring(0, 1),
                        style: TextStyle(
                          fontSize: 9,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: KayleoSpacing.lg),
          Row(
            children: [
              Text(
                '${state.streak} day${state.streak == 1 ? '' : 's'} in a row',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
