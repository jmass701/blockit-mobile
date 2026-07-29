package com.blockit.mobile

import android.content.Context
import android.util.Base64
import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.InetSocketAddress
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

    private val lastSentAt = HashMap<String, Long>()

    /**
     * Fires off the alert on a background thread (SMTP over a blocking socket
     * must never run on the main/event thread) and returns immediately.
     * [reason] is a short machine key (e.g. "accessibility_disabled") used
     * both for the cooldown bucket and to pick the human-readable message.
     */
    fun sendAlert(context: Context, reason: String) {
        val now = System.currentTimeMillis()
        val last = lastSentAt[reason] ?: 0L
        if (now - last < COOLDOWN_MS) return
        lastSentAt[reason] = now

        // Snapshot everything we need from disk on the calling thread — the
        // Context reference itself shouldn't be captured across threads any
        // longer than necessary.
        val cfg = readConfig(context) ?: return
        Thread {
            try {
                send(cfg, reason)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send tamper alert for $reason", e)
            }
        }.start()
    }

    private data class MailConfig(
        val gmailAddress: String,
        val appPassword: String,
        val approverEmails: List<String>,
    )

    private fun readConfig(context: Context): MailConfig? {
        val cfg = JsonState.readConfigJson(context) ?: return null
        val address = cfg.optString("gmail_address", "").trim()
        val password = cfg.optString("gmail_app_password", "").trim()
        val approversArr = cfg.optJSONArray("approver_emails")
        val approvers = mutableListOf<String>()
        if (approversArr != null) {
            for (i in 0 until approversArr.length()) {
                val e = approversArr.optString(i, "").trim()
                if (e.isNotEmpty()) approvers.add(e)
            }
        }
        if (address.isEmpty() || password.isEmpty() || approvers.isEmpty()) return null
        return MailConfig(address, password, approvers)
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
        else -> Pair("BlockIT alert", "A tamper attempt ($reason) was detected on this device.")
    }

    private fun send(cfg: MailConfig, reason: String) {
        val (subject, body) = subjectAndBodyFor(reason)
        val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
        factory.createSocket().use { socket ->
            socket.connect(InetSocketAddress(SMTP_HOST, SMTP_PORT), 15_000)
            socket.soTimeout = 15_000
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
            val writer = PrintWriter(socket.getOutputStream(), true)

            fun readResponse(): String {
                val sb = StringBuilder()
                var line = reader.readLine()
                while (line != null) {
                    sb.append(line).append('\n')
                    // Multi-line SMTP responses use "250-" for all but the last line,
                    // which uses "250 ". Stop once we hit a line with a space at index 3.
                    if (line.length < 4 || line[3] != '-') break
                    line = reader.readLine()
                }
                return sb.toString()
            }

            fun command(cmd: String): String {
                writer.print(cmd + "\r\n")
                writer.flush()
                return readResponse()
            }

            readResponse() // server greeting
            command("EHLO blockit.mobile")
            command("AUTH LOGIN")
            command(Base64.encodeToString(cfg.gmailAddress.toByteArray(Charsets.UTF_8), Base64.NO_WRAP))
            command(Base64.encodeToString(cfg.appPassword.toByteArray(Charsets.UTF_8), Base64.NO_WRAP))
            command("MAIL FROM:<${cfg.gmailAddress}>")
            for (to in cfg.approverEmails) {
                command("RCPT TO:<$to>")
            }
            command("DATA")
            val toHeader = cfg.approverEmails.joinToString(", ")
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
            readResponse()
            command("QUIT")
        }
    }
}
