import 'package:flutter/material.dart';
import '../services/fatsecret_service.dart';

class FoodDiaryPage extends StatefulWidget {
  final FatSecretService fatSecret;

  const FoodDiaryPage({super.key, required this.fatSecret});

  @override
  State<FoodDiaryPage> createState() => _FoodDiaryPageState();
}

class _FoodDiaryPageState extends State<FoodDiaryPage> {
  bool _isLoading = false;
  String _error = '';
  List<dynamic> _entries = [];
  DateTime _selectedDate = DateTime.now();

  // Meal order for grouping
  final List<String> _mealOrder = ['Breakfast', 'Lunch', 'Dinner', 'Other'];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final data = await widget.fatSecret.getFoodEntries(_selectedDate);
      final raw = data['food_entries']?['food_entry'];

      setState(() {
        if (raw == null) {
          _entries = [];
        } else if (raw is List) {
          _entries = raw;
        } else {
          _entries = [raw]; // single entry comes as object not array
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }

    setState(() => _isLoading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadEntries();
    }
  }

  // Group entries by meal type
  Map<String, List<dynamic>> get _groupedEntries {
    final Map<String, List<dynamic>> grouped = {};
    for (final entry in _entries) {
      final meal = entry['meal'] ?? 'Other';
      grouped.putIfAbsent(meal, () => []).add(entry);
    }
    return grouped;
  }

  // Total calories for the day
  double get _totalCalories {
    return _entries.fold(0.0, (sum, e) {
    return sum + (double.tryParse(e['calories']?.toString() ?? '0') ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Food Diary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEntries,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date + total calories bar
          Container(
            color: Colors.green.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.local_fire_department, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      '${_totalCalories.toStringAsFixed(0)} kcal total',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 48),
                            const SizedBox(height: 8),
                            Text(_error, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadEntries,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _entries.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.no_food, size: 64, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('No entries for this day',
                                    style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : ListView(
                            children: _mealOrder
                                .where((meal) =>
                                    _groupedEntries.containsKey(meal))
                                .map((meal) => _buildMealSection(meal))
                                .toList(),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealSection(String meal) {
    final entries = _groupedEntries[meal] ?? [];
    final mealCalories = entries.fold(0.0, (sum, e) {
      return sum + (double.tryParse(e['calories']?.toString() ?? '0') ?? 0);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Meal header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.green.shade100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(_mealIcon(meal), color: Colors.green.shade800),
                  const SizedBox(width: 8),
                  Text(
                    meal,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              Text(
                '${mealCalories.toStringAsFixed(0)} kcal',
                style: TextStyle(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Food entries for this meal
        ...entries.map((entry) => _buildFoodEntry(entry)),
      ],
    );
  }

  Widget _buildFoodEntry(Map<String, dynamic> entry) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Food name + calories
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    entry['food_entry_name'] ?? 'Unknown',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Text(
                  '${entry['calories']} kcal',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Serving description
            Text(
              entry['food_entry_description'] ?? '',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),

            // Macros row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMacro('Carbs', entry['carbohydrate'], 'g', Colors.blue),
                _buildMacro('Protein', entry['protein'], 'g', Colors.red),
                _buildMacro('Fat', entry['fat'], 'g', Colors.yellow.shade800),
                _buildMacro('Fiber', entry['fiber'], 'g', Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacro(String label, dynamic value, String unit, Color color) {
    return Column(
      children: [
        Text(
          '${value ?? 0}$unit',
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  IconData _mealIcon(String meal) {
    switch (meal) {
      case 'Breakfast':
        return Icons.free_breakfast;
      case 'Lunch':
        return Icons.lunch_dining;
      case 'Dinner':
        return Icons.dinner_dining;
      default:
        return Icons.fastfood;
    }
  }
}