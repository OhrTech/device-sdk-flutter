# OhrTech Device SDK for Flutter

`ohrtech_device`: what an app on an OhrTech device can ask the OhrTech Agent for. Who the device is, the
app's own updates, Wi-Fi (with Android's Wi-Fi screen embedded in your layout), mobile data and airplane
mode, kiosk mode, power, settings, managed configuration, KEM keys and attestation in the device's TEE,
client certificates, pre-approved USB devices, its own events and logs, and push from your own server,
end to end.

**Documentation: <https://docs.ohrtech.net/device-sdk/>**

```yaml
dependencies:
  ohrtech_device: ^0.1.0
```

Android only, 13 (API 33) and up, on OhrTech devices with the OhrTech Agent 1059 or later. Set the app's
`minSdk = 33` in `android/app/build.gradle.kts`. It wraps the Kotlin library
([net.ohrtech:device-sdk](https://github.com/OhrTech/device-sdk-android)), so the Agent protocol and its
checks are the same as for Kotlin apps.

## Who may use what

The Agent answers apps your organisation installed through OhrTech; others get `OhrNotManaged`. Reading is
mostly always allowed. Changing something needs the fleet's grant for that area, set in the portal under
the fleet's apps: `wifi`, `network`, `kiosk`, `power`, `settings`. Settings and networks the fleet locks
stay locked (`OhrFleetLocked`).

## Use

```dart
import 'package:ohrtech_device/ohrtech_device.dart';

final info = await OhrDevice.info();                    // deviceId "dev_…", fleet, org, OS, Agent
if (await OhrAccess.mayUse('kiosk')) await OhrKiosk.start();
final sub = OhrWifi.stateChanges.listen((s) => print(s.ssid));   // cancel the subscription to stop
```

Each area is a class of static members; there is nothing to connect or close. The plugin binds the Agent on
the first call and keeps the binding; when the Agent stops (a crash, its own update) it binds again, and
every stream goes on. `OhrDeviceSdk.connectionChanges` says how it stands.

| Class | |
|---|---|
| `OhrDevice` | `info()`: device id, serial, fleet, org, OS version and patch, Agent version, online |
| `OhrUpdates` | `available()`, `install(whenIdle:)`, `changes`: the app's own updates the hub offers |
| `OhrWifi` | state, networks around, saved networks, `save`, `connect`, `forget`, `setEnabled`, `connectQr` |
| `OhrNetwork` | `state()`, `setMobileData`, `setAirplaneMode`, `setDataRoaming` |
| `OhrKiosk` | `start(features:)`, `stop()`, `state()`, `requestExit()`, `heartbeat()` |
| `OhrPower` | `battery()`, `reboot`, `scheduleReboot`, `setScreenTimeout`, `setBrightness` |
| `OhrSettings` | `keys()`, `get(key)`, `set(key, value)`: the device settings apps may change |
| `OhrConfig` | the app's managed configuration, as its fleet or device sets it |
| `OhrAttestation` | `attest(challenge)`, `token(audience)`: proof for your server of this app on this device |
| `OhrCertificates` | client certificates made on the device or imported; `client()` for HTTPS with them |
| `OhrUsb` | the USB devices the fleet pre-approves for the app: no permission prompt |
| `OhrDiagnostics` | the app's own events and log lines for the hub; crashes are reported without it |
| `OhrKeys` | TEE KEM keys: ML-KEM, X-Wing, X25519 for HPKE |
| `OhrPush` | end-to-end push: see below |

Every call can throw an `OhrException`, a sealed class: `OhrNotManaged`, `OhrNotAllowed(area)`,
`OhrFleetLocked(key)`, `OhrUnsupported(reason, needsAgent)`, `OhrInvalidConfig(field, reason)`,
`OhrRefused(reason)` or `OhrFailed(reason)`.

## The Wi-Fi screen

```dart
Expanded(
  child: OhrWifiView(
    theme: const OhrWifiTheme(accent: Colors.indigo),
    onConnected: (ssid) => print('joined $ssid'),
    onError: (e) => print(e.message),
  ),
)
```

The Agent draws Android's Wi-Fi screen inside the widget: no other activity or window opens, so a kiosk
app stays a kiosk. It is an Android view shown with hybrid composition; give it a bounded size.

## Kiosk heartbeat

`OhrKiosk.heartbeat()` beats from the Dart UI isolate: if it hangs for longer than the timeout, the Agent
stops the app and starts it again. Call it after `OhrKiosk.start()`.

## Push

Messages from your server, sealed to the device's TEE key and signed by your sender key; the OhrTech hub only
carries them. The handlers run in a background isolate, whether the app is open or not:

```dart
@pragma('vm:entry-point')
Future<void> onPushMessage(OhrPushMessage message) async {
  // message.data: your server's bytes, verified, opened, in date and not seen before
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OhrPush.setHandlers(onMessage: onPushMessage);
  runApp(const MyApp());
}

final token = await OhrPush.register([OhrSenderKey.fromBase64(ed25519PublicKey)]);
// Send token.token and token.publicKeyBase64 to your server.
```

The plugin declares the push service in its manifest; your app needs nothing more.

## Client certificates

The keys stay in the device's Android Keystore, which Dart's own TLS can't use, so make requests that need
the app's client certificate with the plugin's client (package:http), which goes through Android's:

```dart
final client = OhrCertificates.client(alias: 'orders');
final response = await client.get(Uri.parse('https://api.example.com/orders'));
```

It also trusts the private CAs the fleet gives the app. Bodies are sent and read whole.

## License

MIT
