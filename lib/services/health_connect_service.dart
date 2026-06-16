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

  // ─── Get Existing Meals for a Specific Date ───────────────────

  Future<Set<String>> getExistingMealKeys(DateTime date) async {
    // Strict day boundaries — midnight to midnight
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    try {
      final existing = await _health.getHealthDataFromTypes(
        startTime: startOfDay,
        endTime: endOfDay,
        types: [HealthDataType.NUTRITION],
      );

      final keys = <String>{};
      for (final point in existing) {
        if (point.value is NutritionHealthValue) {
          final nutrition = point.value as NutritionHealthValue;
          // Key includes the exact date so meals from different days
          // never collide
          final key = _buildKey(
            nutrition.name ?? '',
            nutrition.mealType,
            startOfDay,
          );
          keys.add(key);
        }
      }

      print('Existing meal keys for ${date.day}/${date.month}/${date.year}: $keys');
      return keys;
    } catch (e) {
      print('Error fetching existing meals: $e');
      return {};
    }
  }
  
  String _mealTypeToString(dynamic mealType) {
  final s = mealType.toString().toLowerCase();
  // Handles both "breakfast" and "mealtype.breakfast"
  if (s.contains('breakfast')) return 'breakfast';
  if (s.contains('lunch')) return 'lunch';
  if (s.contains('dinner')) return 'dinner';
  return 'snack';
  }
  // Key format: "foodname|mealtype|YYYYMMDD"
  // Using | as separator to avoid collisions with food names containing _
  String _buildKey(String name, dynamic mealType, DateTime date) {
    final dateStr =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return '${name.trim().toLowerCase()}|${_mealTypeToString(mealType)}|$dateStr';
  }

  // ─── Sync Food Entries ────────────────────────────────────────

  Future<Map<String, int>> syncFoodEntries(List<dynamic> entries) async {
    await _health.configure();

    int added = 0;
    int skipped = 0;
    int failed = 0;

    if (entries.isEmpty) return {'added': 0, 'skipped': 0, 'failed': 0};

    // Get the date from the entries — use FatSecret's date_int
    // so we always sync for the correct calendar day
    final dateInt =
        int.tryParse(entries.first['date_int']?.toString() ?? '0') ?? 0;
    final entryDate = DateTime(1970, 1, 1).add(Duration(days: dateInt));
    final syncDate = DateTime(entryDate.year, entryDate.month, entryDate.day);

    print('Syncing for date: ${syncDate.day}/${syncDate.month}/${syncDate.year}');

    // Get existing meals for this specific date only
    final existingKeys = await getExistingMealKeys(syncDate);

    for (final entry in entries) {
      try {
        final mealName = entry['meal']?.toString() ?? 'Other';
        final name = entry['food_entry_name']?.toString() ?? 'Unknown';
        final mealType = _getMealType(mealName);

        // Build key using the entry's actual date
        final key = _buildKey(name, mealType, syncDate);

        if (existingKeys.contains(key)) {
          print('Skipping duplicate: $name on ${syncDate.day}/${syncDate.month}');
          skipped++;
          continue;
        }

        final mealTime = _getMealTime(syncDate, mealName);
        final mealEnd = mealTime.add(const Duration(minutes: 30));

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
          print('Added: $name');
          // Add to local set so if same entry appears twice in the
          // FatSecret response we don't write it twice
          existingKeys.add(key);
          added++;
        } else {
          print('Failed to write: $name');
          failed++;
        }
      } catch (e) {
        print('Error syncing entry: $e');
        failed++;
      }
    }

    print(
        'Sync complete for ${syncDate.day}/${syncDate.month}: $added added, $skipped skipped, $failed failed');
    return {'added': added, 'skipped': skipped, 'failed': failed};
  }

  // ─── Helpers ──────────────────────────────────────────────────
  DateTime _getMealTime(DateTime date, String meal) {
    DateTime mealTime;
    switch (meal.toLowerCase()) {
      case 'breakfast':
        mealTime = DateTime(date.year, date.month, date.day, 8, 0);
        break;
      case 'lunch':
        mealTime = DateTime(date.year, date.month, date.day, 12, 0);
        break;
      case 'dinner':
        mealTime = DateTime(date.year, date.month, date.day, 18, 0);
        break;
      default:
        mealTime = DateTime(date.year, date.month, date.day, 15, 0);
    }

    final now = DateTime.now();
    return mealTime.isAfter(now) ? now.subtract(const Duration(minutes: 1)) : mealTime;
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

  Future<void> removeOrphanedEntries(
    List<dynamic> fatSecretEntries,
    DateTime date,
  ) async {
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    // Build set of keys FatSecret currently has
    final fatSecretKeys = <String>{};
    for (final entry in fatSecretEntries) {
      final name = entry['food_entry_name']?.toString() ?? '';
      final meal = entry['meal']?.toString() ?? '';
      fatSecretKeys.add(_buildKey(name, meal, date));
    }

    // Get everything currently in Health Connect for this day
    final existing = await _health.getHealthDataFromTypes(
      startTime: startOfDay,
      endTime: endOfDay,
      types: [HealthDataType.NUTRITION],
    );

    for (final point in existing) {
      if (point.value is! NutritionHealthValue) continue;
      if (point.sourceName != 'com.example.healthshare') continue;

      final nutrition = point.value as NutritionHealthValue;
      final key = _buildKey(nutrition.name ?? '', nutrition.mealType, startOfDay);

      if (!fatSecretKeys.contains(key)) {
        print('Removing orphan: ${nutrition.name}');
        final deleted = await _health.delete(
          type: HealthDataType.NUTRITION,
          startTime: point.dateFrom,
          endTime: point.dateTo,
        );
        print(deleted ? 'Removed: ${nutrition.name}' : 'Failed to remove: ${nutrition.name}');
      }
    }
  }
  
}