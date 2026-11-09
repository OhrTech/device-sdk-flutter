package net.ohrtech.device.flutter

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.ohrtech.device.OhrAccess
import net.ohrtech.device.OhrAttestation
import net.ohrtech.device.OhrCertificates
import net.ohrtech.device.OhrDevice
import net.ohrtech.device.OhrException
import net.ohrtech.device.OhrKiosk
import net.ohrtech.device.OhrNetwork
import net.ohrtech.device.OhrPower
import net.ohrtech.device.OhrSettings
import net.ohrtech.device.OhrUpdates
import net.ohrtech.device.OhrUsb
import net.ohrtech.device.OhrWifi
import net.ohrtech.device.keys.OhrKeys
import net.ohrtech.device.push.OhrPushMessage
import net.ohrtech.device.push.PushToken
import net.ohrtech.device.push.SenderKey
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.util.concurrent.Executor

/** Android's main thread: where event sinks and method channels must be called. */
internal val mainExecutor = Executor { r -> Handler(Looper.getMainLooper()).post(r) }

/** [OhrException] as the error the Dart side turns back into its OhrException. */
internal fun Throwable.toFlutter(): OhrFlutterError = when (this) {
    is OhrFlutterError -> this
    is OhrException.NotManaged -> OhrFlutterError("NotManaged", message, null)
    is OhrException.NotAllowed -> OhrFlutterError("NotAllowed", message, mapOf("area" to area))
    is OhrException.FleetLocked -> OhrFlutterError("FleetLocked", message, mapOf("key" to key))
    is OhrException.Unsupported -> OhrFlutterError("Unsupported", message, mapOf("reason" to reason, "needsAgent" to needsAgent))
    is OhrException.InvalidConfig -> OhrFlutterError("InvalidConfig", message, mapOf("field" to field, "reason" to reason))
    is OhrException.Refused -> OhrFlutterError("Refused", message, mapOf("reason" to reason))
    is OhrException.Failed -> OhrFlutterError("Failed", message, mapOf("reason" to reason))
    else -> OhrFlutterError("Failed", message ?: toString(), mapOf("reason" to (message ?: toString())))
}

/** Runs [block] off the main thread, with its errors as [OhrFlutterError]. */
internal suspend fun <T> io(block: () -> T): T = withContext(Dispatchers.IO) {
    try {
        block()
    } catch (e: Exception) {
        throw e.toFlutter()
    }
}

/** The same, for the synchronous calls (made on the main thread, needing no Agent). */
internal inline fun <T> local(block: () -> T): T = try {
    block()
} catch (e: Exception) {
    throw e.toFlutter()
}

internal fun OhrAccess.Info.toPigeon() =
    AccessInfo(app, packageName, appVersion, areas.sorted(), agentVersion, agentInterface.toLong())

internal fun OhrDevice.Info.toPigeon() = DeviceInfo(
    deviceId, serial, fleet?.let { NamedInfo(it.id, it.name) }, org?.let { NamedInfo(it.id, it.name) },
    osRelease, osBuild, securityPatch, osIncremental, agentVersion, online,
)

internal fun OhrUpdates.Update.toPigeon() = UpdateInfo(versionCode, versionName, notes, downloaded)

internal fun OhrWifi.State.toPigeon() = WifiStateInfo(enabled, state, connected?.toString())

internal fun List<OhrWifi.Network>.toJson(): String = JSONArray(map { it.json }).toString()

internal fun OhrNetwork.State.toPigeon() = NetworkStateInfo(
    active?.let { ActiveNetworkInfo(it.transport, it.validated, it.captive, it.metered, it.vpn) },
    mobileData, airplaneMode, dataRoaming, ethernetConnected,
)

internal fun OhrKiosk.State.toPigeon() = KioskStateInfo(pinned, mode, features.toLong(), appMayExit)

internal fun OhrPower.Battery.toPigeon() = BatteryInfo(level?.toLong(), charging, plugged, health, temperatureC, screenOn)

internal fun OhrPower.Schedule.toPigeon() = RebootScheduleInfo(time, days.sorted().map { it.toLong() }, reason)

internal fun RebootScheduleInfo.toSdk() = OhrPower.Schedule(time, days.map { it.toInt() }.toSet(), reason)

/** A JSON value as text: null, a string, a number, a boolean, an array or an object. */
internal fun jsonText(value: Any?): String = when (value) {
    null, JSONObject.NULL -> "null"
    is String -> JSONObject.quote(value)
    else -> JSONObject.wrap(value).toString()
}

internal fun parseJson(text: String): Any? = JSONTokener(text).nextValue().takeUnless { it == JSONObject.NULL }

internal fun OhrSettings.Setting.toPigeon() = SettingInfo(key, jsonText(value), mode)

/** A Bundle of managed configuration as JSON: bundles as objects, bundle arrays as lists. */
@Suppress("DEPRECATION")
internal fun Bundle.toJson(): JSONObject = JSONObject().also { o ->
    for (k in keySet().sorted()) {
        o.put(k, when (val v = get(k)) {
            is Bundle -> v.toJson()
            is Array<*> -> JSONArray(v.map { if (it is Bundle) it.toJson() else it })
            null -> JSONObject.NULL
            else -> v
        })
    }
}

internal fun suiteOf(name: String): OhrAttestation.Suite = when (name) {
    "ec" -> OhrAttestation.Suite.EC
    "ec-mldsa65" -> OhrAttestation.Suite.EC_MLDSA65
    else -> throw OhrException.InvalidConfig("suite", "ec or ec-mldsa65")
}

internal fun OhrAttestation.Suite.wire() = name.lowercase().replace('_', '-')

internal fun OhrAttestation.Attestation.toPigeon() =
    AttestationInfo(suite.wire(), ec.map { it.encoded }, mlDsa65?.map { it.encoded }, toJson().toString())

internal fun OhrCertificates.Certificate.toPigeon() =
    CertificateInfo(alias, paths.map { p -> CertificatePathInfo(p.map { it.encoded }) }, imported)

internal fun OhrUsb.Device.toPigeon() = UsbDeviceInfo(
    accessory, deviceName, vendorId.toLong(), productId.toLong(), manufacturer, product, model, version, serial, name, hasPermission,
)

internal fun algorithmOf(name: String): OhrKeys.Algorithm = OhrKeys.Algorithm.named(name)

internal fun SenderKeyData.toSdk() = SenderKey(ed25519, mlDsa65)

internal fun SenderKey.toPigeon() = SenderKeyData(ed25519, mlDsa65)

internal fun PushToken.toPigeon() = PushTokenData(token, suite.wireName, publicKey)

internal fun OhrPushMessage.toPigeon() = PushMessageData(id, data, expiresAtMs, highPriority, pushId)
