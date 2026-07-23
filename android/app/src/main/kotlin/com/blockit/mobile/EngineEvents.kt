package com.blockit.mobile

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * EngineEvents — a tiny process-wide bridge that lets the native services push
 * state-change tags to Flutter over the EventChannel
 * "com.blockit.mobile/engine_events". MainActivity registers the sink; the
 * accessibility / VPN / engine services call [emit] whenever they change
 * something the UI should re-read. Sink may be null when no UI is attached
 * (that's fine — enforcement doesn't depend on Flutter being alive).
 */
object EngineEvents {
    @Volatile
    private var sink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(newSink: EventChannel.EventSink?) {
        sink = newSink
    }

    fun emit(tag: String) {
        val s = sink ?: return
        mainHandler.post {
            try {
                s.success(tag)
            } catch (e: Exception) {
                // UI went away between the null-check and post — ignore.
            }
        }
    }
}
