import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fatsecret_service.dart';
import 'health_connect_service.dart';

class BackgroundSyncService {
  static const MethodChannel _channel = 
      MethodChannel('com.example.healthshare/sync');

  static Future<void> initialize() async {
    // Listen for background sync calls from WorkManager
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sync') {
        await _doSync();
      }
    });
  }

  static Future<void> _doSync() async {
    try {
      final fatSecret = FatSecretService();
      final healthConnect = HealthConnectService();

      // Load saved tokens
      final hasToken = await fatSecret.loadSavedTokens();
      if (!hasToken) return;

      // Check Health Connect permissions
      final hasPermission = await healthConnect.requestPermissions();
      if (!hasPermission) return;

      // Get today's entries
      final data = await fatSecret.getFoodEntries(DateTime.now());
      final raw = data['food_entries']?['food_entry'];
      if (raw == null) return;

      final entries = raw is List ? raw : [raw];
      await healthConnect.syncFoodEntries(entries);

      // Save last sync time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_sync', 
        DateTime.now().toIso8601String(),
      );

      print('Background sync complete');
    } catch (e) {
      print('Background sync error: $e');
    }
  }

  // Schedule periodic sync from Flutter side
  static Future<void> scheduleSync() async {
    try {
      await _channel.invokeMethod('scheduleSync');
    } catch (e) {
      print('Error scheduling sync: $e');
    }
  }

  // Cancel sync
  static Future<void> cancelSync() async {
    try {
      await _channel.invokeMethod('cancelSync');
    } catch (e) {
      print('Error cancelling sync: $e');
    }
  }
}