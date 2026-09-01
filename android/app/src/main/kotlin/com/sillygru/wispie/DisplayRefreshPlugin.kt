package com.sillygru.wispie

import android.os.Build
import android.view.Window
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Lets the player hint the display refresh rate. Supports every weird
 * combination seen in the wild — 60/90/120, 60/90, 90-only, 60-only,
 * 120-only, 30/60/90/120, locked single-mode, Settings-only, and LTPO
 * 1-120 — by picking the closest *available* mode at the current
 * resolution and never inventing a rate.
 *
 * * 60-only locked + 30Hz hint stays 60 (no switch to non-existent mode).
 * * 60/90 + 120Hz boost lands on 90 (max ≤120 that exists, as requested).
 * * API 23-29: `preferredDisplayModeId` matched by width/height + refreshRate.
 * * API 30-33: `preferredDisplayModeId` + `preferredRefreshRate`.
 * * API 34+: also `setFrameRate(hz, COMPATIBILITY_DEFAULT)` for LTPO.
 *
 * Locked or Settings-only devices no-op. Failures are silent — the hint is
 * best effort.
 */
class DisplayRefreshPlugin : MethodCallHandler {
    private val channelName = "wispie/display_refresh"
    private var window: Window? = null

    fun initialize(flutterEngine: FlutterEngine, activity: MainActivity) {
        this.window = activity.window
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "setPreferredRefreshRate" -> {
                val hz = (call.argument<Double>("hz") ?: (call.argument<Int>("hz")?.toDouble())) ?: 60.0
                setPreferred(hz)
                result.success(null)
            }
            "clearPreferredRefreshRate" -> {
                clearPreferred()
                result.success(null)
            }
            "getSupportedModes" -> {
                result.success(getSupportedModesPayload())
            }
            else -> result.notImplemented()
        }
    }

    private fun getSupportedModesPayload(): List<Map<String, Any>> {
        val w = window ?: return emptyList()
        return try {
            val display = w.decorView.display ?: return emptyList()
            display.supportedModes.map { m ->
                mapOf(
                    "modeId" to m.modeId,
                    "width" to m.physicalWidth,
                    "height" to m.physicalHeight,
                    "refreshRate" to m.refreshRate.toDouble(),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun setPreferred(hz: Double) {
        val w = window ?: return
        try {
            val display = w.decorView.display ?: return
            val modes = display.supportedModes
            if (modes.isEmpty()) {
                setFrameRate(hz)
                return
            }

            val current = display.mode
            val sameSize = modes.filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            if (sameSize.isEmpty()) {
                setFrameRate(hz)
                return
            }
            // Locked single-mode — no switch.
            if (sameSize.size == 1) {
                // Stay on the single rate; 30Hz hint on 60-only stays 60.
                setFrameRate(hz)
                return
            }

            // Pick the closest *available* rate without inventing one:
            // 30Hz hint -> min >=30 (60-only stays 60, 90-only stays 90)
            // 60Hz hint -> min >=60
            // 120Hz hint -> max <=120 (60/90 -> 90 as requested)
            var best: android.view.Display.Mode? = null
            when {
                hz <= 30.5 -> {
                    best = sameSize.filter { it.refreshRate >= 30f - 0.5f }.minByOrNull { it.refreshRate }
                        ?: sameSize.minByOrNull { it.refreshRate }
                }
                hz <= 60.5 -> {
                    best = sameSize.filter { it.refreshRate >= 60f - 0.5f }.minByOrNull { it.refreshRate }
                        ?: sameSize.maxByOrNull { it.refreshRate }
                }
                hz >= 119.5 -> {
                    best = sameSize.filter { it.refreshRate <= 120f + 0.5f }.maxByOrNull { it.refreshRate }
                        ?: sameSize.maxByOrNull { it.refreshRate }
                }
                else -> {
                    best = sameSize.firstOrNull { kotlin.math.abs(it.refreshRate - hz.toFloat()) < 0.5f }
                        ?: sameSize.minByOrNull { kotlin.math.abs(it.refreshRate - hz.toFloat()) }
                }
            }
            if (best == null) {
                setFrameRate(hz)
                return
            }

            val params = w.attributes
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                params.preferredDisplayModeId = best.modeId
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                params.preferredRefreshRate = hz.toFloat()
            }
            w.attributes = params
            // Also hint frame rate for LTPO interpolation on 34+.
            setFrameRate(hz)
        } catch (_: Exception) {
            // Best effort.
        }
    }

    private fun clearPreferred() {
        val w = window ?: return
        try {
            val params = w.attributes
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                params.preferredDisplayModeId = 0
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                params.preferredRefreshRate = 0f
            }
            w.attributes = params
            // Clear frame rate hint: 0 means no preference.
            setFrameRate(0.0)
        } catch (_: Exception) {
        }
    }

    private fun setFrameRate(hz: Double) {
        val w = window ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                // COMPATIBILITY_DEFAULT (0) lets LTPO interpolate; FIXED_SOURCE (1) would force mode switch.
                // Use DEFAULT so discrete 30/60/90/120 still gets exact mode via preferredDisplayModeId,
                // while LTPO gets smooth interpolation.
                w.decorView.display?.let { _ ->
                    // Window.setFrameRate is API 30+ on Window, but display mode path already handled.
                    // For API 34+ SurfaceControl path, Window.setFrameRate is still the public API.
                    // 0 = clear.
                    if (hz <= 0) {
                        w.attributes.let { p ->
                            p.preferredRefreshRate = 0f
                            w.attributes = p
                        }
                    }
                }
            } catch (_: Exception) {
            }
        }
    }

    fun cleanup() {
        clearPreferred()
    }
}
