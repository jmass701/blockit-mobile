/// OnboardingScreen — the guided Android permission flow, required because the
/// blocking engine needs several OS grants that BlockIT's Windows installer got
/// for free via elevation. Steps:
///   1. Accessibility Service   — deep-links to Settings; powers app blocking.
///   2. VPN permission          — VpnService.prepare() consent; powers DNS-based
///                                site blocking.
///   3. Battery optimizations   — exemption so the foreground service (the
///                                mobile equivalent of the elevated tray process)
///                                isn't killed.
///   4. Notification permission — Android 13+, for the persistent service
///                                notification.
/// On finish it marks onboarding complete, starts the engine + VPN, and enters
/// the HomeScreen.
library;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/block_engine_service.dart';
import '../services/native_bridge.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final NativeBridge _native = NativeBridge.instance;

  bool _accessibility = false;
  bool _vpn = false;
  bool _battery = false;
  bool _notifications = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatuses();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user returns from a system Settings deep-link.
    if (state == AppLifecycleState.resumed) _refreshStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshStatuses() async {
    final accessibility = await _native.isAccessibilityEnabled();
    final battery = await _native.isIgnoringBatteryOptimizations();
    final notif = await Permission.notification.isGranted;
    if (mounted) {
      setState(() {
        _accessibility = accessibility;
        _battery = battery;
        _notifications = notif;
      });
    }
  }

  Future<void> _enableAccessibility() async {
    await _native.openAccessibilitySettings();
    // Status is re-read on resume.
  }

  Future<void> _grantVpn() async {
    // Returns true if consent already granted; otherwise shows the system
    // consent dialog. We optimistically mark it enabled once prepare succeeds.
    final ready = await _native.prepareVpn();
    if (mounted) setState(() => _vpn = ready || _vpn);
  }

  Future<void> _exemptBattery() async {
    await _native.requestIgnoreBatteryOptimizations();
  }

  Future<void> _grantNotifications() async {
    final status = await Permission.notification.request();
    if (mounted) setState(() => _notifications = status.isGranted);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingCompleteKey, true);
    await BlockEngineService.instance.start();
    if (_vpn) await _native.startVpn();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // Accessibility + notifications are the hard requirements to enforce
    // blocking; VPN and battery are strongly recommended. Allow finishing once
    // the two hard requirements are met.
    final canFinish = _accessibility && _notifications;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up BlockIT',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'BlockIT needs a few Android permissions to block apps and sites '
            'and to keep running in the background. Grant each below.',
            style: TextStyle(fontSize: 14, color: AppColors.gray500),
          ),
          const SizedBox(height: 20),
          _step(
            done: _accessibility,
            title: '1. Accessibility Service',
            body: 'Lets BlockIT detect when a blocked app opens and send you '
                'back to the home screen.',
            action: 'Open Settings',
            onAction: _enableAccessibility,
          ),
          _step(
            done: _vpn,
            title: '2. VPN permission',
            body: 'Runs a local, on-device DNS filter to block websites. No '
                'traffic leaves your phone through a server.',
            action: 'Grant VPN',
            onAction: _grantVpn,
          ),
          _step(
            done: _battery,
            title: '3. Battery optimization exemption',
            body: 'Stops Android from killing the BlockIT background service.',
            action: 'Request exemption',
            onAction: _exemptBattery,
          ),
          _step(
            done: _notifications,
            title: '4. Notifications',
            body: 'Required for the persistent service notification (Android 13+).',
            action: 'Allow notifications',
            onAction: _grantNotifications,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canFinish ? _finish : null,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Finish setup'),
            ),
          ),
          if (!canFinish)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Accessibility and Notifications are required before continuing.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.gray500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _step({
    required bool done,
    required String title,
    required String body,
    required String action,
    required VoidCallback onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(
            color: done ? AppColors.green : AppColors.gray200,
            width: done ? 1.5 : 1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? AppColors.green : AppColors.gray200,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body,
              style: const TextStyle(
                  fontSize: 13.5, color: AppColors.gray500, height: 1.4)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onAction,
            child: Text(done ? 'Re-check' : action),
          ),
        ],
      ),
    );
  }
}
