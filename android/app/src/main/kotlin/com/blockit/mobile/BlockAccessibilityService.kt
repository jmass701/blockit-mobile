package com.blockit.mobile

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * BlockAccessibilityService — app blocking. This is the Android equivalent of
 * blocker.py's "kill any running process that's on the blocklist" loop: on every
 * TYPE_WINDOW_STATE_CHANGED event it reads the foreground package name and, if
 * that package is currently LOCKED (on the blocklist and not individually
 * unlocked), immediately performs GLOBAL_ACTION_HOME to eject the user, then
 * shows the full-screen "Blocked" activity.
 *
 * It reads the lock set straight from blocklist.json / state.json via JsonState
 * (NOT over a MethodChannel) so it reacts instantly and works even when the
 * Flutter engine isn't running — the same reason enforcement on Windows lives in
 * the always-on background process, not the dashboard.
 */
class BlockAccessibilityService : AccessibilityService() {

    // Debounce so we don't spawn the Blocked screen repeatedly for the same app
    // within a single foreground stint.
    private var lastBlockedPackage: String? = null
    private var lastBlockedAt: Long = 0L

    // Package names Android's uninstall confirmation dialog / app-info screen
    // can appear under, across AOSP and the common OEM skins.
    private val installerPackages = setOf(
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.android.settings",
        "com.samsung.android.packageinstaller",
    )

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return

        // Tamper detection: someone opened the system uninstall-confirmation
        // dialog (or the app-info page, which is where the Uninstall button
        // lives) with BlockIT as the subject. This can't reliably distinguish
        // "just looking" from "about to confirm," so it errs toward alerting
        // and immediately backing out — same trade-off as blocking a locked
        // app. It won't catch every path (a determined user could disable
        // Accessibility first) but that itself fires its own alert below.
        if (pkg in installerPackages) {
            val text = event.text?.joinToString(" ") ?: ""
            val cls = event.className?.toString() ?: ""
            val mentionsUs = text.contains("BlockIT", ignoreCase = true) ||
                (cls.contains("InstalledAppDetails", ignoreCase = true) &&
                    text.contains(appLabel(packageName), ignoreCase = true))
            if (mentionsUs && (cls.contains("Uninstall", ignoreCase = true) ||
                    text.contains("uninstall", ignoreCase = true))
            ) {
                TamperAlertMailer.sendAlert(this, "uninstall_attempt")
                performGlobalAction(GLOBAL_ACTION_HOME)
                return
            }
        }

        // Ignore our own UI and the system launcher/home.
        if (pkg == packageName) return

        val locked = JsonState.lockedAppPackages(this)
        if (!locked.contains(pkg.lowercase())) {
            // User navigated away from a blocked app — reset the debounce.
            if (pkg != lastBlockedPackage) lastBlockedPackage = null
            return
        }

        val now = System.currentTimeMillis()
        val isRepeat = pkg == lastBlockedPackage && (now - lastBlockedAt) < 1500
        lastBlockedPackage = pkg
        lastBlockedAt = now

        // Kick the user out immediately.
        performGlobalAction(GLOBAL_ACTION_HOME)
        EngineEvents.emit("app_blocked")

        if (!isRepeat) {
            val label = appLabel(pkg)
            val intent = Intent(this, BlockedOverlayActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(BlockedOverlayActivity.EXTRA_APP_LABEL, label)
            try {
                startActivity(intent)
            } catch (e: Exception) {
                // If we can't launch the overlay (rare), the HOME action already
                // removed the user from the blocked app — that's the hard part.
            }
        }
    }

    private fun appLabel(pkg: String): String {
        return try {
            val pm = packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (e: Exception) {
            pkg
        }
    }

    override fun onInterrupt() {
        // No-op — we don't hold any interruptible feedback.
    }

    /**
     * Called when the system tears this service down — most relevantly, right
     * when the user disables BlockIT's Accessibility permission from Settings.
     * This is the authoritative signal (unlike the uninstall-screen heuristic
     * above), so it's the primary way "someone turned off app blocking" gets
     * reported, not just a best-effort guess.
     */
    override fun onDestroy() {
        TamperAlertMailer.sendAlert(this, "accessibility_disabled")
        super.onDestroy()
    }
}
