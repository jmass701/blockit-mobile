package com.blockit.mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — hosts the Flutter UI and bridges it to the native blocking
 * layer via:
 *   * MethodChannel "com.blockit.mobile/engine" — start/stop the foreground
 *     engine service, prepare/start/stop the VPN, query/deep-link the
 *     accessibility + battery permissions, list installed apps.
 *   * EventChannel "com.blockit.mobile/engine_events" — native -> Flutter
 *     state-change pushes for live UI refresh (see EngineEvents).
 *
 * The method names here match lib/services/native_bridge.dart exactly.
 */
class MainActivity : FlutterActivity() {

    private val methodChannelName = "com.blockit.mobile/engine"
    private val eventChannelName = "com.blockit.mobile/engine_events"

    private val vpnRequestCode = 0x7A01
    private var pendingVpnResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "startEngine" -> {
                    EngineForegroundService.start(this)
                    result.success(null)
                }
                "stopEngine" -> {
                    EngineForegroundService.stop(this)
                    result.success(null)
                }
                "isEngineRunning" -> result.success(EngineForegroundService.isRunning)

                "prepareVpn" -> handlePrepareVpn(result)
                "startVpn" -> {
                    BlockVpnService.start(this)
                    result.success(null)
                }
                "stopVpn" -> {
                    BlockVpnService.stop(this)
                    result.success(null)
                }

                "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())
                "openAccessibilitySettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }

                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }

                "listInstalledApps" -> result.success(listInstalledApps())

                "notifyStateChanged" -> {
                    // The VPN re-reads on its own tick; nudge it and tell any UI.
                    BlockVpnService.refresh(this)
                    EngineEvents.emit("state_changed")
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    EngineEvents.attach(events)
                }

                override fun onCancel(arguments: Any?) {
                    EngineEvents.attach(null)
                }
            }
        )
    }

    // ---- VPN consent ----------------------------------------------------------

    private fun handlePrepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            // Consent already granted.
            result.success(true)
        } else {
            pendingVpnResult = result
            startActivityForResult(intent, vpnRequestCode)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnRequestCode) {
            val granted = resultCode == Activity.RESULT_OK
            if (granted) BlockVpnService.start(this)
            pendingVpnResult?.success(granted)
            pendingVpnResult = null
        }
    }

    // ---- Accessibility --------------------------------------------------------

    private fun isAccessibilityEnabled(): Boolean {
        val expected = "$packageName/${BlockAccessibilityService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next().equals(expected, ignoreCase = true)) return true
        }
        return false
    }

    // ---- Battery optimization -------------------------------------------------

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:$packageName"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    // ---- Installed apps -------------------------------------------------------

    private fun listInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN, null)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(launcherIntent, 0)
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, String>>()
        for (info in resolved) {
            val pkg = info.activityInfo.packageName ?: continue
            if (pkg == packageName) continue // don't offer to block ourselves
            if (!seen.add(pkg)) continue
            val label = info.loadLabel(pm).toString()
            out.add(mapOf("packageName" to pkg, "label" to label))
        }
        return out
    }
}
