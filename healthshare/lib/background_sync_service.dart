import 'package:flutter/services.dart';
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
      await healthConnect.syncFoodEntries(entries);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_sync', DateTime.now().toIso8601String());

      print('Sync complete');
    } catch (e) {
      print('Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  static Future<void> scheduleSync() async {
    try {
      await _channel.invokeMethod('scheduleSync');
    } catch (e) {
      print('Error scheduling sync: $e');
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