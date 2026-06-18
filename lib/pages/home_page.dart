import 'package:flutter/material.dart';
import 'package:healthshare/model/NutrientDef.dart';
import 'package:healthshare/services/notifications/background_sync_service.dart';
import 'package:healthshare/services/fatsecret_service.dart';
import 'package:healthshare/services/health_connect_service.dart';
import 'package:healthshare/pages/food_diary_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Design tokens for this page. Kept local so the redesign doesn't require
/// touching app-wide theming.
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

  // Meal-time spectrum: color tied to time of day, not arbitrary.
  static const dawn = Color(0xFF6B8CAE); // breakfast
  static const noon = Color(0xFFD9A441); // lunch
  static const dusk = Color(0xFF8C6E97); // dinner
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FatSecretService _fatSecret = FatSecretService();
  final HealthConnectService _healthConnect = HealthConnectService();
  int _syncIntervalMinutes = 30; // default

  String _status = 'Not connected';
  String _syncDetails = '';
  bool _isLoading = false;
  bool _isConnected = false;
  List<dynamic> _entries = [];
  DateTime? _lastLoadedDate;
  final Set<String> _expandedMeals = {};
  final Set<String> _collapsedMeals = {};


  @override
  void initState() {
    super.initState();
    _loadSavedTokens();
    BackgroundSyncService.initialize();
  }

  // ─── Auth ─────────────────────────────────────────────────────
  Future<void> _loadSavedTokens() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _syncIntervalMinutes = prefs.getInt('sync_interval_minutes') ?? 30;

    final hasToken = await _fatSecret.loadSavedTokens();
    setState(() {
      _isConnected = hasToken;
      _status = hasToken ? 'Connected' : 'Not connected';
      _isLoading = false;
    });
    if (hasToken) {
      await BackgroundSyncService.scheduleSync(intervalMinutes: _syncIntervalMinutes);
      await Future.delayed(const Duration(seconds: 2));
      await _syncToHealthConnect(silent: true);
    }
  }
  

  Future<void> _connectFatSecret() async {
    setState(() => _isLoading = true);
    try {
      final url = await _fatSecret.getAuthorizationUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      setState(() => _status = 'Waiting for PIN...');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _enterPin() async {
    final pinController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: const [
            Icon(Icons.pin_rounded, color: _Palette.pine),
            SizedBox(width: 10),
            Text(
              'Enter FatSecret PIN',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _Palette.ink),
            ),
          ],
        ),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter PIN here',
            filled: true,
            fillColor: _Palette.linen,
            prefixIcon: const Icon(Icons.dialpad_rounded, color: _Palette.inkMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _Palette.pine, width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _Palette.inkMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _Palette.pine,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _exchangePin(pinController.text.trim());
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _exchangePin(String pin) async {
    setState(() => _isLoading = true);
    try {
      await _fatSecret.exchangePinForAccessToken(pin);
      setState(() {
        _isConnected = true;
        _status = 'Connected';
      });
      await BackgroundSyncService.scheduleSync();
      await _syncToHealthConnect();
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _resync() async {
    setState(() => _isLoading = true);
    try {
      final hasToken = await _fatSecret.loadSavedTokens();
      if (!hasToken) {
        setState(() {
          _isConnected = false;
          _status = 'Token expired — please reconnect';
        });
        return;
      }
      setState(() {
        _isConnected = true;
        _status = 'Connected';
      });
      await _syncToHealthConnect();
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
    setState(() => _isLoading = false);
  }

  // ─── Sync ─────────────────────────────────────────────────────

  Future<void> _syncToHealthConnect({bool silent = false}) async {
    setState(() => _isLoading = true);
    try {
      final today = DateTime.now();
      final isNewDay = _lastLoadedDate == null ||
          _lastLoadedDate!.day != today.day ||
          _lastLoadedDate!.month != today.month;

      if (isNewDay) {
        setState(() => _entries = []);
      }

      // Fire background sync first, then wait for it to fully
      // release the lock before we make our own API call
      await BackgroundSyncService.syncNow(silent: silent);
      await Future.delayed(const Duration(milliseconds: 1500));

      final data = await _fatSecret.getFoodEntries(today);
      final raw = data['food_entries']?['food_entry'];

      if (raw == null) {
        setState(() {
          _syncDetails = 'No food entries today';
          _entries = [];
        });
      } else {
        final entries = raw is List ? raw : [raw];
        setState(() {
          _entries = entries;
          _syncDetails = 'Sync complete';
        });
      }

      _lastLoadedDate = today;
    } catch (e) {
      setState(() => _syncDetails = 'Sync error: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadTodayEntries() async {
    setState(() => _isLoading = true);
    try {
      final data = await _fatSecret.getFoodEntries(DateTime.now());
      final entries = data['food_entries']?['food_entry'] ?? [];
      setState(() {
        _entries = entries is List ? entries : [entries];
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
    setState(() => _isLoading = false);
  }


  Future<void> _showIntervalPicker() async {
    final options = [15, 30, 60, 120, 240];

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
        contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: const Text(
          'Auto-sync interval',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _Palette.ink),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((minutes) {
            final label = _intervalLabel(minutes);
            return RadioListTile<int>(
              dense: true,
              activeColor: _Palette.pine,
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              value: minutes,
              groupValue: _syncIntervalMinutes,
              onChanged: (value) async {
                if (value == null) return;
                Navigator.pop(context);
                setState(() => _syncIntervalMinutes = value);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('sync_interval_minutes', value);
                await BackgroundSyncService.updateInterval(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Auto-sync set to $label')),
                );
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _Palette.inkMuted)),
          ),
        ],
      ),
    );
  }

  // ─── Display helpers (presentation only — no behavior changes) ──

  String _intervalLabel(int minutes) {
    if (minutes < 60) return '$minutes minutes';
    return '${minutes ~/ 60} hour${minutes > 60 ? 's' : ''}';
  }

  String _formattedToday() {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  Color _mealColor(String? meal) {
    switch (meal?.toLowerCase()) {
      case 'breakfast':
        return _Palette.dawn;
      case 'lunch':
        return _Palette.noon;
      case 'dinner':
        return _Palette.dusk;
      default:
        return _Palette.ember;
    }
  }

  // ─── Grouping helpers (presentation only) ────────────────────

  static const List<String> _mealOrder = ['Breakfast', 'Lunch', 'Dinner'];

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
    for (final entry in entries) {
      total += int.tryParse(entry['calories']?.toString() ?? '') ?? 0;
    }
    return total;
  }

  // ─── Build ────────────────────────────────────────────────────

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
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'HealthShare',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3),
            ),
            Text(
              _formattedToday(),
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.78), fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (value) async {
              switch (value) {
                case 'resync':
                  await _resync();
                  break;
                case 'interval':
                  await _showIntervalPicker();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'resync',
                child: Row(
                  children: [
                    Icon(Icons.sync, size: 20, color: _Palette.pine),
                    SizedBox(width: 12),
                    Text('Resync to FatSecret'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'interval',
                child: Row(
                  children: [
                    Icon(Icons.timer, size: 20, color: _Palette.pine),
                    SizedBox(width: 12),
                    Text('Change Auto-Sync Interval'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: _Palette.pine),
                  const SizedBox(height: 12),
                  Text('Loading…', style: TextStyle(color: _Palette.inkMuted)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 14),
                  if (!_isConnected) _buildConnectSection(),
                  if (_isConnected) _buildSyncSection(),
                  const SizedBox(height: 14),
                  if (_isConnected && _entries.isEmpty) _buildEmptyEntries(),
                  if (_entries.isNotEmpty) _buildEntriesSection(),
                ],
              ),
            ),
    );
  }

  // ─── Widgets ──────────────────────────────────────────────────

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isConnected ? _Palette.sage.withOpacity(0.4) : _Palette.mist,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _isConnected ? _Palette.pineLight : _Palette.mist.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isConnected ? Icons.check_circle_rounded : Icons.link_off_rounded,
              color: _isConnected ? _Palette.pine : _Palette.inkMuted,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CONNECTION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: _Palette.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _status,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: _isConnected ? _Palette.pine : _Palette.ink,
                  ),
                ),
                if (_syncDetails.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _syncDetails,
                    style: const TextStyle(fontSize: 13, color: _Palette.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Connect FatSecret',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _Palette.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            'Link your FatSecret account so today\'s meals sync automatically to Google Health.',
            style: TextStyle(color: _Palette.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _connectFatSecret,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Connect FatSecret', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _Palette.pine,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _enterPin,
            icon: const Icon(Icons.pin_rounded, color: _Palette.pine),
            label: const Text('Enter PIN', style: TextStyle(color: _Palette.pine, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _Palette.pine.withOpacity(0.4)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.mist),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sync',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _Palette.ink),
              ),
              GestureDetector(
                onTap: _showIntervalPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _Palette.sage.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: _Palette.pine),
                      const SizedBox(width: 4),
                      Text(
                        'Every ${_intervalLabel(_syncIntervalMinutes)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _Palette.pine),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _syncToHealthConnect,
                  icon: const Icon(Icons.favorite),
                  label: const Text('Sync Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _Palette.ember,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoodDiaryPage(fatSecret: _fatSecret),
                    ),
                  ),
                  icon: const Icon(Icons.table_rows, color: _Palette.pine),
                  label: const Text('View Diary', style: TextStyle(color: _Palette.pine, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _Palette.pine.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyEntries() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.mist),
      ),
      child: Column(
        children: [
          Icon(Icons.restaurant_menu_rounded, size: 36, color: _Palette.mist.withOpacity(0.9)),
          const SizedBox(height: 12),
          const Text(
            'No meals logged yet today',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _Palette.ink),
          ),
          const SizedBox(height: 4),
          const Text(
            'Log food in FatSecret, then tap Sync Now to bring it in.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _Palette.inkMuted),
          ),
        ],
      ),
    );
  }

 Widget _buildEntriesSection() {
    final groups = _groupEntriesByMeal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: groups.entries
          .map((group) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildMealGroupCard(group.key, group.value),
              ))
          .toList(),
    );
  }

 
Widget _buildMealGroupCard(String mealLabel, List<dynamic> entries) {
  final color = _mealColor(mealLabel);

  // Only allow expand/collapse when there's more than 1 entry
  final bool canExpand = entries.length > 1;
  final bool isExpanded = canExpand && _expandedMeals.contains(mealLabel);

  // Show highest-calorie item in the collapsed preview (instead of .first)
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
          // Disable tap entirely when there's only 1 item
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
                Text(
                  mealLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: color),
                ),
                const Spacer(),
                Text(
                  '${entries.length} item${entries.length == 1 ? '' : 's'} · ${_groupCalories(entries)} kcal',
                  style: const TextStyle(
                      color: _Palette.inkMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
                // Only show the chevron when expand is possible
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: _Palette.card,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.80, // never taller than 80% of screen
            maxWidth: screenWidth * 0.92,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header (fixed, never scrolls) ──────────────────────────
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
                      child: Icon(_mealIcon(mealLabel), color: color, size: 22),
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

              // ── Calorie hero (fixed, never scrolls) ────────────────────
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

              // ── Nutrient grid (scrollable) ──────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: _buildNutrientGrid(entry),
                ),
              ),

              // ── Serving footer (fixed) ──────────────────────────────────
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


  IconData _mealIcon(String? meal) {
    switch (meal?.toLowerCase()) {
      case 'breakfast':
        return Icons.free_breakfast;
      case 'lunch':
        return Icons.lunch_dining;
      case 'dinner':
        return Icons.dinner_dining;
      default:
        return Icons.fastfood;
    }
  }

  
}