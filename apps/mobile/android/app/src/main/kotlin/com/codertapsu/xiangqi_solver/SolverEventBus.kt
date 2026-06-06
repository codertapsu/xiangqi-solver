package com.codertapsu.xiangqi_solver

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Process-wide bridge that lets the native services push events to the Flutter
 * EventChannel, even when the Dart listener has not attached its sink yet.
 *
 * Design:
 *  - A single [EventChannel.EventSink] reference, guarded by [lock].
 *  - A thread-safe [pending] queue buffers events emitted before the sink is
 *    attached (e.g. an overlay tap that fires while the engine is detached).
 *  - Every delivery is marshalled onto the main thread, as required by the
 *    Flutter platform-channel API.
 *
 * This is a singleton because the services run in the same process as the
 * FlutterEngine and must reach the one active sink without holding an Activity
 * reference (avoids leaks).
 */
object SolverEventBus {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val pending = ConcurrentLinkedQueue<Map<String, Any?>>()

    @Volatile
    private var sink: EventChannel.EventSink? = null

    /** Called by the EventChannel StreamHandler when Dart starts listening. */
    fun attach(newSink: EventChannel.EventSink) {
        synchronized(lock) {
            sink = newSink
        }
        flushPending()
    }

    /** Called by the StreamHandler when Dart cancels (engine detached). */
    fun detach() {
        synchronized(lock) {
            sink = null
        }
    }

    /**
     * Emit a typed event. [type] becomes the "type" key; [extra] supplies the
     * remaining payload. Safe to call from any thread.
     */
    fun emit(type: String, extra: Map<String, Any?> = emptyMap()) {
        val event = HashMap<String, Any?>(extra.size + 1)
        event[Constants.KEY_TYPE] = type
        event.putAll(extra)
        dispatch(event)
    }

    private fun dispatch(event: Map<String, Any?>) {
        val current = synchronized(lock) { sink }
        if (current == null) {
            // No listener yet: buffer and deliver once the sink attaches.
            pending.add(event)
            return
        }
        postToSink(current, event)
    }

    private fun flushPending() {
        val current = synchronized(lock) { sink } ?: return
        while (true) {
            val event = pending.poll() ?: break
            postToSink(current, event)
        }
    }

    private fun postToSink(target: EventChannel.EventSink, event: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            safeSuccess(target, event)
        } else {
            mainHandler.post { safeSuccess(target, event) }
        }
    }

    private fun safeSuccess(target: EventChannel.EventSink, event: Map<String, Any?>) {
        // Guard against a race where the sink was cancelled between scheduling
        // and execution: only deliver if it is still the active sink.
        val current = synchronized(lock) { sink }
        if (current === target) {
            runCatching { target.success(event) }
        }
    }
}
