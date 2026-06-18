import 'package:flutter/material.dart';
import 'package:healthshare/model/NutrientDef.dart';
import '../services/fatsecret_service.dart';

// ─── Design tokens (mirrored from HomePage) ───────────────────────────────────
class _Palette {
  static const pine = Color(0xFF1F4D3D);
  static const pineLight = Color(0xFFE3ECE6);
  static const ember = Color(0xFFFF6B4A);
  static const emberText = Color(0xFFB14A2E);
  static const sage = Color(0xFF8FAE96);
  static const linen = Color(0xFFFAF6EF);
  static const ink = Color(0xFF232323);
  static const inkMuted = Color(0xFF767670);
  static const mist = Color(0xFFE4DFD3);
  static const card = Color(0xFFFFFFFF);
  static const dawn = Color(0xFF6B8CAE);
  static const noon = Color(0xFFD9A441);
  static const dusk = Color(0xFF8C6E97);
}

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
  final Set<String> _expandedMeals = {};

  static const List<String> _mealOrder = ['Breakfast', 'Lunch', 'Dinner'];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  // ─── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      Map<String, dynamic> data;
      try {
        data = await widget.fatSecret.getFoodEntries(_selectedDate);
      } catch (e) {
        if (e.toString().contains('Invalid signature')) {
          await Future.delayed(const Duration(milliseconds: 500));
          data = await widget.fatSecret.getFoodEntries(_selectedDate);
        } else {
          rethrow;
        }
      }
      final raw = data['food_entries']?['food_entry'];
      setState(() {
        if (raw == null) {
          _entries = [];
        } else if (raw is List) {
          _entries = raw;
        } else {
          _entries = [raw];
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
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _Palette.pine,
            onPrimary: Colors.white,
            surface: _Palette.card,
            onSurface: _Palette.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _expandedMeals.clear(); // reset expanded state for new day
      });
      _loadEntries();
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Color _mealColor(String? meal) {
    switch (meal?.toLowerCase()) {
      case 'breakfast': return _Palette.dawn;
      case 'lunch':     return _Palette.noon;
      case 'dinner':    return _Palette.dusk;
      default:          return _Palette.ember;
    }
  }

  IconData _mealIcon(String? meal) {
    switch (meal?.toLowerCase()) {
      case 'breakfast': return Icons.free_breakfast_rounded;
      case 'lunch':     return Icons.lunch_dining_rounded;
      case 'dinner':    return Icons.dinner_dining_rounded;
      default:          return Icons.fastfood_rounded;
    }
  }

  String _mealLabel(String? meal) {
    if (meal == null || meal.isEmpty) return 'Other';
    return meal[0].toUpperCase() + meal.substring(1).toLowerCase();
  }

  Map<String, List<dynamic>> _groupEntriesByMeal() {
    final Map<String, List<dynamic>> groups = {};
    for (final entry in _entries) {
      final label = _mealLabel(entry['meal']);
      groups.putIfAbsent(label, () => []).add(entry);
    }
    final orderedKeys = groups.keys.toList()
      ..sort((a, b) {
        final ia = _mealOrder.indexOf(a);
        final ib = _mealOrder.indexOf(b);
        final ra = ia == -1 ? _mealOrder.length : ia;
        final rb = ib == -1 ? _mealOrder.length : ib;
        if (ra != rb) return ra.compareTo(rb);
        return a.compareTo(b);
      });
    return {for (final key in orderedKeys) key: groups[key]!};
  }

  int _groupCalories(List<dynamic> entries) {
    int total = 0;
    for (final e in entries) {
      total += int.tryParse(e['calories']?.toString() ?? '') ?? 0;
    }
    return total;
  }

  int get _totalCalories => _groupCalories(_entries);

  String _formattedDate(DateTime date) {
    const weekdays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const months = ['January','February','March','April','May','June',
                    'July','August','September','October','November','December'];
    final isToday = date.day == DateTime.now().day &&
        date.month == DateTime.now().month &&
        date.year == DateTime.now().year;
    final label = isToday ? 'Today' : weekdays[date.weekday - 1];
    return '$label, ${months[date.month - 1]} ${date.day}';
  }

  void _goToPreviousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _expandedMeals.clear();
    });
    _loadEntries();
  }

  void _goToNextDay() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    if (_selectedDate.isBefore(DateTime(tomorrow.year, tomorrow.month, tomorrow.day))) {
      setState(() {
        _selectedDate = _selectedDate.add(const Duration(days: 1));
        _expandedMeals.clear();
      });
      _loadEntries();
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.day == now.day &&
        _selectedDate.month == now.month &&
        _selectedDate.year == now.year;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.linen,
      appBar: AppBar(
        backgroundColor: _Palette.pine,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Food Diary',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3),
            ),
            Text(
              _formattedDate(_selectedDate),
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.78),
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today_rounded),
            tooltip: 'Pick date',
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadEntries,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateNavBar(),
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: _Palette.pine),
                        const SizedBox(height: 12),
                        Text('Loading…',
                            style: TextStyle(color: _Palette.inkMuted)),
                      ],
                    ),
                  )
                : _error.isNotEmpty
                    ? _buildErrorState()
                    : _entries.isEmpty
                        ? _buildEmptyState()
                        : _buildDiaryBody(),
          ),
        ],
      ),
    );
  }

  // ─── Widgets ──────────────────────────────────────────────────────────────

  Widget _buildDateNavBar() {
    return Container(
      color: _Palette.pine,
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 16, top: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            // Previous day
            IconButton(
              onPressed: _goToPreviousDay,
              icon: const Icon(Icons.chevron_left_rounded,
                  color: Colors.white, size: 26),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            // Total calories badge
            Expanded(
              child: Column(
                children: [
                  Text(
                    '$_totalCalories kcal',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18),
                  ),
                  Text(
                    '${_entries.length} item${_entries.length == 1 ? '' : 's'} logged',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            // Next day (greyed out if today)
            IconButton(
              onPressed: _isToday ? null : _goToNextDay,
              icon: Icon(Icons.chevron_right_rounded,
                  color: _isToday
                      ? Colors.white.withOpacity(0.3)
                      : Colors.white,
                  size: 26),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _Palette.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _Palette.mist),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: _Palette.ember, size: 40),
              const SizedBox(height: 12),
              const Text('Something went wrong',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _Palette.ink)),
              const SizedBox(height: 6),
              Text(_error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: _Palette.inkMuted)),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _loadEntries,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Palette.pine,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          decoration: BoxDecoration(
            color: _Palette.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _Palette.mist),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant_menu_rounded,
                  size: 36, color: _Palette.mist.withOpacity(0.9)),
              const SizedBox(height: 12),
              const Text('No meals logged',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _Palette.ink)),
              const SizedBox(height: 4),
              const Text(
                'No food entries found for this day.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _Palette.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiaryBody() {
    final groups = _groupEntriesByMeal();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 14),
          ...groups.entries.map((group) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildMealGroupCard(group.key, group.value),
              )),
        ],
      ),
    );
  }

  /// Macros summary card at the top of the diary
  Widget _buildSummaryCard() {
    final protein = _entries.fold(0.0,
        (s, e) => s + (double.tryParse(e['protein']?.toString() ?? '0') ?? 0));
    final carbs = _entries.fold(0.0,
        (s, e) => s + (double.tryParse(e['carbohydrate']?.toString() ?? '0') ?? 0));
    final fat = _entries.fold(0.0,
        (s, e) => s + (double.tryParse(e['fat']?.toString() ?? '0') ?? 0));
    final fiber = _entries.fold(0.0,
        (s, e) => s + (double.tryParse(e['fiber']?.toString() ?? '0') ?? 0));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.mist),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DAILY SUMMARY',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: _Palette.inkMuted),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryMacro('Calories', '$_totalCalories', 'kcal',
                  _Palette.ember, Icons.local_fire_department_rounded),
              _buildSummaryDivider(),
              _buildSummaryMacro('Protein', '${protein.toStringAsFixed(1)}', 'g',
                  _Palette.dawn, Icons.fitness_center_rounded),
              _buildSummaryDivider(),
              _buildSummaryMacro('Carbs', '${carbs.toStringAsFixed(1)}', 'g',
                  _Palette.noon, Icons.grain_rounded),
              _buildSummaryDivider(),
              _buildSummaryMacro('Fat', '${fat.toStringAsFixed(1)}', 'g',
                  _Palette.dusk, Icons.water_drop_rounded),
              _buildSummaryDivider(),
              _buildSummaryMacro('Fiber', '${fiber.toStringAsFixed(1)}', 'g',
                  _Palette.sage, Icons.eco_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryDivider() =>
      Container(height: 32, width: 1, color: _Palette.mist);

  Widget _buildSummaryMacro(
      String label, String value, String unit, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: color)),
        Text(unit,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _Palette.inkMuted)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: _Palette.inkMuted)),
      ],
    );
  }

  Widget _buildMealGroupCard(String mealLabel, List<dynamic> entries) {
    final color = _mealColor(mealLabel);
    final bool canExpand = entries.length > 1;
    final bool isExpanded = canExpand && _expandedMeals.contains(mealLabel);

    final dynamic previewEntry = entries.reduce((a, b) {
      final aCal = int.tryParse(a['calories']?.toString() ?? '0') ?? 0;
      final bCal = int.tryParse(b['calories']?.toString() ?? '0') ?? 0;
      return aCal >= bCal ? a : b;
    });

    return Container(
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.mist),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: canExpand
                ? () => setState(() {
                      if (isExpanded) {
                        _expandedMeals.remove(mealLabel);
                      } else {
                        _expandedMeals.add(mealLabel);
                      }
                    })
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              color: color.withOpacity(0.12),
              child: Row(
                children: [
                  Icon(_mealIcon(mealLabel), color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(mealLabel,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: color)),
                  const Spacer(),
                  Text(
                    '${entries.length} item${entries.length == 1 ? '' : 's'} · ${_groupCalories(entries)} kcal',
                    style: const TextStyle(
                        color: _Palette.inkMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                  if (canExpand) ...[
                    const SizedBox(width: 6),
                    Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: color,
                      size: 22,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isExpanded) _buildFoodRow(previewEntry, color, mealLabel),
          if (isExpanded)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: _Palette.mist.withOpacity(0.7)),
              itemBuilder: (context, index) =>
                  _buildFoodRow(entries[index], color, mealLabel),
            ),
        ],
      ),
    );
  }

  Widget _buildFoodRow(dynamic entry, Color color, String mealLabel) {
    return InkWell(
      onTap: () => _showNutritionDialog(context, entry, color, mealLabel),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(_mealIcon(mealLabel), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry['food_entry_name'] ?? 'Unknown',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _Palette.ink),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _Palette.ember.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${entry['calories']} kcal',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: _Palette.emberText),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.info_outline_rounded,
                size: 16, color: _Palette.inkMuted),
          ],
        ),
      ),
    );
  }

  void _showNutritionDialog(
      BuildContext context, dynamic entry, Color color, String mealLabel) {
    showDialog(
      context: context,
      builder: (context) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: _Palette.card,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.80,
              maxWidth: screenWidth * 0.92,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.14),
                          shape: BoxShape.circle,
                        ),
                        child:
                            Icon(_mealIcon(mealLabel), color: color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry['food_entry_name'] ?? 'Unknown',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: _Palette.ink),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (entry['food_entry_description'] != null)
                              Text(
                                entry['food_entry_description'],
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: _Palette.inkMuted,
                                    fontWeight: FontWeight.w500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: _Palette.inkMuted, size: 22),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_fire_department_rounded,
                            color: color, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          '${entry['calories']} kcal',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: color),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(color: _Palette.mist, height: 1),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: _buildNutrientGrid(entry),
                  ),
                ),
                if (entry['number_of_units'] != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Text(
                      'Serving: ${entry['number_of_units']} unit(s)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11,
                          color: _Palette.inkMuted,
                          fontWeight: FontWeight.w500),
                    ),
                  )
                else
                  const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

Widget _buildNutrientGrid(dynamic entry) {
  // Define all nutrients with display label and unit
  final nutrients = [
    NutrientDef('Protein',      entry['protein'],          'g',  Icons.fitness_center_rounded),
    NutrientDef('Carbs',        entry['carbohydrate'],     'g',  Icons.grain_rounded),
    NutrientDef('Fat',          entry['fat'],              'g',  Icons.water_drop_rounded),
    NutrientDef('Fiber',        entry['fiber'],            'g',  Icons.eco_rounded),
    NutrientDef('Sugar',        entry['sugar'],            'g',  Icons.icecream_rounded),
    NutrientDef('Sodium',       entry['sodium'],           'mg', Icons.science_rounded),
    NutrientDef('Cholesterol',  entry['cholesterol'],      'mg', Icons.favorite_rounded),
    NutrientDef('Sat. Fat',     entry['saturated_fat'],    'g',  Icons.opacity_rounded),
    NutrientDef('Trans Fat',    entry['trans_fat'],        'g',  Icons.block_rounded),
    NutrientDef('Mono Fat',     entry['monounsaturated_fat'], 'g', Icons.trending_flat_rounded),
    NutrientDef('Poly Fat',     entry['polyunsaturated_fat'], 'g', Icons.waves_rounded),
  ].where((n) => n.value != null && n.value.toString().isNotEmpty).toList();

  return GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      childAspectRatio: 2.2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    ),
    itemCount: nutrients.length,
    itemBuilder: (context, i) {
      final n = nutrients[i];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _Palette.mist.withOpacity(0.35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${n.value}${n.unit}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _Palette.ink),
            ),
            Text(
              n.label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: _Palette.inkMuted),
            ),
          ],
        ),
      );
    },
  );
}

}