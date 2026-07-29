package com.sillygru.wispie

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Reports whether the device is in battery-saver mode, and pushes changes as
 * they happen.
 *
 * The app uses this to thin out the player's animation — fewer motes, half the
 * frame rate — when the system says the user is trying to make the battery
 * last. Shaped like [VolumeMonitorPlugin]: one method channel for the current
 * value, one event channel for changes.
 */
class PowerStatePlugin : MethodCallHandler {
    private val methodChannel = "wispie/power"
    private val eventChannel = "wispie/power_events"

    private var eventSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var powerManager: PowerManager? = null
    private var receiver: BroadcastReceiver? = null

    fun initialize(flutterEngine: FlutterEngine, context: Context) {
        this.context = context
        this.powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel)
            .setMethodCallHandler(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startListening()
                }

                override fun onCancel(arguments: Any?) {
                    stopListening()
                    eventSink = null
                }
            }
        )
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isPowerSaveMode" -> result.success(isPowerSaveMode())
            else -> result.notImplemented()
        }
    }

    private fun isPowerSaveMode(): Boolean = powerManager?.isPowerSaveMode ?: false

    private fun startListening() {
        if (receiver != null) return

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                eventSink?.success(isPowerSaveMode())
            }
        }
        context?.registerReceiver(
            receiver,
            IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        )
    }

    private fun stopListening() {
        receiver?.let {
            try {
                context?.unregisterReceiver(it)
            } catch (e: Exception) {
                // Already gone; nothing to undo.
            }
            receiver = null
        }
    }

    fun cleanup() {
        stopListening()
        eventSink = null
    }
}
