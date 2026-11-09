/// The OhrTech Device SDK for Flutter: what an app on an OhrTech device can ask the OhrTech Agent for.
///
/// Each area is a class of static members: [OhrDevice], [OhrUpdates], [OhrWifi] (and the [OhrWifiView]
/// widget), [OhrNetwork], [OhrKiosk], [OhrPower], [OhrSettings], [OhrConfig], [OhrAttestation],
/// [OhrCertificates], [OhrUsb], [OhrDiagnostics], [OhrKeys], [OhrPush]; [OhrAccess] says what the fleet
/// lets the app do. Every call can throw an [OhrException].
///
/// ```dart
/// final info = await OhrDevice.info();
/// if (await OhrAccess.mayUse('kiosk')) await OhrKiosk.start();
/// OhrWifi.stateChanges.listen((state) => print(state.ssid));
/// ```
library;

export 'src/areas.dart';
export 'src/core.dart' show OhrException, OhrNotManaged, OhrNotAllowed, OhrFleetLocked, OhrUnsupported, OhrInvalidConfig, OhrFailed, OhrRefused;
export 'src/push.dart' hide ohrPushDispatcher;
export 'src/security.dart';
export 'src/wifi.dart';
