import 'dart:async';
import 'dart:convert';

import 'core.dart';
import 'messages.g.dart' as g;

/// The library's connection to the OhrTech Agent. There is nothing to connect or close: the plugin
/// binds the Agent on the first call and keeps the binding; when the Agent stops (a crash, its own
/// update) it binds again, and every stream goes on.
abstract final class OhrDeviceSdk {
  /// Whether this device has an OhrTech Agent with the Device SDK.
  static Future<bool> isAvailable() => callLocal((a) => a.isAvailable());

  /// Connects now, waiting up to [timeout], instead of on the first call: to know at app start whether
  /// the Device SDK is there. Throws [OhrNotManaged], [OhrUnsupported] or [OhrFailed].
  static Future<void> connect({Duration timeout = const Duration(seconds: 10)}) =>
      call((a) => a.connect(timeout.inMilliseconds));

  /// The connection now.
  static Future<OhrConnection> connection() async => _connection(await callLocal((a) => a.connectionState()));

  /// The connection as it changes, starting with how it stands.
  static final Stream<OhrConnection> connectionChanges = shared(g.connection, (g.ConnectionInfo c) => _connection(c.state));

  static OhrConnection _connection(String name) =>
      OhrConnection.values.firstWhere((c) => c.wire == name, orElse: () => OhrConnection.notConnected);
}

/// How the library's connection to the Agent stands.
enum OhrConnection {
  /// Nothing has asked the Agent anything yet.
  notConnected('NOT_CONNECTED'),

  /// Binding the Agent for the first time.
  connecting('CONNECTING'),
  connected('CONNECTED'),

  /// The Agent stopped (a crash, its own update); calls wait for it to come back.
  reconnecting('RECONNECTING'),

  /// No OhrTech Agent with the Device SDK, or the hub didn't install this app.
  unavailable('UNAVAILABLE');

  const OhrConnection(this.wire);
  final String wire;
}

/// Who the Agent takes this app for, and what the fleet lets it do.
class OhrAccessInfo {
  OhrAccessInfo._(g.AccessInfo a)
      : app = a.app,
        packageName = a.packageName,
        appVersion = a.appVersion,
        areas = Set.unmodifiable(a.areas),
        agentVersion = a.agentVersion,
        agentInterface = a.agentInterface;

  /// The hub's id of this app ("app_…").
  final String app;
  final String packageName;

  /// The hub's id of the installed version, or null when it isn't one the hub shipped.
  final String? appVersion;

  /// What the app may use: always "device", "updates", "keys", "push", the reads ("wifi.read", ...), and
  /// each area the fleet grants ("wifi", "kiosk", ...).
  final Set<String> areas;
  final int agentVersion;

  /// The Agent's Device SDK interface version.
  final int agentInterface;

  /// Whether the fleet lets the app use (change) [area]; reads of most areas are always allowed.
  bool mayUse(String area) => areas.contains(area);
}

/// Who the Agent takes this app for, and what the fleet lets it do: asked of the Agent each time.
abstract final class OhrAccess {
  static Future<OhrAccessInfo> info() async => OhrAccessInfo._(await call((a) => a.accessInfo()));

  /// Whether the fleet lets the app use (change) [area] now.
  static Future<bool> mayUse(String area) async => (await info()).mayUse(area);
}

class OhrNamed {
  const OhrNamed(this.id, this.name);
  final String id;
  final String name;
}

class OhrDeviceInfo {
  OhrDeviceInfo._(g.DeviceInfo d)
      : deviceId = d.deviceId,
        serial = d.serial,
        fleet = d.fleet == null ? null : OhrNamed(d.fleet!.id, d.fleet!.name),
        org = d.org == null ? null : OhrNamed(d.org!.id, d.org!.name),
        osRelease = d.osRelease,
        osBuild = d.osBuild,
        securityPatch = d.securityPatch,
        osIncremental = d.osIncremental,
        agentVersion = d.agentVersion,
        online = d.online;

  /// "dev_…" (null until the hub sent the device its first policy).
  final String? deviceId;
  final String? serial;
  final OhrNamed? fleet;
  final OhrNamed? org;
  final String osRelease;
  final String osBuild;
  final String securityPatch;
  final String osIncremental;
  final int agentVersion;

  /// The Agent is connected to the hub now.
  final bool online;
}

/// The device: who it is, as the OhrTech hub and the Management API name it. Always allowed.
abstract final class OhrDevice {
  static Future<OhrDeviceInfo> info() async => OhrDeviceInfo._(await call((a) => a.deviceInfo()));
}

class OhrUpdate {
  const OhrUpdate(this.versionCode, this.versionName, this.notes, this.downloaded);
  OhrUpdate._(g.UpdateInfo u) : this(u.versionCode, u.versionName, u.notes, u.downloaded);
  final int versionCode;
  final String? versionName;
  final String? notes;
  final bool downloaded;

  /// Nothing offered.
  bool get none => versionCode == 0;
}

/// The app's own updates: a version the hub offers as available, downloaded ahead. Always allowed.
abstract final class OhrUpdates {
  /// The offered update, or null.
  static Future<OhrUpdate?> available() async {
    final u = await call((a) => a.updatesAvailable());
    return u == null ? null : OhrUpdate._(u);
  }

  /// Installs the offered update: now, or [whenIdle] the next time the screen is off. The app is
  /// replaced, so it stops; Android starts it again if it was on screen.
  static Future<void> install({bool whenIdle = false}) => call((a) => a.updatesInstall(whenIdle));

  /// The offer as it changes (an update with [OhrUpdate.none] when withdrawn).
  static final Stream<OhrUpdate> changes = shared(g.updates, OhrUpdate._);
}

class OhrActiveNetwork {
  OhrActiveNetwork._(g.ActiveNetworkInfo a)
      : transport = a.transport,
        validated = a.validated,
        captive = a.captive,
        metered = a.metered,
        vpn = a.vpn;

  /// "wifi", "cellular", "ethernet", "vpn" or "other".
  final String transport;
  final bool validated;
  final bool captive;
  final bool metered;
  final bool vpn;
}

class OhrNetworkState {
  OhrNetworkState._(g.NetworkStateInfo s)
      : active = s.active == null ? null : OhrActiveNetwork._(s.active!),
        mobileData = s.mobileData,
        airplaneMode = s.airplaneMode,
        dataRoaming = s.dataRoaming,
        ethernetConnected = s.ethernetConnected;

  /// The network in use, or null for none.
  final OhrActiveNetwork? active;
  final bool mobileData;
  final bool airplaneMode;
  final bool dataRoaming;
  final bool ethernetConnected;
}

/// Mobile data, airplane mode, roaming: read always, change with the fleet's "network" grant.
abstract final class OhrNetwork {
  static Future<OhrNetworkState> state() async => OhrNetworkState._(await call((a) => a.networkState()));
  static Future<void> setMobileData(bool on) => call((a) => a.networkSetMobileData(on));
  static Future<void> setAirplaneMode(bool on) => call((a) => a.networkSetAirplaneMode(on));

  /// [OhrFleetLocked] when the fleet locks network.data_roaming.
  static Future<void> setDataRoaming(bool on) => call((a) => a.networkSetDataRoaming(on));
  static final Stream<OhrNetworkState> changes = shared(g.networkState, OhrNetworkState._);
}

class OhrKioskState {
  OhrKioskState._(g.KioskStateInfo s)
      : pinned = s.pinned,
        mode = s.mode,
        features = s.features,
        appMayExit = s.appMayExit;

  /// This app is the one pinned.
  final bool pinned;

  /// "none", "locked" or "pinned".
  final String mode;
  final int features;
  final bool appMayExit;
}

/// What stays available in kiosk mode (combine with `|`).
abstract final class OhrKioskFeature {
  static const systemInfo = 1;
  static const notifications = 2;
  static const home = 4;
  static const overview = 8;
  static const globalActions = 16;
  static const keyguard = 32;
  static const blockActivityStartInTask = 64;
}

/// Kiosk mode: pins the app with Android's lock task, as the system, so the app can't be left (and
/// can't unpin itself either). Needs the fleet's "kiosk" grant. [stop] works only if the fleet lets
/// kiosk apps leave; otherwise the hub or the exit PIN ends it.
abstract final class OhrKiosk {
  /// Pins the app's task, keeping [features] (default: the power menu and status bar info).
  static Future<void> start({int features = OhrKioskFeature.globalActions | OhrKioskFeature.systemInfo}) =>
      call((a) => a.kioskStart(features));

  /// Ends kiosk mode, if the fleet lets kiosk apps leave ([OhrNotAllowed] otherwise).
  static Future<void> stop() => call((a) => a.kioskStop());
  static Future<OhrKioskState> state() async => OhrKioskState._(await call((a) => a.kioskState()));

  /// Opens the Agent's exit PIN keypad over the app, for staff to leave kiosk mode for a while. The app
  /// must be the one pinned. [OhrNotAllowed] when the fleet doesn't let the app offer it;
  /// [OhrUnsupported] when no exit PIN is set.
  static Future<void> requestExit() => call((a) => a.kioskRequestExit());

  /// The device-wide lock task mode as it changes ("none", "locked", "pinned"); [state] says whose.
  static final Stream<String> modeChanges = shared(g.kioskMode, (g.KioskModeInfo m) => m.mode);

  static Timer? _beats;

  /// Tells the Agent's kiosk watchdog that the app's UI isolate is alive: beats from this isolate's event
  /// loop, a few times per [timeout]. If the beats stop for longer (the UI hangs), the Agent stops the app
  /// and starts it again. Only while the app is pinned; call it again after [start]. One per app.
  ///
  /// With Agent 1062+, the fleet's response timeout for the app (portal or Management API), when set, replaces
  /// [timeout], and hangs aren't counted while the screen is off (the app gets a full timeout again when it
  /// comes back on).
  static Future<void> heartbeat({Duration timeout = const Duration(seconds: 10)}) async {
    final ms = timeout.inMilliseconds;
    if (ms < 2000 || ms > 600000) throw const OhrInvalidConfig('timeout: 2 s to 10 minutes', 'timeout', '2 s to 10 minutes');
    _beats?.cancel();
    await call((a) => a.kioskBeat(ms));
    _beats = Timer.periodic(Duration(milliseconds: ms ~/ 4), (_) => hostApi.kioskBeat(ms).catchError((_) {}));
  }

  /// Stops the heartbeat (and the Agent's watch on it).
  static Future<void> stopHeartbeat() {
    _beats?.cancel();
    _beats = null;
    return call((a) => a.kioskStopHeartbeat());
  }
}

class OhrBattery {
  OhrBattery._(g.BatteryInfo b)
      : level = b.level,
        charging = b.charging,
        plugged = b.plugged,
        health = b.health,
        temperatureC = b.temperatureC,
        screenOn = b.screenOn;
  final int? level;
  final bool charging;

  /// "ac", "usb", "wireless", "dock" or null.
  final String? plugged;

  /// "good", "overheat", ...
  final String health;
  final double temperatureC;
  final bool screenOn;
}

/// A reboot schedule: [time] "HH:mm", [days] 1-7 (Monday = 1).
class OhrRebootSchedule {
  const OhrRebootSchedule(this.time, this.days, this.reason);
  final String time;
  final Set<int> days;
  final String reason;
}

/// Battery (always), reboots, screen timeout and brightness (with the fleet's "power" grant).
abstract final class OhrPower {
  static Future<OhrBattery> battery() async => OhrBattery._(await call((a) => a.powerBattery()));

  /// Reboots in a few seconds; the hub records [reason].
  static Future<void> reboot(String reason) => call((a) => a.powerReboot(reason));

  /// Reboots on a schedule (the device's one; the last app to set it wins); null stops it.
  static Future<void> scheduleReboot(OhrRebootSchedule? schedule) => call((a) => a.powerScheduleReboot(
      schedule == null ? null : g.RebootScheduleInfo(time: schedule.time, days: schedule.days.toList()..sort(), reason: schedule.reason)));

  static Future<OhrRebootSchedule?> rebootSchedule() async {
    final s = await call((a) => a.powerRebootSchedule());
    return s == null ? null : OhrRebootSchedule(s.time, s.days.toSet(), s.reason);
  }

  /// Any whole number of seconds, 1 to 2147483 (Android's limit). [OhrFleetLocked] if the fleet locks it.
  static Future<void> setScreenTimeout(Duration timeout) => call((a) => a.powerSetScreenTimeout(timeout.inSeconds));

  /// 0-100 (turns adaptive brightness off). [OhrFleetLocked] if the fleet locks it.
  static Future<void> setBrightness(int percent) => call((a) => a.powerSetBrightness(percent));
  static final Stream<OhrBattery> batteryChanges = shared(g.battery, OhrBattery._);
}

class OhrSetting {
  OhrSetting._(g.SettingInfo s)
      : key = s.key,
        value = jsonDecode(s.valueJson),
        mode = s.mode;
  final String key;

  /// The value: a bool, number, String, List, Map or null.
  final Object? value;

  /// "unmanaged", "set" or "locked".
  final String mode;
  bool get locked => mode == 'locked';
}

/// The device's settings, by the OhrTech settings catalogue's keys: read always, change with the
/// fleet's "settings" grant. A key the fleet locks refuses ([OhrFleetLocked]); an app's change to an
/// unlocked key holds until the fleet changes that setting.
abstract final class OhrSettings {
  /// The keys apps may read and change on this device.
  static Future<List<String>> keys() => call((a) => a.settingsKeys());
  static Future<OhrSetting> get(String key) async => OhrSetting._(await call((a) => a.settingsGet(key)));

  /// [value]: a bool, number, String, List, Map or null.
  static Future<void> set(String key, Object? value) => call((a) => a.settingsSet(key, jsonEncode(value)));

  /// Each setting as it changes.
  static final Stream<OhrSetting> changes = shared(g.settings, OhrSetting._);
}

/// The app's managed configuration: the values its fleet (or one device's overrides) sets for the
/// settings the app declares in its own `res/xml/app_restrictions.xml`. Needs no Agent connection.
abstract final class OhrConfig {
  /// Every managed value (bundles as maps, bundle arrays as lists of maps).
  static Future<Map<String, Object?>> values() async =>
      (jsonDecode((await callLocal((a) => a.configValues())).json) as Map).cast<String, Object?>();

  /// A string, choice or hidden setting: the managed value, else the declared default, else [fallback].
  static Future<String?> string(String key, {String? fallback}) => callLocal((a) => a.configString(key, fallback));
  static Future<int> integer(String key, {int fallback = 0}) => callLocal((a) => a.configInt(key, fallback));
  static Future<bool> boolean(String key, {bool fallback = false}) => callLocal((a) => a.configBool(key, fallback));

  /// A multi-select setting.
  static Future<List<String>> strings(String key) => callLocal((a) => a.configStrings(key));

  /// Whether the fleet sets [key].
  static Future<bool> isSet(String key) => callLocal((a) => a.configIsSet(key));

  /// A bundle setting (a group of settings), or null if the fleet doesn't set it.
  static Future<Map<String, Object?>?> bundle(String key) async => ((await values())[key] as Map?)?.cast<String, Object?>();

  /// A bundle-array setting (a list of groups).
  static Future<List<Map<String, Object?>>> bundles(String key) async =>
      [for (final b in ((await values())[key] as List?) ?? const []) (b as Map).cast<String, Object?>()];

  /// Every change of the managed configuration, as the new values.
  static final Stream<Map<String, Object?>> changes =
      shared(g.config, (g.ConfigInfo c) => (jsonDecode(c.json) as Map).cast<String, Object?>());
}

class OhrUsbDevice {
  OhrUsbDevice._(g.UsbDeviceInfo d)
      : accessory = d.accessory,
        deviceName = d.deviceName,
        vendorId = d.vendorId,
        productId = d.productId,
        manufacturer = d.manufacturer,
        product = d.product,
        model = d.model,
        version = d.version,
        serial = d.serial,
        name = d.name,
        hasPermission = d.hasPermission;
  final bool accessory;

  /// Android's name for it: opens with UsbManager.
  final String? deviceName;
  final int vendorId;
  final int productId;
  final String? manufacturer;
  final String? product;
  final String? model;
  final String? version;
  final String? serial;

  /// The fleet's label for it.
  final String? name;
  final bool hasPermission;
}

class OhrUsbChange {
  OhrUsbChange._(g.UsbChangeInfo c)
      : attached = c.attached,
        device = OhrUsbDevice._(c.device);
  final bool attached;
  final OhrUsbDevice device;
}

/// The USB devices the fleet pre-approves for this app: when one is attached the Agent gives the app
/// access, so there is no "Allow access?" prompt (Agent 1061+).
abstract final class OhrUsb {
  static Future<List<OhrUsbDevice>> devices() async => [for (final d in await call((a) => a.usbDevices())) OhrUsbDevice._(d)];
  static final Stream<OhrUsbChange> changes = shared(g.usb, OhrUsbChange._);
}

/// The app's own diagnostics for the hub (Agent 1061+). Crashes need nothing: the Agent reports them.
abstract final class OhrDiagnostics {
  /// An event of the app's own ("order_failed"): [name] lower camel or snake case, up to 64 characters;
  /// [data] up to 2 KB as JSON. At most 60 a minute.
  static Future<void> event(String name, [Map<String, Object?> data = const {}]) =>
      call((a) => a.diagnosticsEvent(name, jsonEncode(data)));

  /// A log line for log bundles; [priority] is Android's (4 info, 5 warn, 6 error).
  static Future<void> log(int priority, String tag, String message) => call((a) => a.diagnosticsLog(priority, tag, message));
  static Future<void> i(String tag, String message) => log(4, tag, message);
  static Future<void> w(String tag, String message) => log(5, tag, message);
  static Future<void> e(String tag, String message) => log(6, tag, message);
}
