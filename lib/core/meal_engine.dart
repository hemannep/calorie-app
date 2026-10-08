import '../data/models.dart';
import '../data/food_database.dart';

class Clarification {
  const Clarification(
    this.question,
    this.options,
    this.foodId, {
    this.portion = false,
    this.itemIndex,
  });
  final bool portion;
  final int? itemIndex;
  final String question, foodId;
  final List<String> options;
}

class MealAnalysis {
  MealAnalysis(this.meal, this.questions, {this.unmatched = false});
  final Meal meal;
  final List<Clarification> questions;
  final bool unmatched;
}

class MealEngine {
  static MealAnalysis parse(
    String description, {
    String input = 'Text',
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    var text = description
        .toLowerCase()
        .replaceAll('½', ' 1/2')
        .replaceAll('¼', ' 1/4')
        .replaceAll('¾', ' 3/4');
    text = text.replaceAllMapped(RegExp(r'(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)'), (
      m,
    ) {
      final denominator = int.parse(m[3]!);
      if (denominator == 0) return m[0]!;
      return (double.parse(m[1] ?? '0') + int.parse(m[2]!) / denominator)
          .toString();
    });
    const numberWords = {
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
      'ten': '10',
      'half': '0.5',
    };
    for (final e in numberWords.entries) {
      text = text.replaceAll(RegExp('\\b${e.key}\\b'), e.value);
    }
    final candidates = <({int start, int end, Food food})>[];
    for (final food in foods) {
      for (final alias in food.aliases) {
        for (final match in RegExp(
          '\\b${RegExp.escape(alias)}\\b',
        ).allMatches(text)) {
          candidates.add((start: match.start, end: match.end, food: food));
        }
      }
    }
    candidates.sort((a, b) => (b.end - b.start).compareTo(a.end - a.start));
    final selected = <({int start, int end, Food food})>[];
    for (final c in candidates) {
      if (!selected.any((s) => c.start < s.end && c.end > s.start)) {
        selected.add(c);
      }
    }
    selected.sort((a, b) => a.start.compareTo(b.start));
    final items = <MealItem>[];
    final explicit = <int>{};
    for (var i = 0; i < selected.length; i++) {
      final c = selected[i];
      final before = text.substring(i == 0 ? 0 : selected[i - 1].end, c.start);
      final after = text.substring(
        c.end,
        i + 1 < selected.length ? selected[i + 1].start : text.length,
      );
      final pattern = RegExp(
        r'(\d+(?:\.\d+)?)\s*(grams?|g\b|ounces?|oz\b|cups?|tablespoons?|tbsp|pieces?|eggs?|slices?)?(?:\s+of)?\s*$',
      );
      final amountBefore = pattern.firstMatch(
        before
            .replaceAll(
              RegExp(
                r'(?:home[- ]style|steamed|grilled|cooked|roasted|boiled|fried)\s*$',
              ),
              '',
            )
            .replaceAll(RegExp(r'\ba\s+$'), '1 '),
      );
      final amountAfter = RegExp(
        r'^\s*(?:with\s+)?(\d+(?:\.\d+)?)\s*(grams?|g\b|ounces?|oz\b|cups?|pieces?|slices?)',
      ).firstMatch(after);
      final m = amountBefore ?? amountAfter;
      var grams = c.food.servingGrams;
      if (m != null) {
        final quantity = double.tryParse(m.group(1)!) ?? 1;
        final unit = m.group(2) ?? '';
        grams = unit.startsWith('g')
            ? quantity
            : unit.startsWith('o')
            ? quantity * 28.3495
            : quantity * c.food.servingGrams;
        explicit.add(i);
      }
      if (c.food.id.contains('momo') && !explicit.contains(i)) {
        grams = 8 * 30;
      }
      items.add(MealItem(foodId: c.food.id, grams: grams.clamp(1, 3000)));
    }
    var date = text.contains('yesterday')
        ? DateTime(
            clock.year,
            clock.month,
            clock.day - 1,
            clock.hour,
            clock.minute,
          )
        : clock;
    final t = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b').firstMatch(text);
    if (t != null) {
      final h = int.parse(t.group(1)!);
      final min = int.tryParse(t.group(2) ?? '0') ?? 0;
      if (h >= 1 && h <= 12 && min < 60) {
        date = DateTime(
          date.year,
          date.month,
          date.day,
          h % 12 + (t.group(3) == 'pm' ? 12 : 0),
          min,
        );
      }
    }
    final category = text.contains('breakfast')
        ? 'Breakfast'
        : text.contains('lunch')
        ? 'Lunch'
        : text.contains('dinner')
        ? 'Dinner'
        : categoryForHour(date.hour);
    final questions = <Clarification>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index], food = foodById(items[index].foodId);
      if (explicit.contains(index)) continue;
      questions.add(
        Clarification(
          food.id == 'rice'
              ? 'About how much rice was on your plate?'
              : 'How much ${food.name.toLowerCase()} did you eat?',
          food.id == 'rice'
              ? ['1 cup', '1½ cups', '2 cups']
              : [
                  '${item.grams.round()} g',
                  '${(item.grams / 2).round()} g',
                  '${(item.grams * 1.5).round()} g',
                ],
          food.id,
          portion: true,
          itemIndex: index,
        ),
      );
    }
    if (items.any((i) => i.foodId == 'curry') &&
        !text.contains('home') &&
        !text.contains('restaurant')) {
      questions.add(
        const Clarification('How was the curry prepared?', [
          'Light / home-style',
          'Rich / restaurant-style',
        ], 'curry'),
      );
    }
    if (text.contains('restaurant') && items.any((i) => i.foodId == 'curry')) {
      items.add(
        MealItem(
          foodId: 'oil',
          grams: 10,
          portion: {
            'quantity': 10.0,
            'unit': 'g',
            'share': 1.0,
            'preparationEstimate': true,
          },
        ),
      );
    }
    final names = items
        .where((i) => i.foodId != 'oil')
        .map((i) => foodById(i.foodId).name)
        .toList();
    final meal = Meal(
      id: newId(),
      name: names.isEmpty ? 'My meal' : names.take(2).join(' + '),
      time: date,
      category: category,
      items: items,
      image: items.isEmpty ? 'bowl' : foodById(items.first.foodId).image,
      input: input,
      notes: description,
      assumptions: 'Generic foods and standard servings unless you specify quantities. Composite dishes use illustrative recipe values.',
    );
    return MealAnalysis(meal, questions, unmatched: items.isEmpty);
  }

  static void answer(Meal meal, Clarification question, int selection) {
    if (question.portion) {
      final item = meal.items[question.itemIndex!];
      final standard = mealItemFood(item).servingGrams;
      item.grams = item.foodId == 'rice'
          ? [158.0, 237.0, 316.0][selection]
          : [standard, standard / 2, standard * 1.5][selection];
      item.portion = {'quantity': item.grams, 'unit': 'g', 'share': 1.0};
    } else if (question.foodId == 'curry') {
      meal.items.removeWhere(
        (i) => i.foodId == 'oil' && i.portion?['preparationEstimate'] == true,
      );
      if (selection == 1 && !meal.items.any((i) => i.foodId == 'oil')) {
        meal.items.add(
          MealItem(
            foodId: 'oil',
            grams: 10,
            portion: {
              'quantity': 10.0,
              'unit': 'g',
              'share': 1.0,
              'preparationEstimate': true,
            },
          ),
        );
      }
    }
    meal.assumptions +=
        '\n${question.question} ${question.options[selection]}.';
  }

  static String categoryForHour(int hour) => hour < 11
      ? 'Breakfast'
      : hour < 16
      ? 'Lunch'
      : hour < 21
      ? 'Dinner'
      : 'Snack';
}
