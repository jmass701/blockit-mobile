package com.blockit.mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * BootReceiver — restarts the persistent engine foreground service (and, if VPN
 * consent was previously granted, the DNS-filter VPN) after the device reboots.
 * This mirrors the Windows app's ONLOGON scheduled task that relaunched the
 * blocker on every login, so protection resumes automatically without the user
 * reopening the app.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        EngineForegroundService.start(context)
        // BlockVpnService.prepare() consent survives reboot; start() is a no-op
        // if consent was revoked (establish() returns null and it stops itself).
        BlockVpnService.start(context)
    }
}
