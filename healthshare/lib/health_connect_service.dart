import 'package:health/health.dart';

class HealthConnectService {
  final Health _health = Health();

  static const List<HealthDataType> _types = [
    HealthDataType.NUTRITION,
  ];

  // ─── Request Permissions ──────────────────────────────────────

  Future<bool> requestPermissions() async {
    await _health.configure();
    return await _health.requestAuthorization(
      _types,
      permissions: [HealthDataAccess.READ_WRITE],
    );
  }

  // ─── Get Existing Meals for a Date ───────────────────────────

  Future<Set<String>> getExistingMealKeys(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59);

    try {
      final existing = await _health.getHealthDataFromTypes(
        startTime: startOfDay,
        endTime: endOfDay,
        types: [HealthDataType.NUTRITION],
      );

      // Build a set of keys: "foodname_mealtype_date"
      final keys = <String>{};
      for (final point in existing) {
        if (point.value is NutritionHealthValue) {
          final nutrition = point.value as NutritionHealthValue;
          final key = _buildKey(
            nutrition.name ?? '',
            nutrition.mealType?.toString() ?? '',
            date,
          );
          keys.add(key);
        }
      }

      print('Existing meal keys: $keys');
      return keys;
    } catch (e) {
      print('Error fetching existing meals: $e');
      return {};
    }
  }

  String _buildKey(String name, String mealType, DateTime date) {
    return '${name.toLowerCase()}_${mealType.toLowerCase()}_${date.year}${date.month}${date.day}';
  }

  // ─── Sync Food Entries to Health Connect ──────────────────────

  Future<Map<String, int>> syncFoodEntries(List<dynamic> entries) async {
    await _health.configure();

    int added = 0;
    int skipped = 0;
    int failed = 0;

    // Get date from first entry
    final dateInt = int.tryParse(entries.first['date_int']?.toString() ?? '0') ?? 0;
    final date = DateTime(1970, 1, 1).add(Duration(days: dateInt));

    // Get existing meals to avoid duplicates
    final existingKeys = await getExistingMealKeys(date);

    for (final entry in entries) {
      try {
        final mealName = entry['meal']?.toString() ?? 'Other';
        final name = entry['food_entry_name']?.toString() ?? 'Unknown';
        final mealType = _getMealType(mealName);
        final mealTime = _getMealTime(date, mealName);
        final mealEnd = mealTime.add(const Duration(minutes: 30));

        // Check for duplicate
        final key = _buildKey(name, mealType.toString(), date);
        if (existingKeys.contains(key)) {
          print('Skipping duplicate: $name');
          skipped++;
          continue;
        }

        final calories =
            double.tryParse(entry['calories']?.toString() ?? '0') ?? 0;
        final carbs =
            double.tryParse(entry['carbohydrate']?.toString() ?? '0') ?? 0;
        final protein =
            double.tryParse(entry['protein']?.toString() ?? '0') ?? 0;
        final fat = double.tryParse(entry['fat']?.toString() ?? '0') ?? 0;
        final fiber =
            double.tryParse(entry['fiber']?.toString() ?? '0') ?? 0;
        final sugar =
            double.tryParse(entry['sugar']?.toString() ?? '0') ?? 0;
        final sodium =
            double.tryParse(entry['sodium']?.toString() ?? '0') ?? 0;
        final cholesterol =
            double.tryParse(entry['cholesterol']?.toString() ?? '0') ?? 0;

        final success = await _health.writeMeal(
          startTime: mealTime,
          endTime: mealEnd,
          mealType: mealType,
          name: name,
          caloriesConsumed: calories,
          carbohydrates: carbs,
          protein: protein,
          fatTotal: fat,
          fiber: fiber,
          sugar: sugar,
          sodium: sodium / 1000,
          cholesterol: cholesterol / 1000,
        );

        if (success) {
          added++;
        } else {
          failed++;
        }
      } catch (e) {
        print('Error syncing entry: $e');
        failed++;
      }
    }

    print('Sync done: $added added, $skipped skipped, $failed failed');
    return {'added': added, 'skipped': skipped, 'failed': failed};
  }

  // ─── Helpers ──────────────────────────────────────────────────

  DateTime _getMealTime(DateTime date, String meal) {
    switch (meal.toLowerCase()) {
      case 'breakfast':
        return DateTime(date.year, date.month, date.day, 8, 0);
      case 'lunch':
        return DateTime(date.year, date.month, date.day, 12, 0);
      case 'dinner':
        return DateTime(date.year, date.month, date.day, 18, 0);
      default:
        return DateTime(date.year, date.month, date.day, 15, 0);
    }
  }

  MealType _getMealType(String meal) {
    switch (meal.toLowerCase()) {
      case 'breakfast':
        return MealType.BREAKFAST;
      case 'lunch':
        return MealType.LUNCH;
      case 'dinner':
        return MealType.DINNER;
      default:
        return MealType.SNACK;
    }
  }
}