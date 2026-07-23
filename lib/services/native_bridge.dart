/// NativeBridge — thin Dart wrapper over the MethodChannel/EventChannel that
/// connect Flutter to the Android native layer.
///
/// MethodChannel "com.blockit.mobile/engine":
///   Flutter -> native:  startEngine, stopEngine, isEngineRunning,
///                       prepareVpn, startVpn, stopVpn,
///                       isAccessibilityEnabled, openAccessibilitySettings,
///                       requestIgnoreBatteryOptimizations, listInstalledApps
///   native  -> Flutter: (none — pushes go over the EventChannel)
///
/// EventChannel "com.blockit.mobile/engine_events": native pushes a bare String
/// tag (e.g. "state_changed", "app_blocked") whenever the accessibility/VPN
/// services mutate something, so the UI can live-refresh. Mirrors the Windows
/// dashboard's 4s poll + focus/visibility refresh, but event-driven.
library;

import 'package:flutter/services.dart';

/// One installed app, as returned by the native PackageManager query.
class InstalledApp {
  final String packageName;
  final String label;
  const InstalledApp({required this.packageName, required this.label});

  factory InstalledApp.fromMap(Map<dynamic, dynamic> m) => InstalledApp(
        packageName: (m['packageName'] ?? '').toString(),
        label: (m['label'] ?? m['packageName'] ?? '').toString(),
      );
}

class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.blockit.mobile/engine');
  static const EventChannel _events =
      EventChannel('com.blockit.mobile/engine_events');

  /// Broadcast of native-originated state-change tags. UIs listen and refresh.
  Stream<String> get engineEvents =>
      _events.receiveBroadcastStream().map((e) => e.toString());

  // ---- Foreground engine service -------------------------------------------

  Future<void> startEngine() => _invoke('startEngine');
  Future<void> stopEngine() => _invoke('stopEngine');
  Future<bool> isEngineRunning() async =>
      (await _channel.invokeMethod<bool>('isEngineRunning')) ?? false;

  // ---- VPN (site blocking) --------------------------------------------------

  /// Triggers VpnService.prepare() consent. Returns true if already granted
  /// (no dialog needed); false means the consent dialog is being shown and the
  /// caller should await the result via [prepareVpnResult].
  Future<bool> prepareVpn() async =>
      (await _channel.invokeMethod<bool>('prepareVpn')) ?? false;

  Future<void> startVpn() => _invoke('startVpn');
  Future<void> stopVpn() => _invoke('stopVpn');

  // ---- Accessibility (app blocking) ----------------------------------------

  Future<bool> isAccessibilityEnabled() async =>
      (await _channel.invokeMethod<bool>('isAccessibilityEnabled')) ?? false;

  Future<void> openAccessibilitySettings() =>
      _invoke('openAccessibilitySettings');

  // ---- Permissions ----------------------------------------------------------

  Future<bool> isIgnoringBatteryOptimizations() async =>
      (await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ??
      false;

  Future<void> requestIgnoreBatteryOptimizations() =>
      _invoke('requestIgnoreBatteryOptimizations');

  // ---- Installed-apps picker ------------------------------------------------

  /// Lists launchable installed apps via PackageManager (native side), used by
  /// the "add app to block" picker. More reliable than a plugin.
  Future<List<InstalledApp>> listInstalledApps() async {
    final raw = await _channel
        .invokeMethod<List<dynamic>>('listInstalledApps');
    if (raw == null) return [];
    return raw
        .map((e) => InstalledApp.fromMap(e as Map<dynamic, dynamic>))
        .toList()
      ..sort((a, b) =>
          a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  /// Tells the native services to re-read the JSON files immediately (e.g. right
  /// after the engine changes locks), so enforcement reacts without waiting.
  Future<void> notifyStateChanged() => _invoke('notifyStateChanged');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod(method);
    } on PlatformException {
      // Swallow — callers treat native failures as "feature not available yet"
      // during onboarding rather than crashing.
    }
  }
}
