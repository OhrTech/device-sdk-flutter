import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'core.dart';
import 'messages.g.dart' as g;

/// The push suite of a token: [x25519] is small (about 190 bytes over the data), the default;
/// [xWingMlDsa65] is post-quantum (about 4.6 KB over).
enum OhrPushSuite {
  x25519('x25519'),
  xWingMlDsa65('xwing-mldsa65');

  const OhrPushSuite(this.wire);
  final String wire;

  static OhrPushSuite named(String wire) => values.firstWhere((s) => s.wire == wire);
}

/// A sender's public keys, as your server's OhrTech SDK gives them: [ed25519] (32 bytes) and, for the
/// xwing-mldsa65 suite, [mlDsa65] (1,952 bytes).
class OhrSenderKey {
  OhrSenderKey(this.ed25519, [this.mlDsa65]);

  /// From base64 (standard alphabet, as the Management API and server SDKs print them).
  OhrSenderKey.fromBase64(String ed25519, [String? mlDsa65])
      : this(base64Decode(ed25519), mlDsa65 == null ? null : base64Decode(mlDsa65));
  final Uint8List ed25519;
  final Uint8List? mlDsa65;

  g.SenderKeyData _data() => g.SenderKeyData(ed25519: ed25519, mlDsa65: mlDsa65);
  static OhrSenderKey _of(g.SenderKeyData d) => OhrSenderKey(d.ed25519, d.mlDsa65);
}

/// What your server needs to push to this app on this device: [token] ("psh_…") and [publicKey].
class OhrPushToken {
  OhrPushToken._(g.PushTokenData t)
      : token = t.token,
        suite = OhrPushSuite.named(t.suite),
        publicKey = t.publicKey;
  final String token;
  final OhrPushSuite suite;
  final Uint8List publicKey;
  String get publicKeyBase64 => base64Encode(publicKey);

  @override
  String toString() => 'OhrPushToken($token, ${suite.wire})';
}

/// A message your server sent, verified and opened. [id]: your server's id for it; [data] its bytes (at
/// most 4,096); [highPriority]: sent as high priority; [pushId]: the hub's id ("pmsg_…").
class OhrPushMessage {
  OhrPushMessage._(g.PushMessageData m)
      : id = m.id,
        data = m.data,
        expiresAt = DateTime.fromMillisecondsSinceEpoch(m.expiresAtMs),
        highPriority = m.highPriority,
        pushId = m.pushId;
  final String id;
  final Uint8List data;
  final DateTime expiresAt;
  final bool highPriority;
  final String pushId;
}

/// Handles a push message. A top-level or static function, run in a background isolate.
typedef OhrPushMessageHandler = Future<void> Function(OhrPushMessage message);

/// The token changed or ended (null: register again). Send a new token to your server.
typedef OhrPushTokenHandler = Future<void> Function(OhrPushToken? token);

/// A message was dropped: [reason] "signature", "expired", "duplicate", "malformed", ...
typedef OhrPushDroppedHandler = Future<void> Function(String pushId, String reason);

/// OhrTech push: messages from the app's own server, end to end. The server seals each message to the
/// device's push key (in the TEE) and signs it with its sender key; the OhrTech hub only carries it.
///
/// 1. [setHandlers] at app start, with top-level functions: they run in a background isolate, whether the
///    app is open or not (the Agent starts the app for a message).
/// 2. [register] once (and when the token handler gets null), with your server's sender public keys. Send
///    the [OhrPushToken] (token and public key) to your server.
/// 3. Your server seals and sends through the Management API (`POST /v1/push`). Each message reaches the
///    handler verified, opened, in date and not seen before; others are dropped.
abstract final class OhrPush {
  /// Makes the app's push key for [suite] in the TEE, has the hub verify it and issue a token, and keeps
  /// [senderKeys]. Registering again gives a new token and ends the old one. Waits for the hub (up to 30 s).
  static Future<OhrPushToken> register(List<OhrSenderKey> senderKeys, {OhrPushSuite suite = OhrPushSuite.x25519}) async =>
      OhrPushToken._(await call((a) => a.pushRegister([for (final k in senderKeys) k._data()], suite.wire)));

  /// The current token, or null if the app isn't registered (or its token ended).
  static Future<OhrPushToken?> token() async {
    final t = await call((a) => a.pushToken());
    return t == null ? null : OhrPushToken._(t);
  }

  /// Ends the token and deletes the push key.
  static Future<void> unregister() => call((a) => a.pushUnregister());

  /// Replaces the sender keys messages are checked against (e.g. when your server rotates them).
  static Future<void> setSenderKeys(List<OhrSenderKey> keys) => callLocal((a) => a.pushSetSenderKeys([for (final k in keys) k._data()]));
  static Future<List<OhrSenderKey>> senderKeys() async => [for (final k in await callLocal((a) => a.pushSenderKeys())) OhrSenderKey._of(k)];

  /// The app's handlers, top-level or static functions (annotate them `@pragma('vm:entry-point')`). Call
  /// it at each app start: the handles are kept for when a message starts the app.
  static Future<void> setHandlers({
    required OhrPushMessageHandler onMessage,
    OhrPushTokenHandler? onTokenChanged,
    OhrPushDroppedHandler? onDropped,
  }) {
    int handle(Function? f, String what) {
      if (f == null) return 0;
      final h = PluginUtilities.getCallbackHandle(f);
      if (h == null) throw OhrInvalidConfig('$what: a top-level or static function', what, 'a top-level or static function');
      return h.toRawHandle();
    }

    return callLocal((a) => a.pushSetHandlers(
          handle(ohrPushDispatcher, 'dispatcher'),
          handle(onMessage, 'onMessage'),
          handle(onTokenChanged, 'onTokenChanged'),
          handle(onDropped, 'onDropped'),
        ));
  }
}

/// The background isolate's entry point: the plugin starts it for push. Not for apps to call.
@pragma('vm:entry-point')
void ohrPushDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  g.OhrPushFlutterApi.setUp(_Dispatcher());
  g.OhrPushBackgroundHostApi().ready();
}

class _Dispatcher implements g.OhrPushFlutterApi {
  T? _handler<T>(int handle) => PluginUtilities.getCallbackFromHandle(CallbackHandle.fromRawHandle(handle)) as T?;

  @override
  Future<void> onMessage(int handler, g.PushMessageData message) async =>
      await _handler<OhrPushMessageHandler>(handler)?.call(OhrPushMessage._(message));

  @override
  Future<void> onTokenChanged(int handler, g.PushTokenData? token) async =>
      await _handler<OhrPushTokenHandler>(handler)?.call(token == null ? null : OhrPushToken._(token));

  @override
  Future<void> onDropped(int handler, String pushId, String reason) async =>
      await _handler<OhrPushDroppedHandler>(handler)?.call(pushId, reason);
}
