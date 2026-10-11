import 'package:flutter/material.dart';

class CommunityGroup {
  const CommunityGroup(
    this.id,
    this.name,
    this.description,
    this.category,
    this.icon,
    this.color,
  );
  final String id, name, description, category;
  final IconData icon;
  final Color color;
}

const communityGroups = <CommunityGroup>[
  CommunityGroup(
    'getting-started',
    'New to tracking',
    'Small steps, first wins, and a little encouragement.',
    'Habits',
    Icons.spa_outlined,
    Color(0xFF699B79),
  ),
  CommunityGroup(
    'fitness',
    'Fitness & workouts',
    'Training ideas, movement, and showing up together.',
    'Movement',
    Icons.fitness_center_rounded,
    Color(0xFF9A7DDD),
  ),
  CommunityGroup(
    'weight-loss',
    'Weight loss support',
    'Sustainable habits and a supportive place to check in.',
    'Goals',
    Icons.favorite_outline_rounded,
    Color(0xFFE78B77),
  ),
  CommunityGroup(
    'muscle-gain',
    'Muscle gain & bulking',
    'Fuel your training and celebrate stronger days.',
    'Goals',
    Icons.bolt_rounded,
    Color(0xFFD3A553),
  ),
  CommunityGroup(
    'maintain',
    'Maintain & thrive',
    'Find your balance with everyday routines.',
    'Goals',
    Icons.balance_rounded,
    Color(0xFF6999B1),
  ),
  CommunityGroup(
    'keto',
    'Keto kitchen',
    'Low-carb recipe ideas and everyday food inspiration.',
    'Food styles',
    Icons.egg_outlined,
    Color(0xFFC49B69),
  ),
  CommunityGroup(
    'vegan',
    'Vegan table',
    'Plant-based plates, recipes, and protein inspiration.',
    'Food styles',
    Icons.eco_outlined,
    Color(0xFF699B79),
  ),
  CommunityGroup(
    'vegetarian',
    'Vegetarian living',
    'Colorful meals and meat-free favorites.',
    'Food styles',
    Icons.local_florist_outlined,
    Color(0xFF9A7DDD),
  ),
  CommunityGroup(
    'pescatarian',
    'Pescatarian plates',
    'Seafood, plants, and fresh ideas for your week.',
    'Food styles',
    Icons.set_meal_outlined,
    Color(0xFF6999B1),
  ),
  CommunityGroup(
    'fasting',
    'Intermittent fasting',
    'Share your routine, reflect, and support one another.',
    'Habits',
    Icons.schedule_rounded,
    Color(0xFFD3A553),
  ),
  CommunityGroup(
    'meal-prep',
    'Meal prep club',
    'Plan ahead and make tomorrow a little easier.',
    'Habits',
    Icons.kitchen_outlined,
    Color(0xFFE78B77),
  ),
  CommunityGroup(
    'walking',
    'Daily movement',
    'Walks, fresh air, and little movement milestones.',
    'Movement',
    Icons.directions_walk_rounded,
    Color(0xFF699B79),
  ),
  CommunityGroup(
    'cal-1500',
    '1,500 calorie community',
    'Meal inspiration around your personal plan.',
    'Calorie circles',
    Icons.restaurant_outlined,
    Color(0xFF6999B1),
  ),
  CommunityGroup(
    'cal-1800',
    '1,800 calorie community',
    'Share satisfying plates and everyday ideas.',
    'Calorie circles',
    Icons.restaurant_outlined,
    Color(0xFF9A7DDD),
  ),
  CommunityGroup(
    'cal-2000',
    '2,000 calorie community',
    'Good food, steady habits, and daily encouragement.',
    'Calorie circles',
    Icons.restaurant_outlined,
    Color(0xFF699B79),
  ),
  CommunityGroup(
    'cal-2200',
    '2,200 calorie community',
    'Connect over recipes that fit your routine.',
    'Calorie circles',
    Icons.restaurant_outlined,
    Color(0xFFE78B77),
  ),
  CommunityGroup(
    'cal-2500',
    '2,500 calorie community',
    'Fuel active days with shared meal inspiration.',
    'Calorie circles',
    Icons.restaurant_outlined,
    Color(0xFFD3A553),
  ),
  CommunityGroup(
    'cal-3000',
    '3,000 calorie community',
    'Hearty meals and ideas for higher-energy days.',
    'Calorie circles',
    Icons.restaurant_outlined,
    Color(0xFF6999B1),
  ),
];

/// QR payloads use an app scheme so arbitrary URLs cannot become friend invites.
class FriendInvite {
  static final pattern = RegExp(r'^K-[A-F0-9]{24}$');
  static String parse(String raw) {
    var value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null &&
        uri.scheme == 'kayleo' &&
        uri.host == 'friend' &&
        uri.pathSegments.length == 1) {
      value = uri.pathSegments.single;
    }
    value = value.toUpperCase();
    if (!pattern.hasMatch(value)) {
      throw const FormatException(
        'Enter a complete Kayleo invite code or scan a friend QR.',
      );
    }
    return value;
  }

  static String qr(String code) => 'kayleo://friend/${parse(code)}';
  static String pairId(String a, String b) => ([a, b]..sort()).join('_');
}
