import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/food_database.dart';

class AppState extends ChangeNotifier {
  // Keep these legacy keys stable so the Kayleo rebrand preserves existing logs.
  static const storageKey = 'nouri_state_v1';
  static const recoveryKey = 'nouri_recovery_backup_v1';
  AppState(this.storage, {this.recordKey = storageKey});
  final String recordKey;
  String? accountEmail;
  bool signedOut = false;
  bool _disposed = false;
  String get backupKey =>
      recordKey == storageKey ? recoveryKey : "${recordKey}_recovery";
  void markSignedOut() {
    signedOut = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  final SharedPreferences storage;
  BodyProfile profile = BodyProfile();
  bool onboarded = false, demo = false, premium = false, community = false;
  String? storageError;
  String appearance = 'light';
  List<Meal> meals = [], templates = [];
  List<WeightEntry> weights = [];
  Map<String, int> water = {};
  List<DrinkEntry> drinks = [];
  Map<String, int> activityMinutes = {};
  Set<String> joined = {}, liked = {};
  Set<String> hiddenPosts = {};
  List<Map<String, dynamic>> communityPosts = [];
  Map<String, List<String>> comments = {};
  Map<String, bool> preferences = {
    'Meal reminders': true,
    'Hydration reminders': false,
    'Weekly review': true,
    'Quiet hours': true,
    'Keep meal photos': true,
    'Improve recognition': false,
  };
  Future<void> _pendingWrite = Future.value();

  static Future<AppState> load({String recordKey = storageKey}) async {
    final storage = await SharedPreferences.getInstance();
    final state = AppState(storage, recordKey: recordKey);
    final raw = storage.getString(recordKey);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        state.profile = BodyProfile.fromJson(j['profile']);
        state.accountEmail = j['accountEmail'];
        state.onboarded = j['onboarded'] ?? false;
        state.demo = j['demo'] ?? false;
        state.premium = j['premium'] ?? false;
        state.community = j['community'] ?? false;
        final savedAppearance = j['appearance'];
        if (['light', 'dark', 'system'].contains(savedAppearance)) {
          state.appearance = savedAppearance as String;
        }
        state.meals = (j['meals'] as List)
            .map((m) => Meal.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        state.templates = (j['templates'] as List)
            .map((m) => Meal.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        state.weights = (j['weights'] as List)
            .map((w) => WeightEntry.fromJson(Map<String, dynamic>.from(w)))
            .toList();
        state.water = Map<String, int>.from(j['water'] ?? {});
        if (j['drinks'] is List) {
          state.drinks = (j['drinks'] as List)
              .map((e) => DrinkEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (state.drinks.map((e) => e.id).toSet().length !=
              state.drinks.length) {
            throw const FormatException('Duplicate hydration IDs');
          }
          state._syncWater();
        } else {
          for (final e in state.water.entries) {
            if (e.value < 0 || e.value > 10000) {
              throw const FormatException('Invalid hydration total');
            }
            if (e.value > 0) {
              state.drinks.add(
                DrinkEntry(
                  id: 'legacy-${e.key}',
                  time: DateTime.parse('${e.key}T12:00:00'),
                  ml: e.value,
                ),
              );
            }
          }
        }
        final p = state.profile;
        if (!p.height.isFinite ||
            p.height < 80 ||
            p.height > 250 ||
            !p.weight.isFinite ||
            p.weight < 20 ||
            p.weight > 400 ||
            p.age < 13 ||
            p.age > 120 ||
            p.calorieTarget < 1 ||
            p.waterTarget < 1 ||
            p.proteinTarget < 1 ||
            p.carbTarget < 1 ||
            p.fatTarget < 1) {
          throw const FormatException('Invalid profile');
        }
        for (final meal in [...state.meals, ...state.templates]) {
          state._validateMeal(meal);
        }

        state.activityMinutes = Map<String, int>.from(
          j['activityMinutes'] ?? {},
        );
        state.joined = Set<String>.from(j['joined'] ?? []);
        state.liked = Set<String>.from(j['liked'] ?? []);
        state.hiddenPosts = Set<String>.from(j['hiddenPosts'] ?? []);
        state.communityPosts = (j['communityPosts'] as List? ?? [])
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        state.comments = (j['comments'] as Map? ?? {}).map(
          (k, v) => MapEntry(k.toString(), List<String>.from(v)),
        );
        state.preferences.addAll(
          Map<String, bool>.from(j['preferences'] ?? {}),
        );
      } catch (_) {
        await storage.setString(state.backupKey, raw);
        state.dispose();
        final clean = AppState(storage, recordKey: recordKey);
        clean.storageError = 'Your saved data could not be read. The original backup is still stored; export it from Settings before starting over.';
        return clean;
      }
    }
    return state;
  }

  List<Meal> mealsFor(DateTime date) =>
      meals.where((m) => dateKey(m.time) == dateKey(date)).toList()
        ..sort((a, b) => b.time.compareTo(a.time));
  Nutrients totalsFor(DateTime date) =>
      mealsFor(date).fold(Nutrients.zero, (sum, m) => sum + mealNutrition(m));
  int waterFor(DateTime date) => water[dateKey(date)] ?? 0;
  int get streak {
    var d = DateTime.now();
    if (mealsFor(d).isEmpty) {
      d = DateTime(d.year, d.month, d.day - 1);
    }
    var count = 0;
    while (mealsFor(d).isNotEmpty && count < 365) {
      count++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return count;
  }

  Future<void> persist() {
    if (!_disposed) notifyListeners();
    final snapshot = jsonEncode(toJson());
    _pendingWrite = _pendingWrite
        .catchError((_) {})
        .then((_) async {
          final ok = await storage.setString(recordKey, snapshot);
          if (ok) {
            final hadError = storageError != null;
            storageError = null;
            if (hadError && !_disposed) notifyListeners();
          }
          if (!ok) {
            throw StateError('Storage is full');
          }
        })
        .catchError((Object error) {
          storageError = 'Changes are still in memory, but could not be saved. Export your data before closing the app.';
          if (!_disposed) notifyListeners();
        });
    return _pendingWrite;
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'accountEmail': accountEmail,
    'appearance': appearance,
    'profile': profile.toJson(),
    'onboarded': onboarded,
    'demo': demo,
    'premium': premium,
    'community': community,
    'meals': meals.map((m) => m.toJson()).toList(),
    'templates': templates.map((m) => m.toJson()).toList(),
    'weights': weights.map((w) => w.toJson()).toList(),
    'water': water,
    'drinks': drinks.map((e) => e.toJson()).toList(),
    'activityMinutes': activityMinutes,
    'joined': joined.toList(),
    'liked': liked.toList(),
    'hiddenPosts': hiddenPosts.toList(),
    'communityPosts': communityPosts,
    'comments': comments,
    'preferences': preferences,
  };

  Future<void> setAppearance(String value) async {
    if (!['light', 'dark', 'system'].contains(value)) return;
    appearance = value;
    await persist();
  }

  Future<void> completeOnboarding(
    BodyProfile p, {
    bool withDemo = false,
  }) async {
    profile = p;
    onboarded = true;
    if (withDemo) {
      seedDemo();
    } else if (weights.isEmpty) {
      weights.add(WeightEntry(DateTime.now(), p.weight));
    }
    await persist();
  }

  void seedDemo() {
    demo = true;
    final today = DateTime.now();
    meals.clear();
    weights.clear();
    water.clear();
    drinks.clear();
    templates.clear();
    activityMinutes.clear();
    for (var day = 0; day < 7; day++) {
      final d = today.subtract(Duration(days: day));
      Meal make(
        String name,
        String cat,
        int hour,
        String image,
        List<MealItem> items,
      ) => Meal(
        id: 'demo-$day-$cat',
        name: name,
        time: DateTime(d.year, d.month, d.day, hour, 15),
        category: cat,
        items: items,
        image: image,
        input: 'Sample data',
        assumptions: 'Illustrative sample meal, not a personal record.',
      );
      meals.add(
        make('Avocado toast & eggs', 'Breakfast', 8, 'breakfast', [
          MealItem(foodId: 'toast', grams: 130),
          MealItem(foodId: 'egg', grams: 100),
        ]),
      );
      meals.add(
        make('Grilled chicken bowl', 'Lunch', 12, 'bowl', [
          MealItem(foodId: 'bowl', grams: 380 + day * 5),
        ]),
      );
      if (day > 0) {
        meals.add(
          make('Home-style dal bhat', 'Dinner', 19, 'curry', [
            MealItem(foodId: 'dalbhat', grams: 550 + day * 20),
          ]),
        );
        meals.add(
          make('Yogurt & almonds', 'Snack', 16, 'breakfast', [
            MealItem(foodId: 'yogurt', grams: 170),
            MealItem(foodId: 'almonds', grams: 28),
          ]),
        );
      }
      water[dateKey(d)] = day == 0 ? 1250 : 1750 + (day % 2) * 250;
      activityMinutes[dateKey(d)] = day == 0 ? 15 : 20 + day * 5;
      weights.add(WeightEntry(d, profile.weight + day * .15));
    }
    for (final e in water.entries) {
      drinks.add(
        DrinkEntry(
          id: "demo-water-${e.key}",
          time: DateTime.parse("${e.key}T12:00:00"),
          ml: e.value,
        ),
      );
    }
    templates.add(meals.first.copy(id: 'template-breakfast'));
    templates.add(
      Meal(
        id: 'template-curry',
        name: 'My usual rice & curry',
        time: today,
        category: 'Lunch',
        image: 'curry',
        input: 'Saved meal',
        items: [
          MealItem(foodId: 'rice', grams: 158),
          MealItem(foodId: 'curry', grams: 200),
        ],
      ),
    );
  }

  void _validateMeal(Meal meal) {
    if (meal.id.isEmpty || meal.name.trim().isEmpty) {
      throw const FormatException('Give the meal a name');
    }
    if (meal.items.isEmpty && meal.manual == null) {
      throw const FormatException('Add a food or nutrition values');
    }
    for (final i in meal.items) {
      if (!i.grams.isFinite || i.grams < 1 || i.grams > 3000) {
        throw const FormatException('Invalid portion');
      }
      if (i.snapshot != null && i.snapshot!.id != i.foodId) {
        throw const FormatException('Food identity mismatch');
      }
      if (i.snapshot == null && !foods.any((f) => f.id == i.foodId)) {
        throw const FormatException('Food snapshot missing');
      }
      final n = mealItemFood(i).per100g;
      final values = [n.calories, n.protein, n.carbs, n.fat, n.fiber];
      for (var k = 0; k < values.length; k++) {
        final v = values[k];
        if (v != null && (!v.isFinite || v < 0 || v > (k == 0 ? 1200 : 100))) {
          throw const FormatException('Invalid nutrition');
        }
      }
    }
    final n = meal.manual;
    if (n != null &&
        [
          n.calories,
          n.protein,
          n.carbs,
          n.fat,
          n.fiber,
        ].any((v) => v != null && (!v.isFinite || v < 0 || v > 10000))) {
      throw const FormatException('Invalid manual nutrition');
    }
  }

  Future<void> saveMeal(Meal meal) async {
    _validateMeal(meal);
    if (!preferences['Keep meal photos']!) {
      meal.photo = null;
    }
    meals.removeWhere((m) => m.id == meal.id);
    meals.add(meal.copy());
    await persist();
  }

  Future<void> deleteMeal(String id) async {
    meals.removeWhere((m) => m.id == id);
    await persist();
  }

  Future<void> saveTemplate(Meal meal) async {
    final existing = templates.indexWhere(
      (m) => m.name.toLowerCase() == meal.name.toLowerCase(),
    );
    final template = meal.copy(id: 'template-${newId()}');
    if (existing >= 0) {
      templates[existing] = template;
    } else {
      templates.add(template);
    }
    await persist();
  }

  List<DrinkEntry> drinksFor(DateTime date) =>
      drinks.where((e) => dateKey(e.time) == dateKey(date)).toList()
        ..sort((a, b) => b.time.compareTo(a.time));
  void _syncWater() {
    water = {};
    for (final e in drinks) {
      water[dateKey(e.time)] = (water[dateKey(e.time)] ?? 0) + e.ml;
    }
    if (water.values.any((v) => v > 10000)) {
      throw const FormatException('Daily water limit exceeded');
    }
  }

  Future<DrinkEntry> recordDrink(
    int ml, {
    DateTime? date,
    String? replaceId,
  }) async {
    final time = date ?? DateTime.now();
    final previous = drinks.where((e) => e.id == replaceId).firstOrNull;
    final total =
        waterFor(time) -
        (previous != null && dateKey(previous.time) == dateKey(time)
            ? previous.ml
            : 0) +
        ml;
    if (ml < 1 || ml > 2000 || total > 10000) {
      throw const FormatException('Enter 1–2,000 ml; daily log limit is 10 L.');
    }
    final entry = DrinkEntry(id: replaceId ?? newId(), time: time, ml: ml);
    drinks.removeWhere((e) => e.id == replaceId);
    drinks.add(entry);
    _syncWater();
    await persist();
    return entry;
  }

  Future<void> removeDrink(String id) async {
    drinks.removeWhere((e) => e.id == id);
    _syncWater();
    await persist();
  }

  Future<void> restoreDrink(DrinkEntry entry) async {
    if (drinks.any((e) => e.id == entry.id)) return;
    if (waterFor(entry.time) + entry.ml > 10000) {
      throw const FormatException('Daily log limit exceeded');
    }
    drinks.add(entry);
    _syncWater();
    await persist();
  }

  Future<void> setWaterGoal(int ml) async {
    if (ml < 500 || ml > 6000) {
      throw const FormatException('Choose a goal from 500 to 6,000 ml.');
    }
    profile.waterTarget = ml;
    await persist();
  }

  Future<void> addWater(int amount, {DateTime? date}) async {
    if (amount > 0) {
      await recordDrink(amount, date: date);
      return;
    }
    var remaining = -amount;
    for (final entry in drinksFor(date ?? DateTime.now())) {
      if (remaining <= 0) break;
      drinks.removeWhere((e) => e.id == entry.id);
      if (entry.ml > remaining) {
        drinks.add(
          DrinkEntry(id: entry.id, time: entry.time, ml: entry.ml - remaining),
        );
      }
      remaining -= entry.ml;
    }
    _syncWater();
    await persist();
  }

  Future<void> logWeight(double kg, {DateTime? date}) async {
    if (!kg.isFinite || kg < 20 || kg > 400) {
      throw const FormatException('Enter a weight from 20 to 400 kg');
    }
    final d = date ?? DateTime.now();
    weights.removeWhere((w) => dateKey(w.date) == dateKey(d));
    weights.add(WeightEntry(d, kg));
    weights.sort((a, b) => a.date.compareTo(b.date));
    profile.weight = kg;
    await persist();
  }

  Future<void> addActivity(int minutes) async {
    final key = dateKey(DateTime.now());
    activityMinutes[key] = ((activityMinutes[key] ?? 0) + minutes).clamp(
      0,
      1440,
    );
    await persist();
  }

  Future<void> reset() async {
    await _pendingWrite;
    await storage.remove(recordKey);
    await storage.remove(backupKey);
    profile = BodyProfile();
    onboarded = false;
    demo = false;
    premium = false;
    appearance = 'light';
    community = false;
    meals.clear();
    templates.clear();
    weights.clear();
    water.clear();
    drinks.clear();
    activityMinutes.clear();
    joined.clear();
    liked.clear();
    hiddenPosts.clear();
    communityPosts.clear();
    comments.clear();
    preferences = {
      'Meal reminders': true,
      'Hydration reminders': false,
      'Weekly review': true,
      'Quiet hours': true,
      'Keep meal photos': true,
      'Improve recognition': false,
    };
    storageError = null;
    notifyListeners();
  }
}
