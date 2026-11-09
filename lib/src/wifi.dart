import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'core.dart';
import 'messages.g.dart' as g;

class OhrWifiState {
  OhrWifiState._(g.WifiStateInfo s)
      : enabled = s.enabled,
        state = s.state,
        connected = s.connectedJson == null ? null : (jsonDecode(s.connectedJson!) as Map).cast<String, Object?>();
  final bool enabled;

  /// "on", "off", "turningOn" or "turningOff".
  final String state;

  /// The current network (as [OhrWifiNetwork.json]), or null.
  final Map<String, Object?>? connected;

  /// The current network's SSID, or null.
  String? get ssid => connected?['ssid'] as String?;
}

/// One network in range. [key] joins it with [OhrWifi.connect].
class OhrWifiNetwork {
  OhrWifiNetwork._(this.json)
      : key = json['key'] as String? ?? '',
        title = json['title'] as String? ?? '',
        ssid = json['ssid'] as String?,
        security = [for (final s in (json['security'] as List?) ?? const []) s as String],
        level = (json['level'] as num?)?.toInt() ?? -1,
        saved = json['saved'] == true,
        connected = json['connected'] == 'connected',
        fleet = json['fleet'] == true;
  final String key;
  final String title;
  final String? ssid;
  final List<String> security;

  /// Signal level, 0-4, or -1.
  final int level;
  final bool saved;
  final bool connected;

  /// One of the fleet's networks: read-only to apps.
  final bool fleet;

  /// Everything the Agent says about it (also "internet", "metered").
  final Map<String, Object?> json;

  static List<OhrWifiNetwork> _list(String json) =>
      [for (final n in jsonDecode(json) as List) OhrWifiNetwork._((n as Map).cast<String, Object?>())];
}

/// Wi-Fi: state and the networks around, read always; changes with the fleet's "wifi" grant. The fleet's
/// own networks are read-only ([OhrFleetLocked] "wifi.networks"). For a ready-made screen, use [OhrWifiView].
///
/// Network configs are the OhrTech Wi-Fi model as JSON maps (the same as the fleet setting "Saved Wi-Fi
/// networks"); [WifiConfig] builds the common ones.
abstract final class OhrWifi {
  static Future<OhrWifiState> state() async => OhrWifiState._(await call((a) => a.wifiState()));
  static Future<List<OhrWifiNetwork>> networks() async => OhrWifiNetwork._list(await call((a) => a.wifiNetworks()));
  static Future<void> scan() => call((a) => a.wifiScan());

  /// Saved networks: {"ssid", "security", "fleet"} (or "passpoint").
  static Future<List<Map<String, Object?>>> saved() async =>
      [for (final n in jsonDecode(await call((a) => a.wifiSaved())) as List) (n as Map).cast<String, Object?>()];

  /// Saves [config]; returns its identity ("ssid:…", "passpoint:…"). [OhrInvalidConfig] names the field.
  static Future<String> save(Map<String, Object?> config) => call((a) => a.wifiSave(jsonEncode(config)));

  /// Joins a network by its [OhrWifiNetwork.key] or a saved identity.
  static Future<void> connect(String keyOrIdentity) => call((a) => a.wifiConnect(keyOrIdentity));

  /// Saves, then joins. Returns the identity.
  static Future<String> connectConfig(Map<String, Object?> config) => call((a) => a.wifiConnectConfig(jsonEncode(config)));
  static Future<void> disconnect() => call((a) => a.wifiDisconnect());
  static Future<void> forget(String identity) => call((a) => a.wifiForget(identity));

  /// [OhrFleetLocked] when the fleet locks wifi.enabled.
  static Future<void> setEnabled(bool on) => call((a) => a.wifiSetEnabled(on));

  /// A Wi-Fi QR code the app scanned ("WIFI:…"): saves and joins it. Returns the identity.
  static Future<String> connectQr(String text) => call((a) => a.wifiConnectQr(text));

  static final Stream<OhrWifiState> stateChanges = shared(g.wifiState, OhrWifiState._);
  static final Stream<List<OhrWifiNetwork>> networkChanges =
      shared(g.wifiNetworks, (g.WifiNetworksInfo n) => OhrWifiNetwork._list(n.json));
}

/// The common network configs of the OhrTech Wi-Fi model. For enterprise and Passpoint, build the map.
abstract final class WifiConfig {
  static Map<String, Object?> open(String ssid, {bool hidden = false}) => _base(ssid, 'open', hidden);

  /// Enhanced Open.
  static Map<String, Object?> owe(String ssid, {bool hidden = false}) => _base(ssid, 'owe', hidden);

  /// WPA/WPA2 personal: 8-63 characters, or 64 hex digits.
  static Map<String, Object?> psk(String ssid, String password, {bool hidden = false}) =>
      {..._base(ssid, 'psk', hidden), 'password': password};

  /// WPA3 personal.
  static Map<String, Object?> sae(String ssid, String password, {bool hidden = false}) =>
      {..._base(ssid, 'sae', hidden), 'password': password};

  static Map<String, Object?> _base(String ssid, String security, bool hidden) =>
      {'ssid': ssid, 'security': security, if (hidden) 'hidden': true};
}

/// The look of [OhrWifiView]. Unset values follow the system's Material You colours, as Settings does.
@immutable
class OhrWifiTheme {
  const OhrWifiTheme({this.dark, this.accent, this.background, this.text, this.cornerRadius});
  final bool? dark;
  final Color? accent;
  final Color? background;
  final Color? text;

  /// In logical pixels.
  final double? cornerRadius;

  Map<String, Object?> _map() => {
        if (dark != null) 'dark': dark,
        if (accent != null) 'accent': accent!.toARGB32(),
        if (background != null) 'background': background!.toARGB32(),
        if (text != null) 'text': text!.toARGB32(),
        if (cornerRadius != null) 'cornerRadiusDp': cornerRadius,
      };

  @override
  bool operator ==(Object other) =>
      other is OhrWifiTheme &&
      other.dark == dark &&
      other.accent == accent &&
      other.background == background &&
      other.text == text &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(dark, accent, background, text, cornerRadius);
}

/// What [OhrWifiView] offers (all on by default). Read when the screen opens.
@immutable
class OhrWifiOptions {
  const OhrWifiOptions({this.wifiSwitch = true, this.addNetwork = true, this.enterprise = true, this.forget = true, this.saved = true});
  final bool wifiSwitch;
  final bool addNetwork;
  final bool enterprise;
  final bool forget;
  final bool saved;

  Map<String, Object?> _map() =>
      {'wifiSwitch': wifiSwitch, 'addNetwork': addNetwork, 'enterprise': enterprise, 'forget': forget, 'saved': saved};
}

/// The Wi-Fi screen of Android's Settings, drawn by the OhrTech Agent inside the app's own layout: the
/// network list, joining every type of network, saved networks, forgetting. It opens no other activity
/// or window, so a kiosk app stays a kiosk. Needs the fleet's "wifi" grant ([onError] says if not).
///
/// It is an Android view shown with hybrid composition; give it a bounded size (inside an Expanded or a
/// SizedBox).
class OhrWifiView extends StatefulWidget {
  const OhrWifiView({super.key, this.theme = const OhrWifiTheme(), this.options = const OhrWifiOptions(), this.onConnected, this.onError});

  /// Changes apply at once.
  final OhrWifiTheme theme;
  final OhrWifiOptions options;

  /// The device joined the network named.
  final ValueChanged<String>? onConnected;

  /// The screen couldn't open or stopped.
  final ValueChanged<OhrException>? onError;

  @override
  State<OhrWifiView> createState() => _OhrWifiViewState();
}

class _OhrWifiViewState extends State<OhrWifiView> {
  static const _type = 'net.ohrtech.device/wifi_view';
  MethodChannel? _channel;

  @override
  void didUpdateWidget(OhrWifiView old) {
    super.didUpdateWidget(old);
    if (old.theme != widget.theme) _channel?.invokeMethod('setTheme', widget.theme._map());
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _created(int id) {
    final channel = MethodChannel('net.ohrtech.device/wifi_view_$id');
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'connected':
          widget.onConnected?.call(call.arguments as String);
        case 'error':
          final m = (call.arguments as Map).cast<String, Object?>();
          widget.onError?.call(ohrException(PlatformException(code: m['code'] as String? ?? 'Failed', message: m['message'] as String?, details: m['details'])));
      }
    });
    _channel = channel;
  }

  @override
  Widget build(BuildContext context) {
    final params = {'theme': widget.theme._map(), 'options': widget.options._map()};
    return PlatformViewLink(
      viewType: _type,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params0) {
        // Hybrid composition: the Agent's screen is a SurfaceView, which texture-based modes can't show.
        final c = PlatformViewsService.initExpensiveAndroidView(
          id: params0.id,
          viewType: _type,
          layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          creationParams: params,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params0.onFocusChanged(true),
        );
        c.addOnPlatformViewCreatedListener(params0.onPlatformViewCreated);
        c.addOnPlatformViewCreatedListener(_created);
        c.create();
        return c;
      },
    );
  }
}
