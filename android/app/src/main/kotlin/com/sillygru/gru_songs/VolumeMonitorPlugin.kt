package com.sillygru.gru_songs

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class VolumeMonitorPlugin : MethodCallHandler {
    private val methodChannel = "gru_songs/volume"
    private val eventChannel = "gru_songs/volume_events"
    private var eventSink: EventChannel.EventSink? = null
    private var audioManager: AudioManager? = null
    private var context: Context? = null
    private var volumeObserver: ContentObserver? = null
    private var volumeReceiver: BroadcastReceiver? = null
    
    private var lastVolume = -1f
    
    fun initialize(flutterEngine: FlutterEngine, context: Context) {
        this.context = context
        this.audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        // Setup method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannel).setMethodCallHandler(this)
        
        // Setup event channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    lastVolume = getCurrentVolume()
                    startListening()
                }
                
                override fun onCancel(arguments: Any?) {
                    stopListening()
                    eventSink = null
                }
            }
        )
    }
    
    private fun startListening() {
        if (volumeObserver == null) {
            volumeObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    checkAndNotifyVolumeChange()
                }
            }
            context?.contentResolver?.registerContentObserver(
                Settings.System.CONTENT_URI,
                true,
                volumeObserver!!
            )
        }
        
        if (volumeReceiver == null) {
            volumeReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    checkAndNotifyVolumeChange()
                }
            }
            val filter = IntentFilter().apply {
                addAction("android.media.VOLUME_CHANGED_ACTION")
                addAction("android.media.STREAM_MUTE_CHANGED_ACTION")
            }
            context?.registerReceiver(volumeReceiver, filter)
        }
    }
    
    private fun stopListening() {
        volumeObserver?.let {
            context?.contentResolver?.unregisterContentObserver(it)
            volumeObserver = null
        }
        volumeReceiver?.let {
            try {
                context?.unregisterReceiver(it)
            } catch (e: Exception) {
                // Ignore
            }
            volumeReceiver = null
        }
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getCurrentVolume" -> {
                result.success(getCurrentVolume())
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun getCurrentVolume(): Float {
        return audioManager?.let { am ->
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (am.isStreamMute(AudioManager.STREAM_MUSIC)) {
                    return 0f
                }
            }
            val currentVolume = am.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat()
            val maxVolume = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).toFloat()
            if (maxVolume > 0) currentVolume / maxVolume else 0f
        } ?: 1.0f
    }
    
    private fun checkAndNotifyVolumeChange() {
        val currentVolume = getCurrentVolume()
        if (currentVolume != lastVolume) {
            lastVolume = currentVolume
            eventSink?.success(currentVolume.toDouble())
        }
    }
    
    fun cleanup() {
        stopListening()
        eventSink = null
    }
}
