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

List<String> portionUnits(Food food) => {
  food.nutritionBasisUnit,
  food.nutritionBasisUnit == 'ml' ? 'US fl oz' : 'oz',
  food.unit,
}.toList();
double portionFactor(Food food, String unit) => unit == food.nutritionBasisUnit
    ? 1
    : unit == 'oz'
    ? 28.3495
    : unit == 'US fl oz'
    ? 29.5735295625
    : unit == food.unit
    ? food.servingGrams
    : throw const FormatException('Unsupported unit');
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
    text: (widget.item.portion?['quantity'] ?? widget.item.grams).toString(),
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
  Widget build(BuildContext context) => SheetFrame(
    title: 'Your portion',
    subtitle: food.name,
    footer: FilledButton(onPressed: save, child: const Text('Update portion')),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('portion-quantity'),
          controller: amount,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: shared ? 'Shared dish amount' : 'Amount eaten',
            hintText: '150 or 1/2',
          ),
          onChanged: (_) => setState(() => {}),
        ),
        const SizedBox(height: 16),
        const Text('Unit'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in portionUnits(food))
              ChoiceChip(
                label: Text(value),
                selected: unit == value,
                onSelected: (_) => setState(() {
                  final q = portionNumber(amount.text);
                  if (q != null) {
                    amount.text =
                        (q *
                                portionFactor(food, unit) /
                                portionFactor(food, value))
                            .toString();
                  }
                  unit = value;
                }),
              ),
          ],
        ),
        if (food.unit != food.nutritionBasisUnit)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '1 ${food.unit} ≈ ${food.servingGrams} ${food.nutritionBasisUnit}. Serving conversions are estimates. Use a measured amount when possible.',
              style: TextStyle(fontSize: 12, color: context.kayleoMuted),
            ),
          ),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Shared dish total'),
          subtitle: const Text('Only count the share you ate.'),
          value: shared,
          onChanged: (v) => setState(() => shared = v),
        ),
        if (shared) ...[
          TextField(
            key: const Key('portion-share'),
            controller: fraction,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Fraction you ate',
              hintText: '1/4 or 0.25',
            ),
            onChanged: (_) => setState(() => {}),
          ),
          const SizedBox(height: 10),
          const Text(
            'For four equal servings, enter 1/4. For half the dish, enter 1/2.',
          ),
        ],
        const SizedBox(height: 16),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
