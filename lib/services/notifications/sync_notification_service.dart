import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SyncNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _syncNotificationId = 1;

  static Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    // Request permission — required on Android 13+
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      print('Notification permission granted: $granted');
    }
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
        ongoing: true,
        onlyAlertOnce: true,
        showWhen: false,
        icon: '@mipmap/ic_launcher',
        timeoutAfter: 15000,
      ),
    );

    await _plugin.show(
      _syncNotificationId,
      'HealthShare',
      'Syncing nutrition data...',
      details,
    );
    print('Sync notification shown');
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
  }

  static Future<void> dismiss() async {
    await _plugin.cancel(_syncNotificationId);
  }
}