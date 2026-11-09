package net.ohrtech.device.flutter

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import net.ohrtech.device.OhrAccess
import net.ohrtech.device.OhrAttestation
import net.ohrtech.device.OhrCertificates
import net.ohrtech.device.OhrConfig
import net.ohrtech.device.OhrDevice
import net.ohrtech.device.OhrDeviceSdk
import net.ohrtech.device.OhrDiagnostics
import net.ohrtech.device.OhrException
import net.ohrtech.device.OhrKiosk
import net.ohrtech.device.OhrNetwork
import net.ohrtech.device.OhrPower
import net.ohrtech.device.OhrSettings
import net.ohrtech.device.OhrUpdates
import net.ohrtech.device.OhrUsb
import net.ohrtech.device.OhrWifi
import net.ohrtech.device.keys.OhrKeys
import net.ohrtech.device.push.OhrPush
import org.json.JSONArray
import org.json.JSONObject

/**
 * The OhrTech Device SDK for Flutter: the Dart API's Android side, over the Kotlin library
 * (net.ohrtech:device-sdk). It attaches to every engine, the app's and push's background one.
 */
class OhrDevicePlugin : FlutterPlugin, ActivityAware {
    private var messenger: BinaryMessenger? = null
    private var streams: Streams? = null

    @Volatile
    internal var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        OhrDeviceSdk.init(context)
        messenger = binding.binaryMessenger
        OhrHostApi.setUp(binding.binaryMessenger, HostApi(this, context))
        OhrPushBackgroundHostApi.setUp(binding.binaryMessenger, PushDispatcher)
        streams = Streams(binding.binaryMessenger)
        binding.platformViewRegistry.registerViewFactory(WifiViewFactory.TYPE, WifiViewFactory(binding.binaryMessenger))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        OhrHostApi.setUp(binding.binaryMessenger, null)
        OhrPushBackgroundHostApi.setUp(binding.binaryMessenger, null)
        streams?.close()
        streams = null
        messenger = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}

private class HostApi(private val plugin: OhrDevicePlugin, private val context: Context) : OhrHostApi {
    // The connection and access
    override suspend fun connect(timeoutMs: Long) = io { OhrDeviceSdk.connectBlocking(timeoutMs) }
    override fun isAvailable(): Boolean = local { OhrDeviceSdk.isAvailable() }
    override fun connectionState(): String = OhrDeviceSdk.connection.value.name
    override suspend fun accessInfo(): AccessInfo = io { OhrAccess.info().toPigeon() }

    // Device and updates
    override suspend fun deviceInfo(): DeviceInfo = io { OhrDevice.info().toPigeon() }
    override suspend fun updatesAvailable(): UpdateInfo? = io { OhrUpdates.available()?.toPigeon() }
    override suspend fun updatesInstall(whenIdle: Boolean) = io { OhrUpdates.install(whenIdle) }

    // Wi-Fi
    override suspend fun wifiState(): WifiStateInfo = io { OhrWifi.state().toPigeon() }
    override suspend fun wifiNetworks(): String = io { OhrWifi.networks().toJson() }
    override suspend fun wifiScan() = io { OhrWifi.scan() }
    override suspend fun wifiSaved(): String = io { JSONArray(OhrWifi.saved()).toString() }
    override suspend fun wifiSave(configJson: String): String = io { OhrWifi.save(config(configJson)) }
    override suspend fun wifiConnect(keyOrIdentity: String) = io { OhrWifi.connect(keyOrIdentity) }
    override suspend fun wifiConnectConfig(configJson: String): String = io { OhrWifi.connect(config(configJson)) }
    override suspend fun wifiDisconnect() = io { OhrWifi.disconnect() }
    override suspend fun wifiForget(identity: String) = io { OhrWifi.forget(identity) }
    override suspend fun wifiSetEnabled(on: Boolean) = io { OhrWifi.setEnabled(on) }
    override suspend fun wifiConnectQr(text: String): String = io { OhrWifi.connectQr(text) }

    private fun config(json: String): JSONObject = try {
        JSONObject(json)
    } catch (e: org.json.JSONException) {
        throw OhrException.InvalidConfig("config", "not a JSON object: ${e.message}")
    }

    // Network
    override suspend fun networkState(): NetworkStateInfo = io { OhrNetwork.state().toPigeon() }
    override suspend fun networkSetMobileData(on: Boolean) = io { OhrNetwork.setMobileData(on) }
    override suspend fun networkSetAirplaneMode(on: Boolean) = io { OhrNetwork.setAirplaneMode(on) }
    override suspend fun networkSetDataRoaming(on: Boolean) = io { OhrNetwork.setDataRoaming(on) }

    // Kiosk
    override suspend fun kioskStart(features: Long) = io {
        val a = plugin.activity ?: throw OhrException.Failed("kiosk mode needs the app's activity, which this engine has none of")
        OhrKiosk.start(a, features.toInt())
    }

    override suspend fun kioskStop() = io { OhrKiosk.stop() }
    override suspend fun kioskState(): KioskStateInfo = io { OhrKiosk.state().toPigeon() }
    override suspend fun kioskRequestExit() = io { OhrKiosk.requestExit() }
    override fun kioskBeat(timeoutMs: Long) = local { OhrKiosk.beat(timeoutMs) }
    override fun kioskStopHeartbeat() = local { OhrKiosk.stopHeartbeat() }

    // Power
    override suspend fun powerBattery(): BatteryInfo = io { OhrPower.battery().toPigeon() }
    override suspend fun powerReboot(reason: String) = io { OhrPower.reboot(reason) }
    override suspend fun powerScheduleReboot(schedule: RebootScheduleInfo?) = io { OhrPower.scheduleReboot(schedule?.toSdk()) }
    override suspend fun powerRebootSchedule(): RebootScheduleInfo? = io { OhrPower.rebootSchedule()?.toPigeon() }
    override suspend fun powerSetScreenTimeout(seconds: Long) = io { OhrPower.setScreenTimeout(seconds.toInt()) }
    override suspend fun powerSetBrightness(percent: Long) = io { OhrPower.setBrightness(percent.toInt()) }

    // Settings
    override suspend fun settingsKeys(): List<String> = io { OhrSettings.keys() }
    override suspend fun settingsGet(key: String): SettingInfo = io { OhrSettings.get(key).toPigeon() }
    override suspend fun settingsSet(key: String, valueJson: String) = io {
        val value = try {
            parseJson(valueJson)
        } catch (e: org.json.JSONException) {
            throw OhrException.InvalidConfig(key, "not JSON: ${e.message}")
        }
        OhrSettings.set(key, value)
    }

    // Managed configuration (local: Android's application restrictions)
    override fun configValues(): ConfigInfo = local { ConfigInfo(OhrConfig.values().toJson().toString()) }
    override fun configString(key: String, fallback: String?): String? = local { OhrConfig.string(key, fallback) }
    override fun configInt(key: String, fallback: Long): Long = local { OhrConfig.int(key, fallback.toInt()).toLong() }
    override fun configBool(key: String, fallback: Boolean): Boolean = local { OhrConfig.bool(key, fallback) }
    override fun configStrings(key: String): List<String> = local { OhrConfig.strings(key) }
    override fun configIsSet(key: String): Boolean = local { OhrConfig.isSet(key) }

    // Attestation
    override suspend fun attestationAttest(challenge: ByteArray, suite: String): AttestationInfo =
        io { OhrAttestation.attest(challenge, suiteOf(suite)).toPigeon() }

    override suspend fun attestationToken(audience: String, ttlSeconds: Long, nonce: String?): String =
        io { OhrAttestation.token(audience, ttlSeconds, nonce) }

    override suspend fun attestationSuite(): String? = io { OhrAttestation.suite?.wire() }

    // Certificates
    override suspend fun certificatesCanRequest(): Boolean = io { OhrCertificates.canRequest() }
    override suspend fun certificatesRequest(alias: String, timeoutMs: Long): CertificateInfo =
        io { OhrCertificates.request(alias, timeoutMs).toPigeon().also { Http.forget() } }

    override suspend fun certificatesRenewIfDue(alias: String): CertificateInfo? =
        io { OhrCertificates.renewIfDue(alias)?.toPigeon()?.also { Http.forget() } }

    override suspend fun certificatesList(): List<CertificateInfo> = io { OhrCertificates.list().map { it.toPigeon() } }
    override suspend fun httpSend(request: HttpRequestData): HttpResponseData = io { Http.send(request) }

    // USB
    override suspend fun usbDevices(): List<UsbDeviceInfo> = io { OhrUsb.devices().map { it.toPigeon() } }

    // Diagnostics
    override suspend fun diagnosticsEvent(name: String, dataJson: String) = io {
        val data = try {
            JSONObject(dataJson)
        } catch (e: org.json.JSONException) {
            throw OhrException.InvalidConfig("data", "not a JSON object: ${e.message}")
        }
        OhrDiagnostics.event(name, data)
    }

    override suspend fun diagnosticsLog(priority: Long, tag: String, message: String) =
        io { OhrDiagnostics.log(priority.toInt(), tag, message) }

    // Keys
    override suspend fun keysIsAvailable(): Boolean = io { OhrKeys.isAvailable() }
    override suspend fun keysGenerate(alias: String, algorithm: String): ByteArray = io { OhrKeys.generate(alias, algorithmOf(algorithm)) }
    override suspend fun keysList(): List<KeyInfoData> =
        io { OhrKeys.list().map { KeyInfoData(it.alias, it.algorithm.standardName, it.createdAtMs) } }

    override suspend fun keysPublicKey(alias: String): ByteArray? = io { OhrKeys.publicKey(alias) }
    override suspend fun keysDelete(alias: String) = io { OhrKeys.delete(alias) }
    override suspend fun keysDecapsulate(alias: String, ciphertext: ByteArray): ByteArray = io { OhrKeys.decapsulate(alias, ciphertext) }
    override suspend fun keysEncapsulate(algorithm: String, publicKey: ByteArray): EncapsulatedData =
        io { OhrKeys.encapsulate(algorithmOf(algorithm), publicKey).let { EncapsulatedData(it.ciphertext, it.sharedSecret) } }

    override suspend fun keysHpkeOpen(alias: String, kdf: Long, aead: Long, enc: ByteArray, info: ByteArray, aad: ByteArray,
                                      ciphertext: ByteArray): ByteArray =
        io { OhrKeys.hpkeOpen(alias, kdf.toInt(), aead.toInt(), enc, info, aad, ciphertext) }

    override suspend fun keysAttest(alias: String, challenge: ByteArray): KeyAttestationData = io {
        OhrKeys.attest(alias, challenge).let { KeyAttestationData(it.algorithm.standardName, it.publicKey, it.owner, it.coseSign1, it.diceChain) }
    }

    // Push
    override suspend fun pushRegister(senderKeys: List<SenderKeyData>, suite: String): PushTokenData = io {
        val s = OhrPush.Suite.named(suite) ?: throw OhrException.InvalidConfig("suite", "x25519 or xwing-mldsa65")
        OhrPush.register(senderKeys.map { it.toSdk() }, s).toPigeon()
    }

    override suspend fun pushToken(): PushTokenData? = io { OhrPush.token()?.toPigeon() }
    override suspend fun pushUnregister() = io { OhrPush.unregister() }
    override fun pushSetSenderKeys(keys: List<SenderKeyData>) = local { OhrPush.setSenderKeys(keys.map { it.toSdk() }) }
    override fun pushSenderKeys(): List<SenderKeyData> = local { OhrPush.senderKeys().map { it.toPigeon() } }
    override fun pushSetHandlers(dispatcher: Long, onMessage: Long, onTokenChanged: Long, onDropped: Long) =
        PushDispatcher.setHandlers(context, PushDispatcher.Handles(dispatcher, onMessage, onTokenChanged, onDropped))
}
