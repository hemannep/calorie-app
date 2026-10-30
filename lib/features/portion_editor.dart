import 'package:flutter/material.dart';

import '../core/ui.dart';
import '../data/models.dart';
import '../data/food_database.dart';

double? portionNumber(String text) {
  final value = text
      .trim()
      .replaceAll('½', ' 1/2')
      .replaceAll('¼', ' 1/4')
      .replaceAll('¾', ' 3/4')
      .trim();
  final match = RegExp(r'^(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)$').firstMatch(value);
  final number = match == null
      ? double.tryParse(value)
      : double.parse(match[1] ?? '0') +
            double.parse(match[2]!) / double.parse(match[3]!);
  return number != null && number.isFinite && number > 0 && number <= 100000
      ? number
      : null;
}

String formatPortionQuantity(double value) {
  if (!value.isFinite) return '1';
  final roundedInt = value.roundToDouble();
  if ((value - roundedInt).abs() < 0.01) {
    return roundedInt.toInt().toString();
  }
  final oneDec = (value * 10).round() / 10;
  if ((value - oneDec).abs() < 0.04) {
    return oneDec.toStringAsFixed(1);
  }
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

List<String> portionUnits(Food food) => food.nutritionBasisUnit == 'ml'
    ? {
        food.nutritionBasisUnit,
        'US fl oz',
        food.unit,
        'cup',
        'glass',
        'serving',
        'tbsp',
      }.toList()
    : {
        food.nutritionBasisUnit,
        'oz',
        food.unit,
        'piece',
        'serving',
        'bowl',
        'cup',
        'slice',
        'tbsp',
      }.toList();

double portionFactor(Food food, String unit) {
  if (unit == food.nutritionBasisUnit || unit == 'g' || unit == 'ml') {
    return 1;
  }
  if (unit == 'oz') return 28.3495;
  if (unit == 'US fl oz') return 29.5735295625;
  if (unit == food.unit) return food.servingGrams;
  switch (unit) {
    case 'piece':
      return food.servingGrams >= 15 && food.servingGrams <= 180
          ? food.servingGrams
          : 60;
    case 'serving':
      return food.servingGrams > 0 && food.servingGrams != 100
          ? food.servingGrams
          : 150;
    case 'bowl':
      return food.servingGrams >= 180 && food.servingGrams <= 400
          ? food.servingGrams
          : 250;
    case 'cup':
      return food.nutritionBasisUnit == 'ml' ? 240 : 160;
    case 'glass':
      return 240;
    case 'slice':
      return 40;
    case 'plate':
      return 350;
    case 'tbsp':
    case 'tablespoon':
      return 15;
    default:
      throw const FormatException('Unsupported unit');
  }
}

double portionStepForUnit(String unit) {
  switch (unit) {
    case 'g':
    case 'ml':
      return 25;
    case 'cup':
    case 'bowl':
    case 'serving':
    case 'glass':
    case 'plate':
      return 0.5;
    default:
      return 1;
  }
}

double consumedPortion(Food food, Map<String, dynamic> portion) {
  final quantity = (portion['quantity'] as num).toDouble(),
      share = (portion['share'] as num? ?? 1).toDouble();
  final amount = quantity * portionFactor(food, portion['unit']) * share;
  if (!quantity.isFinite ||
      quantity <= 0 ||
      quantity > 100000 ||
      !share.isFinite ||
      share <= 0 ||
      share > 1 ||
      !amount.isFinite ||
      amount < 1 ||
      amount > 3000) {
    throw const FormatException(
      'Enter a valid amount and share (1–3,000 eaten).',
    );
  }
  return amount;
}

Future<Map<String, dynamic>?> editPortion(
  BuildContext context,
  MealItem item,
) => openSheet<Map<String, dynamic>>(context, PortionEditor(item: item));

class PortionEditor extends StatefulWidget {
  const PortionEditor({super.key, required this.item});
  final MealItem item;
  @override
  State<PortionEditor> createState() => _PortionEditorState();
}

class _PortionEditorState extends State<PortionEditor> {
  late final food = mealItemFood(widget.item);
  late String unit = widget.item.portion?['unit'] ?? food.nutritionBasisUnit;
  late final amount = TextEditingController(
    text: formatPortionQuantity(
      ((widget.item.portion?['quantity'] ?? widget.item.grams) as num)
          .toDouble(),
    ),
  );
  late final fraction = TextEditingController(
    text: (widget.item.portion?['share'] ?? .5).toString(),
  );
  late bool shared = ((widget.item.portion?['share'] ?? 1) as num) < 1;
  String? error;

  @override
  void dispose() {
    amount.dispose();
    fraction.dispose();
    super.dispose();
  }

  void _stepQuantity(double delta) {
    final current = portionNumber(amount.text) ?? 1.0;
    final step = portionStepForUnit(unit);
    final next = (current + delta * step).clamp(
      step == 25 ? 10.0 : 0.25,
      3000.0,
    );
    setState(() {
      amount.text = formatPortionQuantity(next);
      error = null;
    });
  }

  Map<String, dynamic>? get candidate {
    final q = portionNumber(amount.text),
        share = shared ? portionNumber(fraction.text) : 1.0;
    return q == null || share == null
        ? null
        : {'quantity': q, 'unit': unit, 'share': share};
  }

  void save() {
    try {
      final p = candidate;
      if (p == null) {
        throw const FormatException(
          'Enter a positive amount and a share such as 1/2.',
        );
      }
      consumedPortion(food, p);
      Navigator.pop(context, p);
    } catch (e) {
      setState(
        () => error = e.toString().replaceFirst('FormatException: ', ''),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final currentCandidate = candidate;
    double? previewGrams;
    if (currentCandidate != null) {
      try {
        previewGrams = consumedPortion(food, currentCandidate);
      } catch (_) {}
    }
    final previewCalories = previewGrams == null
        ? null
        : (food.per100g.calories * previewGrams / 100).round();

    return SheetFrame(
      title: 'Your portion',
      subtitle: food.name,
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: dark ? lime : forest,
            foregroundColor: dark ? forest : Colors.white,
          ),
          onPressed: save,
          child: const LocalizedText('Update portion'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (previewGrams != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.kayleoSurfaces.soft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.kayleoSurfaces.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.scale_outlined,
                    size: 18,
                    color: context.kayleoPrimary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LocalizedText(
                      'Logging ${previewGrams.round()} ${food.nutritionBasisUnit}'
                      '${previewCalories != null ? ' · $previewCalories kcal' : ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (shared) Tag('Shared', color: lime, textColor: forest),
                ],
              ),
            ),
          Row(
            children: [
              IconButton.outlined(
                tooltip: context.l10n.translate('Decrease amount'),
                onPressed: () => _stepQuantity(-1),
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('portion-quantity'),
                  controller: amount,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    labelText: context.l10n.translate(
                      shared ? 'Shared dish amount' : 'Amount eaten',
                    ),
                    hintText: context.l10n.translate('150 or 1/2'),
                    suffixText: unit,
                  ),
                  onChanged: (_) => setState(() => error = null),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: context.l10n.translate('Increase amount'),
                onPressed: () => _stepQuantity(1),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const LocalizedText(
            'Unit',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in portionUnits(food))
                ChoiceChip(
                  label: LocalizedText(value),
                  selected: unit == value,
                  onSelected: (_) => setState(() {
                    final q = portionNumber(amount.text);
                    if (q != null) {
                      final converted =
                          q *
                          portionFactor(food, unit) /
                          portionFactor(food, value);
                      amount.text = formatPortionQuantity(converted);
                    }
                    unit = value;
                    error = null;
                  }),
                ),
            ],
          ),
          if (unit != food.nutritionBasisUnit)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LocalizedText(
                '1 $unit ≈ ${portionFactor(food, unit).round()} ${food.nutritionBasisUnit}. Serving conversions are estimates.',
                style: TextStyle(fontSize: 12, color: context.kayleoMuted),
              ),
            ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const LocalizedText(
              'Shared dish total',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const LocalizedText(
              'Splitting with friends or family? Only count the share you ate.',
            ),
            value: shared,
            onChanged: (v) => setState(() => shared = v),
          ),
          if (shared) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in const [
                  ('1/2', '2 people (1/2)'),
                  ('1/3', '3 people (1/3)'),
                  ('1/4', '4 people (1/4)'),
                  ('2/3', '2/3 share'),
                  ('3/4', '3/4 share'),
                ])
                  ChoiceChip(
                    label: LocalizedText(preset.$2),
                    selected: fraction.text.trim() == preset.$1,
                    onSelected: (_) => setState(() {
                      fraction.text = preset.$1;
                      error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('portion-share'),
              controller: fraction,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: context.l10n.translate('Fraction you ate'),
                hintText: context.l10n.translate('1/4 or 0.25'),
              ),
              onChanged: (_) => setState(() => error = null),
            ),
            const SizedBox(height: 10),
            LocalizedText(
              'For four equal servings, enter 1/4. For half the dish, enter 1/2.',
              style: TextStyle(fontSize: 12, color: context.kayleoMuted),
            ),
          ],
          const SizedBox(height: 16),
          if (error != null)
            LocalizedText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
