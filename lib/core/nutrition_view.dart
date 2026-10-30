import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'ui.dart';

enum NutritionMetric {
  calories,
  protein,
  carbs,
  fats;

  String get label => switch (this) {
    calories => 'Calories',
    protein => 'Protein',
    carbs => 'Carbs',
    fats => 'Fats',
  };

  String get unit => this == calories ? 'kcal' : 'g';

  Color get color => switch (this) {
    calories => forest,
    protein => KayleoColors.protein,
    carbs => KayleoColors.carbs,
    fats => KayleoColors.fat,
  };

  IconData get icon => switch (this) {
    calories => Icons.local_fire_department_outlined,
    protein => Icons.restaurant_outlined,
    carbs => Icons.grain_rounded,
    fats => Icons.water_drop_outlined,
  };

  double amount(Nutrients nutrition) => switch (this) {
    calories => nutrition.calories,
    protein => nutrition.protein,
    carbs => nutrition.carbs,
    fats => nutrition.fat,
  };

  int target(BodyProfile profile) => switch (this) {
    calories => profile.calorieTarget,
    protein => profile.proteinTarget,
    carbs => profile.carbTarget,
    fats => profile.fatTarget,
  };
}

/// Intake and daily target remain visible even when the visual bar is full.
class NutrientProgressRow extends StatelessWidget {
  const NutrientProgressRow({
    super.key,
    required this.metric,
    required this.amount,
    required this.target,
    this.compact = false,
  });

  final NutritionMetric metric;
  final double amount;
  final int target;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${metric.label}: ${number(amount)} ${metric.unit} of $target ${metric.unit} daily target',
    excludeSemantics: true,
    child: Column(
      children: [
        Row(
          children: [
            if (!compact) ...[
              Icon(metric.icon, color: metric.color, size: 17),
              const SizedBox(width: KayleoSpacing.sm),
            ],
            Expanded(
              child: LocalizedText(
                metric.label,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            LocalizedText(
              '${number(amount)} / ${number(target)} ${metric.unit}',
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: context.kayleoMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 5 : 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            key: Key('daily-${metric.name}-progress'),
            value: (amount / math.max(target, 1)).clamp(0, 1),
            minHeight: compact ? 4 : 7,
            color: metric.color,
            backgroundColor: context.kayleoSurfaces.soft,
          ),
        ),
      ],
    ),
  );
}
