import 'package:flutter/material.dart';

import '../core/meal_lookup.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../services/food_ai_service.dart';

/// A database candidate is never silently substituted for the user's dish.
class MealFoodMatch extends StatefulWidget {
  const MealFoodMatch({
    super.key,
    required this.request,
    required this.results,
  });
  final MealFoodRequest request;
  final FoodSearchResults results;
  @override
  State<MealFoodMatch> createState() => _MealFoodMatchState();
}

class _MealFoodMatchState extends State<MealFoodMatch> {
  FoodNutrition? selected;
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(
    text: widget.request.amount?.toString() ?? '',
  );
  final values = List.generate(5, (_) => TextEditingController());
  String? error;
  @override
  void dispose() {
    amount.dispose();
    for (final controller in values) {
      controller.dispose();
    }
    super.dispose();
  }

  void choose(FoodNutrition food) {
    setState(() {
      selected = food;
      error = null;
      for (var i = 0; i < values.length; i++) {
        values[i].text = food.values[i]?.toString() ?? '';
      }
      if (widget.request.amount != null && widget.request.unit != food.unit) {
        amount.clear(); // Never treat ml as grams without a density.
      }
    });
  }

  void confirm() {
    if (selected == null || !form.currentState!.validate()) return;
    final numbers = values.map((c) => double.tryParse(c.text)).toList();
    final food = selected!.toFood(numbers);
    final snapshot = Food(
      id: food.id,
      name: food.name,
      aliases: food.aliases,
      per100g: food.per100g,
      servingGrams: food.servingGrams,
      unit: food.unit,
      nutritionBasisUnit: food.nutritionBasisUnit,
      source:
          food.source +
          (selected!.complete ? '' : ' · label values completed by you'),
      sourceUrl: food.sourceUrl,
      barcode: food.barcode,
    );
    Navigator.pop(
      context,
      MealItem(
        foodId: snapshot.id,
        grams: double.parse(amount.text),
        snapshot: snapshot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: 'Match your food',
    subtitle: widget.request.description,
    footer: selected == null
        ? null
        : FilledButton(onPressed: confirm, child: const Text('Use this food')),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Results from the food databases. Choose the recipe or product you ate; similar names can have different nutrition.',
          ),
          if (widget.results.unavailableSources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${widget.results.unavailableSources.join(' and ')} could not be reached. Available results are shown.',
              ),
            ),
          if (selected == null)
            for (final food in widget.results.foods)
              ListTile(
                title: Text(food.name),
                subtitle: Text(
                  '${food.source}\n${food.values[0] == null ? 'Calories missing' : '${number(food.values[0]!)} kcal per 100 ${food.unit}'}${food.complete ? '' : ' · complete missing label values'}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => choose(food),
              )
          else ...[
            const SizedBox(height: 16),
            Text(selected!.name, style: Theme.of(context).textTheme.titleLarge),
            Text(selected!.source),
            TextButton(
              onPressed: () => setState(() => selected = null),
              child: const Text('Choose another match'),
            ),
            TextFormField(
              key: const Key('matched-food-amount'),
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount eaten (${selected!.unit})',
                helperText: 'Enter the total you ate. Piece counts need a measured weight.',
              ),
              onChanged: (_) => setState(() {}),
              validator: (text) {
                final n = double.tryParse(text ?? '');
                return n == null || !n.isFinite || n < 1 || n > 3000
                    ? 'Enter an amount from 1 to 3,000'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            Text('Nutrition per 100 ${selected!.unit}'),
            for (var i = 0; i < values.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextFormField(
                  controller: values[i],
                  readOnly: selected!.values[i] != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: const [
                      'Calories (kcal)',
                      'Protein (g)',
                      'Carbohydrates (g)',
                      'Fat (g)',
                      'Fiber (g, optional)',
                    ][i],
                  ),
                  validator: (text) {
                    if (i == 4 && (text ?? '').trim().isEmpty) return null;
                    final n = double.tryParse(text ?? '');
                    return n == null ||
                            !n.isFinite ||
                            n < 0 ||
                            n > (i == 0 ? 1200 : 100)
                        ? 'Enter a valid label value'
                        : null;
                  },
                ),
              ),
            if (!selected!.complete)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'This record has missing nutrients. Complete them from a label, or choose another match.',
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ],
      ),
    ),
  );
}
