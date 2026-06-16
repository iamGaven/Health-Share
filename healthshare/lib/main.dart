import 'package:flutter/material.dart';
import 'package:healthshare/background_sync_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'fatsecret_service.dart';
import 'health_connect_service.dart';
import 'pages/food_diary_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthShare',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FatSecretService _fatSecret = FatSecretService();
  final HealthConnectService _healthConnect = HealthConnectService();

  String _status = 'Not connected';
  String _syncDetails = '';
  bool _isLoading = false;
  bool _isConnected = false;
  List<dynamic> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadSavedTokens();
    BackgroundSyncService.initialize();
  }

  // ─── Auth ─────────────────────────────────────────────────────

  Future<void> _loadSavedTokens() async {
    setState(() => _isLoading = true);
    final hasToken = await _fatSecret.loadSavedTokens();
    setState(() {
      _isConnected = hasToken;
      _status = hasToken ? 'Connected' : 'Not connected';
      _isLoading = false;
    });
    if (hasToken) {
      await BackgroundSyncService.scheduleSync();
      await _syncToHealthConnect();
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
        title: const Text('Enter FatSecret PIN'),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter PIN here'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
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
      final isValid = await _fatSecret.testConnection();
      setState(() {
        _isConnected = isValid;
        _status = isValid ? 'Connected' : 'Token expired — please reconnect';
      });
      if (isValid) await _syncToHealthConnect();
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
    setState(() => _isLoading = false);
  }

  // ─── Sync ─────────────────────────────────────────────────────

  Future<void> _syncToHealthConnect() async {
    setState(() => _isLoading = true);
    try {
      final hasPermission = await _healthConnect.requestPermissions();
      if (!hasPermission) {
        setState(() => _syncDetails = 'Health Connect permission denied');
        setState(() => _isLoading = false);
        return;
      }

      final data = await _fatSecret.getFoodEntries(DateTime.now());
      final raw = data['food_entries']?['food_entry'];

      if (raw == null) {
        setState(() => _syncDetails = 'No food entries today');
        setState(() => _isLoading = false);
        return;
      }

      final entries = raw is List ? raw : [raw];
      final result = await _healthConnect.syncFoodEntries(entries);

      setState(() {
        _entries = entries;
        _syncDetails =
            '${result['added']} added · ${result['skipped']} skipped · ${result['failed']} failed';
      });
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

  // ─── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: const Text('HealthShare',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Resync',
            onPressed: _isLoading ? null : _resync,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  if (!_isConnected) _buildConnectSection(),
                  if (_isConnected) _buildSyncSection(),
                  const SizedBox(height: 16),
                  if (_entries.isNotEmpty) _buildEntriesSection(),
                ],
              ),
            ),
    );
  }

  // ─── Widgets ──────────────────────────────────────────────────

  Widget _buildStatusCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isConnected
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _isConnected ? Icons.check_circle : Icons.link_off,
                color: _isConnected ? Colors.green : Colors.grey,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _status,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _isConnected ? Colors.green : Colors.grey.shade700,
                    ),
                  ),
                  if (_syncDetails.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _syncDetails,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Connect FatSecret',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              'Connect your FatSecret account to start syncing nutrition data to Google Health.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _connectFatSecret,
              icon: const Icon(Icons.link),
              label: const Text('Connect FatSecret'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _enterPin,
              icon: const Icon(Icons.pin),
              label: const Text('Enter PIN'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sync',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _syncToHealthConnect,
                    icon: const Icon(Icons.favorite),
                    label: const Text('Sync Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FoodDiaryPage(fatSecret: _fatSecret),
                      ),
                    ),
                    icon: const Icon(Icons.table_rows),
                    label: const Text('View Diary'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntriesSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.green.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Today's Food",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${_entries.length} items',
                    style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _entries.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, index) {
              final entry = _entries[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade50,
                  child: Icon(_mealIcon(entry['meal']),
                      color: Colors.green, size: 20),
                ),
                title: Text(
                  entry['food_entry_name'] ?? 'Unknown',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(entry['meal'] ?? '',
                    style: const TextStyle(fontSize: 12)),
                trailing: Text(
                  '${entry['calories']} kcal',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              );
            },
          ),
        ],
      ),
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