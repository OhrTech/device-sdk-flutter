# Changelog

## 0.1.1 (2026-11-10)

Builds on net.ohrtech:device-sdk 0.3.2.

- A push message that doesn't reach your handler is no longer lost silently: the hub shows it as dropped, and its id is forgotten, so the sender may send it again (before, it was logged and counted as delivered). The reason says why:
  `app_no_handler` (`OhrPush.setHandlers` never ran), `app_no_engine` (the background isolate didn't start),
  `app_handler_timeout` (over 25 s) or `app_handler` (the handler threw, or its callback wasn't found after an update).
- `OhrDeviceSdk.connectionChanges` starts with how the connection stands for every listener, not only the first.
- `OhrCertificates.client` drops its cached TLS setup when the fleet changes the app's certificates (trusted CAs,
  bundles), not only after `request` or a renewal: with Agent 1061 or later, such a change applies to the next request.

## 0.1.0 (2026-11-09)

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
