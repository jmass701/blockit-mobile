package com.blockit.mobile

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * DebugLog — a small on-device ring-buffer log so the accessibility/VPN
 * enforcement services can be inspected without adb or root. Written to from
 * exactly the code paths that have been silently failing (accessibility
 * connect/disconnect, per-event package checks, VPN start/revoke), and read
 * back through a MethodChannel call so Settings can show it as plain
 * selectable text the user can copy and paste elsewhere.
 *
 * Deliberately dead simple (append + trim a text file) rather than a real
 * logging framework — this only needs to survive long enough to catch one
 * repro.
 */
object DebugLog {
    private const val FILE_NAME = "debug_log.txt"
    private const val MAX_LINES = 400
    private val formatter = SimpleDateFormat("MM-dd HH:mm:ss", Locale.US)

    @Synchronized
    fun log(context: Context, tag: String, message: String) {
        try {
            val f = file(context)
            f.appendText("${formatter.format(Date())} [$tag] $message\n")
            trim(f)
        } catch (e: Exception) {
            // Logging must never be the thing that crashes a caller.
        }
    }

    fun read(context: Context): String {
        return try {
            val f = file(context)
            if (!f.exists() || f.length() == 0L) "(empty — nothing logged yet)" else f.readText()
        } catch (e: Exception) {
            "(error reading log: ${e.message})"
        }
    }

    fun clear(context: Context) {
        try {
            file(context).writeText("")
        } catch (e: Exception) {
            // Ignore.
        }
    }

    private fun file(context: Context): File =
        File(context.getDir("app_flutter", Context.MODE_PRIVATE), FILE_NAME)

    private fun trim(f: File) {
        val lines = f.readLines()
        if (lines.size > MAX_LINES) {
            f.writeText(lines.takeLast(MAX_LINES).joinToString("\n", postfix = "\n"))
        }
    }
}
