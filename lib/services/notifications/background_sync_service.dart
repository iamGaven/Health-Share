import 'package:flutter/services.dart';
import 'package:healthshare/services/notifications/sync_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../fatsecret_service.dart';
import '../health_connect_service.dart';


@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await SyncNotificationService.initializeForBackground();
      await _runSync();
      return true;
    } catch (e) {
      print('Background task error: $e');
      return true; 
    }
  });
}


Future<void> _runSync() async {
    await SyncNotificationService.showSyncing(); // ← add this

  final fatSecret = FatSecretService();
  final healthConnect = HealthConnectService();

  final hasToken = await fatSecret.loadSavedTokens();
  if (!hasToken) return;

  final hasPermission = await healthConnect.requestPermissions();
  if (!hasPermission) return;

  final data = await fatSecret.getFoodEntries(DateTime.now());
  final raw = data['food_entries']?['food_entry'];
  if (raw == null) return;

  final entries = raw is List ? raw : [raw];
  await healthConnect.removeOrphanedEntries(entries, DateTime.now());
  final result = await healthConnect.syncFoodEntries(entries);

  await SyncNotificationService.showSyncComplete({
    ...result,
    'removed': 0,
  });

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('last_sync', DateTime.now().toIso8601String());
}

class BackgroundSyncService {
  static bool _isSyncing = false;

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> syncNow({bool silent = false}) async {
    if (_isSyncing) {
      print('Sync already in progress, skipping');
      return;
    }
    _isSyncing = true;
    if (!silent) await SyncNotificationService.showSyncing();

    try {
      final fatSecret = FatSecretService();
      final healthConnect = HealthConnectService();

      final hasToken = await fatSecret.loadSavedTokens();
      if (!hasToken) return;

      final hasPermission = await healthConnect.requestPermissions();
      if (!hasPermission) return;

      final data = await fatSecret.getFoodEntries(DateTime.now());
      final raw = data['food_entries']?['food_entry'];
      if (raw == null) {
        print('No food entries for today');
        return;
      }

      final entries = raw is List ? raw : [raw];
      await healthConnect.removeOrphanedEntries(entries, DateTime.now());
      final result = await healthConnect.syncFoodEntries(entries);

      if (!silent) {
        await SyncNotificationService.showSyncComplete({
          ...result,
          'removed': 0,
        });
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync', DateTime.now().toIso8601String());

      print('Sync complete');
    } catch (e) {
      print('Sync error: $e');
      if (!silent) await SyncNotificationService.dismiss();
    } finally {
      _isSyncing = false;
    }
  }

    
  static Future<void> scheduleSync({int intervalMinutes = 30}) async {
    final interval = intervalMinutes < 15 ? 15 : intervalMinutes;
    await Workmanager().registerPeriodicTask(
      'healthshare_sync',
      'sync',
      frequency: Duration(minutes: interval),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    print('Sync scheduled every $interval minutes');
  }

  static Future<void> updateInterval(int intervalMinutes) async {
    final interval = intervalMinutes < 15 ? 15 : intervalMinutes;
    await Workmanager().registerPeriodicTask(
      'healthshare_sync',
      'sync',
      frequency: Duration(minutes: interval),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    print('Sync interval updated to $interval minutes');
  }

  static Future<void> cancelSync() async {
    await Workmanager().cancelByUniqueName('healthshare_sync');
    print('Sync cancelled');
  }

}