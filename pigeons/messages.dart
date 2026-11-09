// The plugin's messages between Dart and the Android side. Generate with:
//   dart run pigeon --input pigeons/messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  dartPackageName: 'ohrtech_device',
  kotlinOut: 'android/src/main/kotlin/net/ohrtech/device/flutter/Messages.g.kt',
  kotlinOptions: KotlinOptions(package: 'net.ohrtech.device.flutter', errorClassName: 'OhrFlutterError'),
))
class AccessInfo {
  AccessInfo(this.app, this.packageName, this.appVersion, this.areas, this.agentVersion, this.agentInterface);
  String app;
  String packageName;
  String? appVersion;
  List<String> areas;
  int agentVersion;
  int agentInterface;
}

class NamedInfo {
  NamedInfo(this.id, this.name);
  String id;
  String name;
}

class DeviceInfo {
  DeviceInfo(this.deviceId, this.serial, this.fleet, this.org, this.osRelease, this.osBuild, this.securityPatch,
      this.osIncremental, this.agentVersion, this.online);
  String? deviceId;
  String? serial;
  NamedInfo? fleet;
  NamedInfo? org;
  String osRelease;
  String osBuild;
  String securityPatch;
  String osIncremental;
  int agentVersion;
  bool online;
}

class UpdateInfo {
  UpdateInfo(this.versionCode, this.versionName, this.notes, this.downloaded);
  int versionCode;
  String? versionName;
  String? notes;
  bool downloaded;
}

/// Wi-Fi state; [connectedJson] the current network as the Agent's JSON, or null.
class WifiStateInfo {
  WifiStateInfo(this.enabled, this.state, this.connectedJson);
  bool enabled;
  String state;
  String? connectedJson;
}

/// The networks around, as the Agent's JSON list.
class WifiNetworksInfo {
  WifiNetworksInfo(this.json);
  String json;
}

class ActiveNetworkInfo {
  ActiveNetworkInfo(this.transport, this.validated, this.captive, this.metered, this.vpn);
  String transport;
  bool validated;
  bool captive;
  bool metered;
  bool vpn;
}

class NetworkStateInfo {
  NetworkStateInfo(this.active, this.mobileData, this.airplaneMode, this.dataRoaming, this.ethernetConnected);
  ActiveNetworkInfo? active;
  bool mobileData;
  bool airplaneMode;
  bool dataRoaming;
  bool ethernetConnected;
}

class KioskStateInfo {
  KioskStateInfo(this.pinned, this.mode, this.features, this.appMayExit);
  bool pinned;
  String mode;
  int features;
  bool appMayExit;
}

class KioskModeInfo {
  KioskModeInfo(this.mode);
  String mode;
}

class BatteryInfo {
  BatteryInfo(this.level, this.charging, this.plugged, this.health, this.temperatureC, this.screenOn);
  int? level;
  bool charging;
  String? plugged;
  String health;
  double temperatureC;
  bool screenOn;
}

class RebootScheduleInfo {
  RebootScheduleInfo(this.time, this.days, this.reason);
  String time;
  List<int> days;
  String reason;
}

/// A setting; [valueJson] its value as JSON.
class SettingInfo {
  SettingInfo(this.key, this.valueJson, this.mode);
  String key;
  String valueJson;
  String mode;
}

/// The managed configuration's values, as JSON (bundles as objects, bundle arrays as lists).
class ConfigInfo {
  ConfigInfo(this.json);
  String json;
}

class AttestationInfo {
  AttestationInfo(this.suite, this.ec, this.mlDsa65, this.json);
  String suite;
  List<Uint8List> ec;
  List<Uint8List>? mlDsa65;
  String json;
}

class CertificatePathInfo {
  CertificatePathInfo(this.certificates);
  List<Uint8List> certificates;
}

class CertificateInfo {
  CertificateInfo(this.alias, this.paths, this.imported);
  String alias;
  List<CertificatePathInfo> paths;
  bool imported;
}

class CertificatesChangedInfo {
  CertificatesChangedInfo(this.changed);
  bool changed;
}

class UsbDeviceInfo {
  UsbDeviceInfo(this.accessory, this.deviceName, this.vendorId, this.productId, this.manufacturer, this.product,
      this.model, this.version, this.serial, this.name, this.hasPermission);
  bool accessory;
  String? deviceName;
  int vendorId;
  int productId;
  String? manufacturer;
  String? product;
  String? model;
  String? version;
  String? serial;
  String? name;
  bool hasPermission;
}

class UsbChangeInfo {
  UsbChangeInfo(this.attached, this.device);
  bool attached;
  UsbDeviceInfo device;
}

class KeyInfoData {
  KeyInfoData(this.alias, this.algorithm, this.createdAtMs);
  String alias;
  String algorithm;
  int createdAtMs;
}

class EncapsulatedData {
  EncapsulatedData(this.ciphertext, this.sharedSecret);
  Uint8List ciphertext;
  Uint8List sharedSecret;
}

class KeyAttestationData {
  KeyAttestationData(this.algorithm, this.publicKey, this.owner, this.coseSign1, this.diceChain);
  String algorithm;
  Uint8List publicKey;
  String owner;
  Uint8List coseSign1;
  Uint8List diceChain;
}

class SenderKeyData {
  SenderKeyData(this.ed25519, this.mlDsa65);
  Uint8List ed25519;
  Uint8List? mlDsa65;
}

class PushTokenData {
  PushTokenData(this.token, this.suite, this.publicKey);
  String token;
  String suite;
  Uint8List publicKey;
}

class PushMessageData {
  PushMessageData(this.id, this.data, this.expiresAtMs, this.highPriority, this.pushId);
  String id;
  Uint8List data;
  int expiresAtMs;
  bool highPriority;
  String pushId;
}

class HttpRequestData {
  HttpRequestData(this.method, this.url, this.headers, this.body, this.alias, this.timeoutMs, this.followRedirects);
  String method;
  String url;
  Map<String, String> headers;
  Uint8List? body;
  String? alias;
  int timeoutMs;
  bool followRedirects;
}

class HttpResponseData {
  HttpResponseData(this.status, this.reason, this.headers, this.body, this.url);
  int status;
  String? reason;
  Map<String, String> headers;
  Uint8List body;
  String url;
}

class ConnectionInfo {
  ConnectionInfo(this.state);
  String state;
}

/// Everything the Dart side asks. Each call runs on a worker thread of the plugin.
@HostApi()
abstract class OhrHostApi {
  // The connection and access
  @async
  void connect(int timeoutMs);
  bool isAvailable();
  String connectionState();
  @async
  AccessInfo accessInfo();

  // Device and updates
  @async
  DeviceInfo deviceInfo();
  @async
  UpdateInfo? updatesAvailable();
  @async
  void updatesInstall(bool whenIdle);

  // Wi-Fi (configs and networks as the Agent's JSON)
  @async
  WifiStateInfo wifiState();
  @async
  String wifiNetworks();
  @async
  void wifiScan();
  @async
  String wifiSaved();
  @async
  String wifiSave(String configJson);
  @async
  void wifiConnect(String keyOrIdentity);
  @async
  String wifiConnectConfig(String configJson);
  @async
  void wifiDisconnect();
  @async
  void wifiForget(String identity);
  @async
  void wifiSetEnabled(bool on);
  @async
  String wifiConnectQr(String text);

  // Network
  @async
  NetworkStateInfo networkState();
  @async
  void networkSetMobileData(bool on);
  @async
  void networkSetAirplaneMode(bool on);
  @async
  void networkSetDataRoaming(bool on);

  // Kiosk
  @async
  void kioskStart(int features);
  @async
  void kioskStop();
  @async
  KioskStateInfo kioskState();
  @async
  void kioskRequestExit();
  void kioskBeat(int timeoutMs);
  void kioskStopHeartbeat();

  // Power
  @async
  BatteryInfo powerBattery();
  @async
  void powerReboot(String reason);
  @async
  void powerScheduleReboot(RebootScheduleInfo? schedule);
  @async
  RebootScheduleInfo? powerRebootSchedule();
  @async
  void powerSetScreenTimeout(int seconds);
  @async
  void powerSetBrightness(int percent);

  // Settings (values as JSON)
  @async
  List<String> settingsKeys();
  @async
  SettingInfo settingsGet(String key);
  @async
  void settingsSet(String key, String valueJson);

  // Managed configuration
  ConfigInfo configValues();
  String? configString(String key, String? fallback);
  int configInt(String key, int fallback);
  bool configBool(String key, bool fallback);
  List<String> configStrings(String key);
  bool configIsSet(String key);

  // Attestation
  @async
  AttestationInfo attestationAttest(Uint8List challenge, String suite);
  @async
  String attestationToken(String audience, int ttlSeconds, String? nonce);
  @async
  String? attestationSuite();

  // Certificates
  @async
  bool certificatesCanRequest();
  @async
  CertificateInfo certificatesRequest(String alias, int timeoutMs);
  @async
  CertificateInfo? certificatesRenewIfDue(String alias);
  @async
  List<CertificateInfo> certificatesList();
  @async
  HttpResponseData httpSend(HttpRequestData request);

  // USB
  @async
  List<UsbDeviceInfo> usbDevices();

  // Diagnostics
  @async
  void diagnosticsEvent(String name, String dataJson);
  @async
  void diagnosticsLog(int priority, String tag, String message);

  // Keys
  @async
  bool keysIsAvailable();
  @async
  Uint8List keysGenerate(String alias, String algorithm);
  @async
  List<KeyInfoData> keysList();
  @async
  Uint8List? keysPublicKey(String alias);
  @async
  void keysDelete(String alias);
  @async
  Uint8List keysDecapsulate(String alias, Uint8List ciphertext);
  @async
  EncapsulatedData keysEncapsulate(String algorithm, Uint8List publicKey);
  @async
  Uint8List keysHpkeOpen(String alias, int kdf, int aead, Uint8List enc, Uint8List info, Uint8List aad, Uint8List ciphertext);
  @async
  KeyAttestationData keysAttest(String alias, Uint8List challenge);

  // Push
  @async
  PushTokenData pushRegister(List<SenderKeyData> senderKeys, String suite);
  @async
  PushTokenData? pushToken();
  @async
  void pushUnregister();
  void pushSetSenderKeys(List<SenderKeyData> keys);
  List<SenderKeyData> pushSenderKeys();
  /// The callback handles of the background dispatcher and the app's handlers (0: none).
  void pushSetHandlers(int dispatcher, int onMessage, int onTokenChanged, int onDropped);
}

/// The background isolate's side of push: it says when it is ready for messages.
@HostApi()
abstract class OhrPushBackgroundHostApi {
  void ready();
}

/// What the plugin tells the background isolate. Each call returns when the app's handler finished.
@FlutterApi()
abstract class OhrPushFlutterApi {
  @async
  void onMessage(int handler, PushMessageData message);
  @async
  void onTokenChanged(int handler, PushTokenData? token);
  @async
  void onDropped(int handler, String pushId, String reason);
}

/// The Agent's changes, one stream each. Listening watches; cancelling stops watching.
@EventChannelApi()
abstract class OhrEvents {
  ConnectionInfo connection();
  UpdateInfo updates();
  WifiStateInfo wifiState();
  WifiNetworksInfo wifiNetworks();
  NetworkStateInfo networkState();
  KioskModeInfo kioskMode();
  BatteryInfo battery();
  SettingInfo settings();
  ConfigInfo config();
  CertificatesChangedInfo certificates();
  UsbChangeInfo usb();
}
