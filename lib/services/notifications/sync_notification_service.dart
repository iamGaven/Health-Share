import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SyncNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _syncNotificationId = 1;
  static Timer? _dismissTimer;

  static Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      print('Notification permission granted: $granted');
    }
  }

  static Future<void> initializeForBackground() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
  }

  static void _scheduleDismiss({int seconds = 10}) {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(Duration(seconds: seconds), () {
      _plugin.cancel(_syncNotificationId);
      print('Notification auto-dismissed after ${seconds}s');
    });
  }

  static Future<void> showSyncing() async {
    print('Showing sync notification...');
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sync_channel',
        'Sync Status',
        channelDescription: 'Shows when a background sync is in progress',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        onlyAlertOnce: true,
        showWhen: false,
        icon: '@mipmap/ic_launcher',
        autoCancel: true,
      ),
    );

    await _plugin.show(
      _syncNotificationId,
      'HealthShare',
      'Syncing nutrition data...',
      details,
    );
    print('Sync notification shown');
    _scheduleDismiss();
  }

  static Future<void> showSyncComplete(Map<String, int> result) async {
    print('Showing sync complete notification...');
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sync_channel',
        'Sync Status',
        channelDescription: 'Shows when a background sync is in progress',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        onlyAlertOnce: true,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
        autoCancel: true,
      ),
    );

    final added = result['added'] ?? 0;
    final removed = result['removed'] ?? 0;

    final message = [
      if (added > 0) '$added added',
      if (removed > 0) '$removed removed',
      if (added == 0 && removed == 0) 'Nothing changed',
    ].join(' · ');

    await _plugin.show(
      _syncNotificationId,
      'HealthShare Sync Complete',
      message,
      details,
    );
    print('Sync complete notification shown: $message');
    _scheduleDismiss();
  }

  static Future<void> dismiss() async {
    _dismissTimer?.cancel();
    await _plugin.cancel(_syncNotificationId);
  }
}