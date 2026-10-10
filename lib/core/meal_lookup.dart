import '../data/food_database.dart';
import '../data/models.dart';
import 'meal_engine.dart';

class MealFoodRequest {
  const MealFoodRequest(this.description, this.query, this.amount, this.unit);
  final String description, query;
  final double? amount;
  final String unit;
}

class MealLookupPlan {
  const MealLookupPlan(this.analysis, this.requests);
  final MealAnalysis analysis;
  final List<MealFoodRequest> requests;
  static final _knownAliases = foods.expand((food) => food.aliases).toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  static MealLookupPlan parse(
    String description, {
    required DateTime now,
    required String input,
  }) {
    if (description.length > 1000) {
      throw const FormatException(
        'Please describe up to eight foods in 1,000 characters.',
      );
    }
    final original = MealEngine.parse(description, now: now, input: input);
    var splitText = description.toLowerCase();
    // Keep a known dish such as "biryani with chicken" together while still
    // splitting "rice with curry" into two foods.
    for (final alias in _knownAliases.where((a) => a.contains(' with '))) {
      splitText = splitText.replaceAll(
        alias,
        alias.replaceAll(' with ', ' _with_ '),
      );
    }
    final clauses = splitText
        .split(RegExp(r'\s+(?:and|with|plus)\s+|[,;&+]'))
        .map((clause) => clause.replaceAll(' _with_ ', ' with '))
        .toList();
    if (clauses.length > 8) {
      throw const FormatException('Please log up to eight foods at a time.');
    }
    final requests = <MealFoodRequest>[];
    final items = <MealItem>[];
    final questions = <Clarification>[];
    for (final clause in clauses) {
      var query = clause
          .replaceAll(RegExp(r'\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b'), '')
          .replaceAll(
            RegExp(
              r'\b(?:i|had|have|ate|eaten|eat|just|for|my|a|an|the|some|about|around|roughly|approximately|of|at|today|yesterday|breakfast|lunch|dinner|snack)\b',
            ),
            '',
          )
          .trim();
      const numbers = {
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
      for (final entry in numbers.entries) {
        query = query.replaceAll(RegExp('\\b${entry.key}\\b'), entry.value);
      }
      query = query
          .replaceAll('½', ' 1/2')
          .replaceAll('¼', ' 1/4')
          .replaceAll('¾', ' 3/4');
      query = query.replaceAllMapped(
        RegExp(r'(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)'),
        (m) {
          final denominator = int.parse(m[3]!);
          if (denominator == 0) return m[0]!;
          return (double.parse(m[1] ?? '0') + int.parse(m[2]!) / denominator)
              .toString();
        },
      );
      final mass = RegExp(
        r'\b(\d+(?:\.\d+)?)\s*(grams?|g\b|ounces?|oz\b|milliliters?|ml\b)\b',
      ).firstMatch(query);
      double? amount;
      var unit = 'g';
      if (mass != null) {
        amount = double.parse(mass[1]!);
        if (mass[2]!.startsWith('o')) amount *= 28.3495;
        if (mass[2]!.startsWith('m')) unit = 'ml';
        if (amount < 1 || amount > 3000) {
          throw const FormatException(
            'Enter a measured amount from 1 to 3,000 g or ml.',
          );
        }
      }
      query = query
          .replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), '')
          .replaceAll(
            RegExp(
              r'\b(?:grams?|g|ounces?|oz|milliliters?|ml|cups?|pieces?|servings?|slices?|bowls?|plates?|tablespoons?|tbsp)\b',
            ),
            '',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (query.isEmpty) continue;
      var residual = query;
      for (final alias in _knownAliases) {
        residual = residual.replaceAll(
          RegExp('\\b${RegExp.escape(alias)}\\b'),
          '',
        );
      }
      residual = residual
          .replaceAll(
            RegExp(
              r'\b(?:home|style|home-style|restaurant|restaurant-style|steamed|grilled|cooked|roasted|boiled|fried|light|rich)\b',
            ),
            '',
          )
          .replaceAll('-', '')
          .trim();
      if (residual.isNotEmpty) {
        if (query.length > 100) {
          throw const FormatException(
            'Use a shorter food name (up to 100 characters).',
          );
        }
        requests.add(MealFoodRequest(clause.trim(), query, amount, unit));
        continue;
      }
      final parsed = MealEngine.parse(clause, now: now, input: input);
      final offset = items.length;
      items.addAll(parsed.meal.items);
      questions.addAll(
        parsed.questions.map(
          (q) => Clarification(
            q.question,
            q.options,
            q.foodId,
            portion: q.portion,
            itemIndex: q.itemIndex == null ? null : q.itemIndex! + offset,
          ),
        ),
      );
    }
    if (requests.isEmpty) return MealLookupPlan(original, requests);
    original.meal.items = items;
    return MealLookupPlan(MealAnalysis(original.meal, questions), requests);
  }
}
