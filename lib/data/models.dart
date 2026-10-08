import 'dart:convert';
import 'dart:typed_data';

class Nutrients {
  const Nutrients(
    this.calories,
    this.protein,
    this.carbs,
    this.fat, [
    this.fiber,
  ]);
  final double calories, protein, carbs, fat;
  final double? fiber;
  Nutrients operator +(Nutrients other) => Nutrients(
    calories + other.calories,
    protein + other.protein,
    carbs + other.carbs,
    fat + other.fat,
    fiber == null || other.fiber == null ? null : fiber! + other.fiber!,
  );
  Nutrients scaled(double factor) => Nutrients(
    calories * factor,
    protein * factor,
    carbs * factor,
    fat * factor,
    fiber == null ? null : fiber! * factor,
  );
  static const zero = Nutrients(0, 0, 0, 0, 0);
}

class Food {
  const Food({
    required this.id,
    required this.name,
    required this.aliases,
    required this.per100g,
    required this.servingGrams,
    required this.unit,
    this.source = 'Prototype recipe estimate',
    this.image = 'bowl',
    this.category = 'Meals',
    this.sourceUrl = '',
    this.barcode = '',
    this.nutritionBasisUnit = 'g',
  });
  final String id, name, unit, source, image, category;
  final List<String> aliases;
  final Nutrients per100g;
  final double servingGrams;
  final String sourceUrl, barcode, nutritionBasisUnit;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'aliases': aliases,
    'servingGrams': servingGrams,
    'unit': unit,
    'source': source,
    'sourceUrl': sourceUrl,
    'barcode': barcode,
    'nutritionBasisUnit': nutritionBasisUnit,
    'image': image,
    'category': category,
    'nutrients': [
      per100g.calories,
      per100g.protein,
      per100g.carbs,
      per100g.fat,
      per100g.fiber,
    ],
  };
  factory Food.fromJson(Map<String, dynamic> j) {
    final n = j['nutrients'] as List;
    for (final value in n.take(4)) {
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('Invalid nutrition');
      }
    }
    return Food(
      id: j['id'],
      name: j['name'],
      aliases: List<String>.from(j['aliases'] ?? []),
      per100g: Nutrients(
        (n[0] as num).toDouble(),
        (n[1] as num).toDouble(),
        (n[2] as num).toDouble(),
        (n[3] as num).toDouble(),
        n.length > 4 && n[4] != null ? (n[4] as num).toDouble() : null,
      ),
      servingGrams: (j['servingGrams'] as num).toDouble(),
      unit: j['unit'],
      source: j['source'],
      sourceUrl: j['sourceUrl'] ?? '',
      barcode: j['barcode'] ?? '',
      nutritionBasisUnit: j['nutritionBasisUnit'] ?? 'g',
      image: j['image'] ?? 'bowl',
      category: j['category'] ?? 'Meals',
    );
  }
}

class MealItem {
  MealItem({
    required this.foodId,
    required this._grams,
    this.snapshot,
    this.portion,
  });
  String foodId;
  double _grams;
  double get grams => _grams;
  set grams(double value) {
    _grams = value;
    portion = null;
  }

  Food? snapshot;
  Map<String, dynamic>? portion;
  MealItem copy() => MealItem(
    foodId: foodId,
    grams: grams,
    snapshot: snapshot,
    portion: portion == null ? null : Map.of(portion!),
  );
  Map<String, dynamic> toJson() => {
    'foodId': foodId,
    'grams': grams,
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (portion != null) 'portion': portion,
  };
  factory MealItem.fromJson(Map<String, dynamic> j) => MealItem(
    foodId: j['foodId'] as String,
    grams: (j['grams'] as num).toDouble(),
    snapshot: j['snapshot'] == null
        ? null
        : Food.fromJson(Map<String, dynamic>.from(j['snapshot'])),
    portion: j['portion'] == null
        ? null
        : Map<String, dynamic>.from(j['portion']),
  );
}

class Meal {
  Meal({
    required this.id,
    required this.name,
    required this.time,
    required this.category,
    required this.items,
    this.image = 'bowl',
    this.photo,
    this.input = 'Manual',
    this.notes = '',
    this.assumptions = '',
    this.manual,
  });
  final String id;
  String name, category, image, input, notes, assumptions;
  DateTime time;
  List<MealItem> items;
  Uint8List? photo;
  Nutrients? manual;
  Meal copy({String? id, DateTime? time}) => Meal(
    id: id ?? this.id,
    name: name,
    time: time ?? this.time,
    category: category,
    items: items.map((i) => i.copy()).toList(),
    image: image,
    photo: photo,
    input: input,
    notes: notes,
    assumptions: assumptions,
    manual: manual,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'time': time.toIso8601String(),
    'category': category,
    'items': items.map((i) => i.toJson()).toList(),
    'image': image,
    'photo': photo == null ? null : base64Encode(photo!),
    'input': input,
    'notes': notes,
    'assumptions': assumptions,
    'manual': manual == null
        ? null
        : [
            manual!.calories,
            manual!.protein,
            manual!.carbs,
            manual!.fat,
            manual!.fiber,
          ],
  };
  factory Meal.fromJson(Map<String, dynamic> j) => Meal(
    id: j['id'],
    name: j['name'],
    time: DateTime.parse(j['time']),
    category: j['category'],
    items: (j['items'] as List)
        .map((i) => MealItem.fromJson(Map<String, dynamic>.from(i)))
        .toList(),
    image: j['image'] ?? 'bowl',
    photo: j['photo'] == null ? null : base64Decode(j['photo']),
    input: j['input'] ?? 'Manual',
    notes: j['notes'] ?? '',
    assumptions: j['assumptions'] ?? '',
    manual: j['manual'] == null
        ? null
        : Nutrients(
            (j['manual'][0] as num).toDouble(),
            (j['manual'][1] as num).toDouble(),
            (j['manual'][2] as num).toDouble(),
            (j['manual'][3] as num).toDouble(),
            (j['manual'] as List).length > 4 && j['manual'][4] != null
                ? (j['manual'][4] as num).toDouble()
                : null,
          ),
  );
}

class BodyProfile {
  BodyProfile({
    this.name = 'Alex',
    this.age = 28,
    this.height = 172,
    this.weight = 70,
    this.sex = 'Prefer not to say',
    this.activity = 'Lightly active',
    this.goal = 'Feel healthier',
    this.diet = 'Everything',
    this.calorieTarget = 2200,
    this.proteinTarget = 120,
    this.carbTarget = 275,
    this.fatTarget = 65,
    this.waterTarget = 2000,
    this.units = 'Metric',
  });
  String name, sex, activity, goal, diet, units;
  int age, calorieTarget, proteinTarget, carbTarget, fatTarget, waterTarget;
  double height, weight;
  int get maintenance {
    final offset = sex == 'Male'
        ? 5
        : sex == 'Female'
        ? -161
        : -78;
    final factor =
        {
          'Mostly sitting': 1.2,
          'Lightly active': 1.375,
          'Moderately active': 1.55,
          'Very active': 1.725,
        }[activity] ??
        1.375;
    return ((10 * weight + 6.25 * height - 5 * age + offset) * factor).round();
  }

  void calculateTargets() {
    final adjustment = goal == 'Lose weight'
        ? -250
        : goal == 'Build muscle'
        ? 250
        : 0;
    calorieTarget = (maintenance + adjustment).clamp(1500, 4500);
    proteinTarget = (weight * (goal == 'Build muscle' ? 1.8 : 1.6)).round();
    fatTarget = (calorieTarget * .28 / 9).round();
    carbTarget = ((calorieTarget - proteinTarget * 4 - fatTarget * 9) / 4)
        .round();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'height': height,
    'weight': weight,
    'sex': sex,
    'activity': activity,
    'goal': goal,
    'diet': diet,
    'calorieTarget': calorieTarget,
    'proteinTarget': proteinTarget,
    'carbTarget': carbTarget,
    'fatTarget': fatTarget,
    'waterTarget': waterTarget,
    'units': units,
  };
  factory BodyProfile.fromJson(Map<String, dynamic> j) => BodyProfile(
    name: j['name'] ?? 'Alex',
    age: j['age'] ?? 28,
    height: (j['height'] ?? 172).toDouble(),
    weight: (j['weight'] ?? 70).toDouble(),
    sex: j['sex'] ?? 'Prefer not to say',
    activity: j['activity'] ?? 'Lightly active',
    goal: j['goal'] ?? 'Feel healthier',
    diet: j['diet'] ?? 'Everything',
    calorieTarget: j['calorieTarget'] ?? 2200,
    proteinTarget: j['proteinTarget'] ?? 120,
    carbTarget: j['carbTarget'] ?? 275,
    fatTarget: j['fatTarget'] ?? 65,
    waterTarget: j['waterTarget'] ?? 2000,
    units: j['units'] ?? 'Metric',
  );
}

class WeightEntry {
  WeightEntry(this.date, this.kg);
  final DateTime date;
  final double kg;
  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'kg': kg};
  factory WeightEntry.fromJson(Map<String, dynamic> j) =>
      WeightEntry(DateTime.parse(j['date']), (j['kg'] as num).toDouble());
}

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

class DrinkEntry {
  DrinkEntry({required this.id, required this.time, required this.ml});
  final String id;
  final DateTime time;
  final int ml;
  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time.toIso8601String(),
    'ml': ml,
  };
  factory DrinkEntry.fromJson(Map<String, dynamic> j) {
    final ml = j['ml'];
    if (ml is! int || ml < 1 || ml > 10000) {
      throw const FormatException('Invalid hydration entry');
    }
    return DrinkEntry(
      id: j['id'] as String,
      time: DateTime.parse(j['time']),
      ml: ml,
    );
  }
}
