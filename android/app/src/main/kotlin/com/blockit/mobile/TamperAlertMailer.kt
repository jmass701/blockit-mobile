package com.blockit.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Base64
import android.util.Log
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * TamperAlertMailer — sends a same-instant email to the approver(s) whenever
 * someone tries to remove or disable BlockIT on the device: opening the
 * uninstall confirmation screen, turning off the Accessibility service, or
 * revoking the VPN.
 *
 * Android gives no reliable way for a normal (non-Device-Owner) app to BLOCK
 * uninstallation — the OS always lets the device owner remove any app they
 * installed. This is the honest alternative: real-time notification instead
 * of a false promise of prevention, mirroring the existing Gmail approval
 * workflow used everywhere else in the app.
 *
 * This sends over a raw SMTPS socket rather than going through the Dart
 * mailer/enough_mail packages on purpose: the moment of tampering is exactly
 * when the Flutter engine is *least* likely to be alive (app backgrounded or
 * about to be killed), so this — like JsonState's direct file reads — must
 * not depend on the Dart isolate being resident. It reads config.json off
 * disk directly, the same file blocker's Dart StorageService writes.
 */
object TamperAlertMailer {
    private const val TAG = "TamperAlertMailer"
    private const val SMTP_HOST = "smtp.gmail.com"
    private const val SMTP_PORT = 465
    private const val COOLDOWN_MS = 60_000L // don't spam if a screen re-fires
    private const val RESULT_CHANNEL_ID = "blockit_tamper_alert_result"
    private const val RESULT_NOTIFICATION_ID = 1003

    private val lastSentAt = HashMap<String, Long>()

    /**
     * Fires off the alert on a background thread (SMTP over a blocking socket
     * must never run on the main/event thread) and returns immediately.
     * [reason] is a short machine key (e.g. "accessibility_disabled") used
     * both for the cooldown bucket and to pick the human-readable message.
     *
     * Posts a plain (non-ongoing) notification with the outcome — success or
     * the specific failure — so a failure is never silent. There's no other
     * place to surface this: the moment this fires is often exactly when the
     * Flutter UI isn't on screen to show an in-app error.
     *
     * [extraDetail] is optional free text appended to the email body — used
     * by the in-person PIN flow (called from Dart via MainActivity's
     * "sendTamperAlert") to say exactly what got unlocked, since "pin_unlock"
     * alone doesn't say which item.
     */
    fun sendAlert(context: Context, reason: String, extraDetail: String? = null) {
        val now = System.currentTimeMillis()
        val last = lastSentAt[reason] ?: 0L
        if (now - last < COOLDOWN_MS) return
        lastSentAt[reason] = now

        val appContext = context.applicationContext
        val cfg = readConfig(appContext)
        if (cfg == null) {
            postResultNotification(
                appContext, reason, success = false,
                detail = "No Gmail account / approver configured yet.",
            )
            return
        }
        Thread {
            try {
                send(cfg, reason, extraDetail)
                postResultNotification(appContext, reason, success = true, detail = null)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send tamper alert for $reason", e)
                postResultNotification(
                    appContext, reason, success = false,
                    detail = e.message ?: e.javaClass.simpleName,
                )
            }
        }.start()
    }

    private data class MailConfig(
        val gmailAddress: String,
        val appPassword: String,
        // Approver emails + carrier email-to-SMS gateway addresses, combined —
        // both are just RCPT TO targets for the same short alert message.
        val recipients: List<String>,
    )

    private fun readConfig(context: Context): MailConfig? {
        val cfg = JsonState.readConfigJson(context) ?: return null
        val address = cfg.optString("gmail_address", "").trim()
        val password = cfg.optString("gmail_app_password", "").trim()
        val recipients = mutableListOf<String>()
        cfg.optJSONArray("approver_emails")?.let { arr ->
            for (i in 0 until arr.length()) {
                val e = arr.optString(i, "").trim()
                if (e.isNotEmpty()) recipients.add(e)
            }
        }
        cfg.optJSONArray("tamper_alert_sms_gateways")?.let { arr ->
            for (i in 0 until arr.length()) {
                val e = arr.optString(i, "").trim()
                if (e.isNotEmpty() && e !in recipients) recipients.add(e)
            }
        }
        if (address.isEmpty() || password.isEmpty() || recipients.isEmpty()) return null
        return MailConfig(address, password, recipients)
    }

    private fun subjectAndBodyFor(reason: String): Pair<String, String> = when (reason) {
        "accessibility_disabled" -> Pair(
            "BlockIT alert: Accessibility permission was turned off",
            "BlockIT's Accessibility permission — required for app blocking — was just " +
                "disabled on this device. App blocking is no longer active until it's " +
                "re-enabled. Site blocking (VPN) is unaffected.",
        )
        "vpn_revoked" -> Pair(
            "BlockIT alert: Site blocking was turned off",
            "BlockIT's VPN — required for website blocking — was just disabled or revoked " +
                "on this device. Website blocking is no longer active until it's " +
                "re-enabled. App blocking is unaffected.",
        )
        "uninstall_attempt" -> Pair(
            "BlockIT alert: Someone tried to uninstall BlockIT",
            "Someone just opened the \"Uninstall BlockIT\" confirmation screen on this " +
                "device. BlockIT is still installed for now, but you may want to check in.",
        )
        "pin_unlock" -> Pair(
            "BlockIT alert: In-person PIN used to unlock something",
            "The in-person PIN was just used on this device to unlock a blocked app or " +
                "site immediately, without going through the usual email approval.",
        )
        else -> Pair("BlockIT alert", "A tamper attempt ($reason) was detected on this device.")
    }

    /**
     * Local (device-side) notification confirming what happened, shown on the
     * SAME phone as a diagnostic — not sent to the approver. Lets you verify
     * a tamper alert actually went out (or see exactly why it didn't) without
     * needing a computer + adb hooked up to read logs.
     */
    private fun postResultNotification(
        context: Context,
        reason: String,
        success: Boolean,
        detail: String?,
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                RESULT_CHANNEL_ID,
                "Tamper alert status",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = "Confirms whether a tamper alert email/text was sent." }
            nm.createNotificationChannel(channel)
        }
        val title = if (success) "Tamper alert sent" else "Tamper alert FAILED to send"
        val text = if (success) {
            "Notified your approver about: $reason"
        } else {
            "Reason: $reason. ${detail ?: "Unknown error."}"
        }
        val builder = Notification.Builder(context, RESULT_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(
                if (success) android.R.drawable.stat_sys_warning
                else android.R.drawable.stat_notify_error
            )
            .setAutoCancel(true)
        nm.notify(RESULT_NOTIFICATION_ID, builder.build())
    }

    /** Reads one SMTP response and throws if the status code isn't 2xx/3xx. */
    private fun BufferedReader.readSmtpResponse(context: String): String {
        val sb = StringBuilder()
        var line = readLine() ?: throw IOException("$context: connection closed unexpectedly")
        while (true) {
            sb.append(line).append('\n')
            // Multi-line SMTP responses use "250-" for all but the last line,
            // which uses "250 ". Stop once we hit a line with a space at index 3.
            if (line.length < 4 || line[3] != '-') break
            line = readLine() ?: throw IOException("$context: connection closed mid-response")
        }
        val code = sb.toString().take(3).toIntOrNull()
        if (code == null || code >= 400) {
            throw IOException("$context failed: ${sb.toString().trim()}")
        }
        return sb.toString()
    }

    private fun send(cfg: MailConfig, reason: String, extraDetail: String? = null) {
        val (subject, baseBody) = subjectAndBodyFor(reason)
        val body = if (extraDetail.isNullOrBlank()) baseBody else "$baseBody\n\n$extraDetail"

        // Connect a plain socket first (with a real, enforceable connect
        // timeout), THEN layer TLS on top of it — createSocket(host, port)
        // directly can hang indefinitely on a bad network, and the no-arg
        // createSocket()+connect() combo used previously doesn't reliably set
        // up SNI on all Android/JSSE versions, which some mail servers
        // (including Gmail) can reject during the handshake. Wrapping an
        // already-connected plain socket is the documented reliable pattern.
        val plain = Socket()
        plain.connect(InetSocketAddress(SMTP_HOST, SMTP_PORT), 15_000)
        val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
        val socket = factory.createSocket(plain, SMTP_HOST, SMTP_PORT, true) as SSLSocket
        socket.soTimeout = 15_000
        socket.use {
            it.startHandshake()
            val reader = BufferedReader(InputStreamReader(it.getInputStream(), Charsets.UTF_8))
            val writer = PrintWriter(it.getOutputStream(), true)

            fun command(cmd: String, label: String): String {
                writer.print(cmd + "\r\n")
                writer.flush()
                return reader.readSmtpResponse(label)
            }

            reader.readSmtpResponse("greeting")
            command("EHLO blockit.mobile", "EHLO")
            command("AUTH LOGIN", "AUTH LOGIN")
            command(
                Base64.encodeToString(cfg.gmailAddress.toByteArray(Charsets.UTF_8), Base64.NO_WRAP),
                "username",
            )
            command(
                Base64.encodeToString(cfg.appPassword.toByteArray(Charsets.UTF_8), Base64.NO_WRAP),
                "password (check the Gmail App Password in Settings)",
            )
            command("MAIL FROM:<${cfg.gmailAddress}>", "MAIL FROM")
            for (to in cfg.recipients) {
                command("RCPT TO:<$to>", "RCPT TO:<$to>")
            }
            command("DATA", "DATA")
            val toHeader = cfg.recipients.joinToString(", ")
            val message = buildString {
                append("From: BlockIT <${cfg.gmailAddress}>\r\n")
                append("To: $toHeader\r\n")
                append("Subject: $subject\r\n")
                append("Content-Type: text/plain; charset=UTF-8\r\n")
                append("\r\n")
                append(body)
                append("\r\n.\r\n")
            }
            writer.print(message)
            writer.flush()
            reader.readSmtpResponse("message body")
            command("QUIT", "QUIT")
        }
    }
}
