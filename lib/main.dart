/// BlockIT Mobile — entry point.
///
/// Android-only on-device app/website blocker, sibling to the Windows "BlockIT"
/// app. On launch it decides whether to show the permission-onboarding flow
/// (first run / permissions not granted) or the HomeScreen, then starts the
/// Dart block engine (which in turn spins up the Android foreground service that
/// keeps everything alive — the mobile equivalent of BlockIT's elevated tray
/// process).
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/block_engine_service.dart';
import 'theme/app_theme.dart';

/// shared_preferences flag key — the ONLY thing we keep in prefs (per the
/// spec: simple boot flags only; all real data lives in the JSON files).
const String kOnboardingCompleteKey = 'onboarding_complete';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool(kOnboardingCompleteKey) ?? false;

  if (onboarded) {
    // Best-effort start of the engine; onboarding starts it on completion.
    await BlockEngineService.instance.start();
  }

  runApp(BlockItApp(onboarded: onboarded));
}

class BlockItApp extends StatelessWidget {
  final bool onboarded;
  const BlockItApp({super.key, required this.onboarded});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlockIT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: onboarded ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
