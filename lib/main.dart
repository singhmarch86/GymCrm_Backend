import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const GymCRMApp());
}

class GymCRMApp extends StatelessWidget {
  const GymCRMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GymCRM',
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
