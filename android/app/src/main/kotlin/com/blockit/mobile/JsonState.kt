package com.blockit.mobile

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/**
 * JsonState — reads the SAME config.json / blocklist.json / state.json files
 * that the Dart StorageService writes, straight off disk. The accessibility and
 * VPN services must react instantly and must not depend on the Flutter engine
 * being alive, so they read these files directly rather than round-tripping
 * over a MethodChannel.
 *
 * The directory here — context.getDir("flutter", MODE_PRIVATE) — is exactly
 * what path_provider's getApplicationDocumentsDirectory() returns on Android
 * (Flutter engine's PathUtils.getDataDirectory() calls getDir("flutter", ...)
 * internally), so both sides resolve the identical files.
 *
 * IMPORTANT: Android's Context.getDir(name, mode) auto-prefixes the folder it
 * creates with "app_" — getDir("flutter", ...) is what actually produces the
 * on-disk folder named "app_flutter". Passing "app_flutter" as the name (as
 * this used to) makes Android create/read "app_app_flutter" instead — a
 * silently different, permanently-empty directory. That mismatch was the
 * root cause of app/site blocking (and tamper alerts) never firing: this
 * native side was reading a directory Dart never wrote to.
 *
 * Ports blocker_common.item_key() and is_item_unlocked() so the lock decision
 * matches the Dart/Python logic byte-for-byte.
 */
object JsonState {

    private fun dataDir(context: Context): File =
        context.getDir("flutter", Context.MODE_PRIVATE)

    private fun readJson(context: Context, name: String): JSONObject {
        val f = File(dataDir(context), name)
        if (!f.exists()) return JSONObject()
        return try {
            val text = f.readText()
            if (text.isBlank()) JSONObject() else JSONObject(text)
        } catch (e: Exception) {
            JSONObject()
        }
    }

    /**
     * Public read of config.json, for callers (e.g. TamperAlertMailer) that need
     * the Gmail address/app password/approver list straight off disk, the same
     * way this object already reads blocklist.json/state.json directly.
     * Returns null if the file doesn't exist yet (not configured).
     */
    fun readConfigJson(context: Context): JSONObject? {
        val f = File(dataDir(context), "config.json")
        if (!f.exists()) return null
        return try {
            val text = f.readText()
            if (text.isBlank()) null else JSONObject(text)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * True if the "strict" adult-content DNS filter is turned on in
     * config.json. Read fresh each time (like everything else here) so
     * BlockVpnService picks up an enable/disable within one refresh cycle.
     */
    fun adultContentFilterEnabled(context: Context): Boolean =
        readConfigJson(context)?.optBoolean("adult_content_filter_enabled", false) ?: false

    /** item_key(kind, target) == "kind:target.trim().lowercase()". */
    fun itemKey(kind: String, target: String): String =
        "$kind:${target.trim().lowercase()}"

    /** Ported from is_item_unlocked(): unlocked if indefinite, or now < until. */
    private fun isItemUnlocked(state: JSONObject, key: String): Boolean {
        val unlocks = state.optJSONObject("unlocks") ?: return false
        val info = unlocks.optJSONObject(key) ?: return false
        if (info.optBoolean("unlocked_indefinitely", false)) return true
        val until = info.optString("unlocked_until", "")
        if (until.isBlank() || until == "null") return false
        return try {
            // Dart writes a local (no-offset) ISO string; compare wall-clock.
            val cleaned = until.substringBefore('Z')
            val dt = LocalDateTime.parse(cleaned, DateTimeFormatter.ISO_LOCAL_DATE_TIME)
            LocalDateTime.now().isBefore(dt)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * The set of package names currently LOCKED (blocked and not unlocked),
     * lowercased. Mirrors main_loop()'s locked_apps computation.
     */
    fun lockedAppPackages(context: Context): Set<String> {
        val blocklist = readJson(context, "blocklist.json")
        val state = readJson(context, "state.json")
        val procs = blocklist.optJSONArray("blocked_processes") ?: return emptySet()
        val out = HashSet<String>()
        for (i in 0 until procs.length()) {
            val target = targetOf(procs.opt(i)) ?: continue
            if (!isItemUnlocked(state, itemKey("app", target))) {
                out.add(target.lowercase())
            }
        }
        return out
    }

    /**
     * The set of domains currently LOCKED, lowercased. Mirrors main_loop()'s
     * locked_domains computation.
     */
    fun lockedDomains(context: Context): Set<String> {
        val blocklist = readJson(context, "blocklist.json")
        val state = readJson(context, "state.json")
        val domains = blocklist.optJSONArray("blocked_domains") ?: return emptySet()
        val out = HashSet<String>()
        for (i in 0 until domains.length()) {
            val target = targetOf(domains.opt(i)) ?: continue
            if (!isItemUnlocked(state, itemKey("site", target))) {
                out.add(target.trim().lowercase())
            }
        }
        return out
    }

    /**
     * A blocklist entry is stored as an object {"target","name"} by the Dart
     * side, but tolerate a bare string too (legacy / Windows-style).
     */
    private fun targetOf(entry: Any?): String? = when (entry) {
        is String -> entry
        is JSONObject -> entry.optString("target", "").ifBlank { null }
        else -> null
    }
}
