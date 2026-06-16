import 'package:flutter/services.dart';
import 'package:healthshare/sync_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fatsecret_service.dart';
import 'health_connect_service.dart';

class BackgroundSyncService {
  static const MethodChannel _channel =
      MethodChannel('com.example.healthshare/sync');

  static bool _isSyncing = false;

  static Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sync') {
        await _doSync();
      }
    });
  }

  static Future<void> syncNow() async {
    await _doSync();
  }
    
  static Future<void> _doSync() async {
    if (_isSyncing) {
      print('Sync already in progress, skipping');
      return;
    }
    _isSyncing = true;
    await SyncNotificationService.showSyncing();

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

      // Add removed count to result for notification
      final removed = 0; // removeOrphanedEntries doesn't return a count yet
      await SyncNotificationService.showSyncComplete({
        ...result,
        'removed': removed,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync', DateTime.now().toIso8601String());

      print('Sync complete');
    } catch (e) {
      print('Sync error: $e');
      await SyncNotificationService.dismiss();
    } finally {
      _isSyncing = false;
    }
  }

  static Future<void> scheduleSync({int intervalMinutes = 30}) async {
    try {
      await _channel.invokeMethod('scheduleSync', {'intervalMinutes': intervalMinutes});
    } catch (e) {
      print('Error scheduling sync: $e');
    }
  }

  static Future<void> updateInterval(int intervalMinutes) async {
    try {
      await _channel.invokeMethod('updateInterval', {'intervalMinutes': intervalMinutes});
    } catch (e) {
      print('Error updating interval: $e');
    }
  }

  static Future<void> cancelSync() async {
    try {
      await _channel.invokeMethod('cancelSync');
    } catch (e) {
      print('Error cancelling sync: $e');
    }
  }
}