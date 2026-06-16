import 'package:flutter/material.dart';
import 'package:healthshare/background_sync_service.dart';
import 'pages/home_page.dart';
import 'sync_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SyncNotificationService.initialize();
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