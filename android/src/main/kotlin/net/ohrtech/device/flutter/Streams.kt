package net.ohrtech.device.flutter

import io.flutter.plugin.common.BinaryMessenger
import net.ohrtech.device.OhrCertificates
import net.ohrtech.device.OhrConfig
import net.ohrtech.device.OhrDeviceSdk
import net.ohrtech.device.OhrKiosk
import net.ohrtech.device.OhrListener
import net.ohrtech.device.OhrNetwork
import net.ohrtech.device.OhrPower
import net.ohrtech.device.OhrSettings
import net.ohrtech.device.OhrUpdates
import net.ohrtech.device.OhrUsb
import net.ohrtech.device.OhrWifi
import java.io.Closeable
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * One event channel per kind of change. The Dart side shares each as a broadcast stream, so a
 * channel has at most one listener: listening subscribes to the Agent, cancelling unsubscribes.
 */
internal class Streams(messenger: BinaryMessenger) : Closeable {
    private val handlers = listOf(
        Handler<OhrDeviceSdk.Connection, ConnectionInfo>({ e, l ->
            val now = OhrDeviceSdk.connection.value
            e.execute { l.onChange(now) }                       // the current state first
            OhrDeviceSdk.listenConnection(e, l)
        }) { c: OhrDeviceSdk.Connection -> ConnectionInfo(c.name) }.also { h ->
            ConnectionStreamHandler.register(messenger, object : ConnectionStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<ConnectionInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrUpdates::listen) { u: OhrUpdates.Update -> u.toPigeon() }.also { h ->
            UpdatesStreamHandler.register(messenger, object : UpdatesStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<UpdateInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrWifi::listenState) { s: OhrWifi.State -> s.toPigeon() }.also { h ->
            WifiStateStreamHandler.register(messenger, object : WifiStateStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<WifiStateInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrWifi::listenNetworks) { n: List<OhrWifi.Network> -> WifiNetworksInfo(n.toJson()) }.also { h ->
            WifiNetworksStreamHandler.register(messenger, object : WifiNetworksStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<WifiNetworksInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrNetwork::listen) { s: OhrNetwork.State -> s.toPigeon() }.also { h ->
            NetworkStateStreamHandler.register(messenger, object : NetworkStateStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<NetworkStateInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrKiosk::listenMode) { m: String -> KioskModeInfo(m) }.also { h ->
            KioskModeStreamHandler.register(messenger, object : KioskModeStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<KioskModeInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrPower::listenBattery) { b: OhrPower.Battery -> b.toPigeon() }.also { h ->
            BatteryStreamHandler.register(messenger, object : BatteryStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<BatteryInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrSettings::listen) { s: OhrSettings.Setting -> s.toPigeon() }.also { h ->
            SettingsStreamHandler.register(messenger, object : SettingsStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<SettingInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrConfig::listen) { b: android.os.Bundle -> ConfigInfo(b.toJson().toString()) }.also { h ->
            ConfigStreamHandler.register(messenger, object : ConfigStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<ConfigInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrCertificates::listen) { _: Unit -> CertificatesChangedInfo(true) }.also { h ->
            CertificatesStreamHandler.register(messenger, object : CertificatesStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<CertificatesChangedInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
        Handler(OhrUsb::listen) { c: OhrUsb.Change -> UsbChangeInfo(c.attached, c.device.toPigeon()) }.also { h ->
            UsbStreamHandler.register(messenger, object : UsbStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<UsbChangeInfo>) = h.listen(sink::success, sink::error)
                override fun onCancel(p0: Any?) = h.cancel()
            })
        },
    )

    override fun close() = handlers.forEach { it.cancel() }

    /**
     * One subscription at a time: [subscribe] is the library's listen(executor, listener), [map] the
     * value to send. Subscribing is a binder call, so it runs on a worker; events come on the main
     * thread, where the sink must be called.
     */
    private class Handler<T, P>(
        private val subscribe: (Executor, OhrListener<T>) -> Closeable,
        private val map: (T) -> P,
    ) {
        private var subscription: Closeable? = null

        @Volatile
        private var generation = 0

        @Synchronized
        fun listen(send: (P) -> Unit, error: (String, String?, Any?) -> Unit) {
            cancel()
            val mine = ++generation
            worker.execute {
                try {
                    val s = subscribe(mainExecutor) { v -> if (generation == mine) send(map(v)) }
                    synchronized(this) {
                        if (generation == mine) subscription = s else s.close()
                    }
                } catch (e: Exception) {
                    val f = e.toFlutter()
                    mainExecutor.execute { if (generation == mine) error(f.code, f.message, f.details) }
                }
            }
        }

        @Synchronized
        fun cancel() {
            generation++
            subscription?.let { s -> worker.execute { runCatching { s.close() } } }
            subscription = null
        }
    }

    private companion object {
        val worker: Executor = Executors.newCachedThreadPool { r -> Thread(r, "OhrDeviceStreams").apply { isDaemon = true } }
    }
}
