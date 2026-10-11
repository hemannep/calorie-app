import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../data/food_database.dart';
import '../services/health_service.dart';
import 'dashboard.dart';
import 'logging.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key, required this.state});
  final AppState state;
  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  DateTime date = DateTime.now();
  String search = '', category = 'All meals';
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final meals = state
        .mealsFor(date)
        .where(
          (m) =>
              (category == 'All meals' || m.category == category) &&
              m.name.toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    final days = List.generate(
      7,
      (i) => date.subtract(Duration(days: date.weekday - 1 - i)),
    );
    final n = state.totalsFor(date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your food log', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('EEEE, d MMMM').format(date),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Panel(
          padding: 18,
          border: false,
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => setState(
                      () => date = date.subtract(const Duration(days: 7)),
                    ),
                    tooltip: 'Previous week',
                    icon: Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          );
                          if (d != null) {
                            setState(() => date = d);
                          }
                        },
                        icon: const Icon(Icons.calendar_today_outlined, size: 15),
                        label: Text(
                          DateFormat('MMMM yyyy').format(date),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: days.last.isBefore(DateTime.now())
                        ? () => setState(
                            () => date = date.add(const Duration(days: 7)),
                          )
                        : null,
                    tooltip: 'Next week',
                    icon: Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: KayleoSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose a day',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() < 80) return;
                  setState(() {
                    date = date.add(Duration(days: velocity < 0 ? 7 : -7));
                  });
                },
                child: Row(
                  children: days
                      .map(
                        (d) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: InkWell(
                            onTap: d.isAfter(DateTime.now())
                                ? null
                                : () => setState(() => date = d),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                color: dateKey(d) == dateKey(date)
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      DateFormat('E').format(d),
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.25,
                                        color: dateKey(d) == dateKey(date)
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: KayleoSpacing.sm),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '${d.day}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        height: 1.2,
                                        fontWeight: FontWeight.w800,
                                        color: dateKey(d) == dateKey(date)
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Container(
                                    width: 4,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: state.mealsFor(d).isEmpty
                                          ? Colors.transparent
                                          : dateKey(d) == dateKey(date)
                                          ? Theme.of(context)
                                                .colorScheme
                                                .onPrimary
                                          : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DiaryOverview(state: state, date: date, nutrition: n),
        const SizedBox(height: KayleoSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final feed = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: (v) => setState(() => search = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    hintText: 'Search meals for this day',
                    suffixIcon: search.isEmpty ? null : IconButton(onPressed: () => setState(() => search = ''), icon: const Icon(Icons.close_rounded, size: 18)),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        ['All meals', 'Breakfast', 'Lunch', 'Dinner', 'Snack']
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(
                                  right: KayleoSpacing.sm,
                                ),
                                child: ChoiceChip(
                                  label: Text(
                                    c,
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  selected: category == c,
                                  selectedColor: Theme.of(context)
                                      .extension<KayleoSurfaces>()!
                                      .soft,
                                  side: BorderSide(
                                    color: Theme.of(context)
                                        .extension<KayleoSurfaces>()!
                                        .border,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => category = c),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'All meals',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (meals.isEmpty)
                  Panel(
                    child: EmptyState(
                      icon: Icons.restaurant_outlined,
                      title: search.isNotEmpty || category != 'All meals'
                          ? 'No matching meals'
                          : 'A fresh page',
                      subtitle: search.isNotEmpty || category != 'All meals'
                          ? 'Try another meal name or choose All meals.'
                          : 'Nothing logged on ${DateFormat('d MMM').format(date)}. Start with one meal.',
                    ),
                  )
                else
                  for (final cat in [
                    'Breakfast',
                    'Lunch',
                    'Snack',
                    'Dinner',
                  ]) ...[
                    if (meals.any((m) => m.category == cat))
                      Panel(
                        padding: 16,
                        border: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  cat == 'Breakfast'
                                      ? Icons.wb_sunny_outlined
                                      : cat == 'Dinner'
                                      ? Icons.nights_stay_outlined
                                      : Icons.restaurant_outlined,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${number(meals.where((m) => m.category == cat).fold<double>(0, (s, m) => s + mealNutrition(m).calories))} kcal',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: KayleoSpacing.card),
                            for (final m in meals.where(
                              (m) => m.category == cat,
                            ))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: MealRow(meal: m, state: state),
                              ),
                          ],
                        ),
                      ),
                    if (meals.any((m) => m.category == cat))
                      const SizedBox(height: KayleoSpacing.lg),
                  ],
                if (meals.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: OutlinedButton.icon(
                      onPressed: () => showLogger(context, state, initialDate: date),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Forgot to log a meal that day? Do it now'),
                    ),
                  ),
              ],
            );
            return constraints.maxWidth > 850
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: feed),
                      const SizedBox(width: KayleoSpacing.xl),
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            WaterPanel(state: state, date: date),
                            const SizedBox(height: KayleoSpacing.page),
                            Tag(
                              '${meals.length} meals · ${n.protein.round()}g protein',
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      feed,
                      const SizedBox(height: KayleoSpacing.page),
                      WaterPanel(state: state, date: date),
                    ],
                  );
          },
        ),
      ],
    );
  }
}

class _DiaryOverview extends StatefulWidget {
  const _DiaryOverview({required this.state, required this.date, required this.nutrition});
  final AppState state;
  final DateTime date;
  final Nutrients nutrition;

  @override
  State<_DiaryOverview> createState() => _DiaryOverviewState();
}

class _DiaryOverviewState extends State<_DiaryOverview> {
  HealthActivityData activity = HealthActivityData.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DiaryOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (dateKey(oldWidget.date) != dateKey(widget.date)) _load();
  }

  Future<void> _load() async {
    final result = await HealthService.instance.fetchActivityData(widget.date, state: widget.state);
    if (mounted) setState(() => activity = result);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DashboardRingsSection(
    state: widget.state,
    date: widget.date,
    activity: activity,
    onConnectHealth: () {},
    onSelectHealthSource: () {},
    onSetStepGoal: () {},
  );
}

// Kept as a fallback reference for activity-only previews.
// ignore: unused_element
class _ActivityDayCard extends StatelessWidget {
  const _ActivityDayCard({required this.activity});
  final HealthActivityData activity;

  @override
  Widget build(BuildContext context) => Panel(
    padding: 18,
    border: false,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.directions_walk_rounded, color: context.kayleoPrimary),
        const SizedBox(width: 9),
        const Text('Activity for this day', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 18),
      Center(
        child: Column(
          children: [
            KayleoRing(
              size: 150,
              stroke: 12,
              progress: activity.steps / 10000,
              color: Colors.green,
              track: context.kayleoSurfaces.soft,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.directions_walk_rounded, size: 25, color: Colors.green),
                const SizedBox(height: 5),
                Text('${activity.steps}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                Text('steps', style: TextStyle(fontSize: 11, color: context.kayleoMuted)),
              ]),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _activityMetric(context, Icons.timer_outlined, '${activity.activeMinutes} min', 'Active time', activity.activeMinutes / 60, Colors.teal),
              _activityMetric(context, Icons.local_fire_department_outlined, '${activity.activeCalories}', 'Calories burned', activity.activeCalories / 500, Colors.deepOrange),
              _activityMetric(context, Icons.straighten_rounded, '${activity.motionKm.toStringAsFixed(1)} km', 'Distance', activity.motionKm / 5, Colors.cyan),
            ]),
          ],
        ),
      ),
    ]),
  );

  Widget _activityMetric(BuildContext context, IconData icon, String value, String label, double progress, Color color) => SizedBox(
    width: 96,
    child: Panel(
      padding: 12,
      child: Column(children: [
        KayleoRing(
          size: 52,
          stroke: 6,
          progress: progress,
          color: color,
          track: context.kayleoSurfaces.soft,
          highlight: false,
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 8),
        Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: context.kayleoMuted)),
      ]),
    ),
  );
}

class SavedMealsScreen extends StatefulWidget {
  const SavedMealsScreen({super.key, required this.state});
  final AppState state;
  @override
  State<SavedMealsScreen> createState() => _SavedMealsScreenState();
}

class _SavedMealsScreenState extends State<SavedMealsScreen> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final templates = widget.state.templates
        .where((m) => m.name.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageTitle(
          'Saved meals',
          'Your usuals, ready.',
          'Review portions and log a familiar meal.',
        ),
        TextField(
          onChanged: (v) => setState(() => search = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Find a saved meal…',
          ),
        ),
        const SizedBox(height: KayleoSpacing.xl),
        if (templates.isEmpty)
          Panel(
            child: EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'Save a meal for next time',
              subtitle: 'When you log a meal, turn on “Remember this as a usual meal.” It will be waiting here next time.',
              action: FilledButton(
                onPressed: () => showLogger(context, widget.state),
                child: Text('Log a meal'),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 20,
              runSpacing: 20,
              children: templates
                  .map(
                    (m) => SizedBox(
                      width: c.maxWidth > 900
                          ? (c.maxWidth - 40) / 3
                          : c.maxWidth > 600
                          ? (c.maxWidth - 20) / 2
                          : c.maxWidth,
                      child: Panel(
                        padding: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FoodPhoto(
                              image: m.image,
                              meal: m,
                              height: 170,
                              width: double.infinity,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text('Remove saved meal?'),
                                        content: Text(
                                          'Existing diary entries will stay in your log.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: Text('Keep'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text('Remove'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      widget.state.templates.removeWhere(
                                        (t) => t.id == m.id,
                                      );
                                      await widget.state.persist();
                                    }
                                  },
                                  tooltip: 'Remove saved meal',
                                  icon: Icon(
                                    Icons.bookmark_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '${number(mealNutrition(m).calories)} kcal  ·  ${mealNutrition(m).protein.round()}g protein',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: KayleoSpacing.page),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => showLogger(
                                  context,
                                  widget.state,
                                  meal: m.copy(
                                    id: newId(),
                                    time: DateTime.now(),
                                  ),
                                ),
                                icon: Icon(Icons.add_rounded, size: 17),
                                label: Text(
                                  'Review & log',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 26),
        Panel(
          color: Theme.of(context).extension<KayleoSurfaces>()!.soft,
          border: false,
          child: Row(
            children: [
              Icon(
                Icons.mic_none_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Try saying “same breakfast as yesterday.” Kayleo can bring that meal back for you to review.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    height: 1.7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
