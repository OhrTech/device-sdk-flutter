package net.ohrtech.device.flutter

import android.content.Context
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import net.ohrtech.device.OhrWifiView

/**
 * The Agent's Wi-Fi screen as a platform view. It is a SurfaceView drawn above the window, so the
 * Dart side shows it with hybrid composition. Each view has a method channel for its events
 * ("connected", "error") and theme changes ("setTheme").
 */
internal class WifiViewFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        val channel = MethodChannel(messenger, "net.ohrtech.device/wifi_view_$viewId")
        val view = OhrWifiView(context).apply {
            options = options(params["options"])
            theme = theme(params["theme"])
            listener = object : OhrWifiView.Listener {
                override fun onConnected(ssid: String) = channel.invokeMethod("connected", ssid)
                override fun onError(error: Exception) {
                    val f = error.toFlutter()
                    channel.invokeMethod("error", mapOf("code" to f.code, "message" to f.message, "details" to f.details))
                }
            }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setTheme" -> {
                    view.theme = theme(call.arguments)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        return object : PlatformView {
            override fun getView(): View = view
            override fun dispose() = channel.setMethodCallHandler(null)
        }
    }

    companion object {
        const val TYPE = "net.ohrtech.device/wifi_view"

        private fun Map<*, *>.bool(name: String, default: Boolean) = this[name] as? Boolean ?: default
        private fun Map<*, *>.color(name: String) = (this[name] as? Number)?.toInt()

        fun options(value: Any?): OhrWifiView.Options {
            val m = value as? Map<*, *> ?: return OhrWifiView.Options()
            return OhrWifiView.Options(m.bool("wifiSwitch", true), m.bool("addNetwork", true), m.bool("enterprise", true),
                m.bool("forget", true), m.bool("saved", true))
        }

        fun theme(value: Any?): OhrWifiView.Theme {
            val m = value as? Map<*, *> ?: return OhrWifiView.Theme()
            return OhrWifiView.Theme(m["dark"] as? Boolean, m.color("accent"), m.color("background"), m.color("text"),
                (m["cornerRadiusDp"] as? Number)?.toFloat())
        }
    }
}
