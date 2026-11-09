# Changelog

## 0.1.0 (unreleased)

The first release: every area of the OhrTech Device SDK (net.ohrtech:device-sdk 0.3.1) for Flutter on
Android, needing the OhrTech Agent 1059 or later (1061 for diagnostics, USB devices, certificates and the
kiosk exit PIN).

- Static classes per area: `OhrDevice`, `OhrUpdates`, `OhrWifi`, `OhrNetwork`, `OhrKiosk`, `OhrPower`,
  `OhrSettings`, `OhrConfig`, `OhrAttestation`, `OhrCertificates`, `OhrUsb`, `OhrDiagnostics`, `OhrKeys`,
  `OhrPush`; `OhrAccess` and `OhrDeviceSdk` (the connection). Changes as broadcast streams.
- `OhrWifiView`: the Agent's Wi-Fi screen as a widget (hybrid composition).
- Push handled by top-level functions in a background isolate, whether the app is open or not.
- `OhrCertificates.client()`: a package:http client with the app's client certificate and trusted CAs,
  over Android's TLS (the keys live in the Android Keystore).
- `OhrKiosk.heartbeat()` beats from the Dart UI isolate, so the Agent's watchdog sees it hang.
