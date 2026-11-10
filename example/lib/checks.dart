import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ohrtech_device/ohrtech_device.dart';

/// Device checks of the plugin against the real Agent and TEE, as the Kotlin library's:
/// `am start -n <pkg>/net.ohrtech.device.flutter.example.MainActivity --es route '/checks/<name>?<args>'`.
/// Logs "CHECK PASS|FAIL name detail" and "CHECK DONE" (logcat tag flutter).
class ChecksApp extends StatefulWidget {
  const ChecksApp(this.route, {super.key});
  final Uri route;

  @override
  State<ChecksApp> createState() => _ChecksAppState();
}

class _ChecksAppState extends State<ChecksApp> {
  String _summary = 'running…';
  int _passed = 0, _failed = 0;

  String get _check => widget.route.pathSegments.last;
  Map<String, String> get _args => widget.route.queryParameters;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _step(String name, FutureOr<Object?> Function() body) async {
    try {
      final r = await body();
      _passed++;
      debugPrint('CHECK PASS $name ${r is String ? r : ''}');
    } catch (e) {
      _failed++;
      debugPrint('CHECK FAIL $name: $e');
    }
  }

  void _expect(bool ok, String what) {
    if (!ok) throw StateError(what);
  }

  Future<void> _run() async {
    switch (_check) {
      case 'basics':
        await _step('connect', () => OhrDeviceSdk.connect());
        await _step('connection', () async => (await OhrDeviceSdk.connection()).name);
        await _step('access', () async => (await OhrAccess.info()).app);
        await _step('device', () async => (await OhrDevice.info()).deviceId);
        await _step('updates', () async => '${(await OhrUpdates.available())?.versionCode}');
        await _step('wifi state', () async => '${(await OhrWifi.state()).state} ${(await OhrWifi.state()).ssid}');
        await _step('wifi networks', () async => '${(await OhrWifi.networks()).length} networks');
        await _step('network', () async => '${(await OhrNetwork.state()).active?.transport}');
        await _step('kiosk state', () async => (await OhrKiosk.state()).mode);
        await _step('battery', () async => '${(await OhrPower.battery()).level}%');
        await _step('settings keys', () async => '${(await OhrSettings.keys()).length} keys');
        await _step('timeout 0 refused', () async {
          try {
            await OhrSettings.set('display.timeout', 0);
          } on OhrInvalidConfig catch (e) {
            return e.reason;
          }
          throw StateError('accepted 0');
        });
        await _step('timeout 45 accepted', () async {
          final before = (await OhrSettings.get('display.timeout')).value;
          await OhrSettings.set('display.timeout', 45);
          final now = (await OhrSettings.get('display.timeout')).value;
          await OhrSettings.set('display.timeout', before);
          _expect('$now' == '45', 'read back $now');
          return '45 (back to $before)';
        });
        await _step('config', () async => jsonEncode(await OhrConfig.values()));
        await _step('usb', () async => '${(await OhrUsb.devices()).length} attached');
        await _step('diag events', () async {
          await OhrDiagnostics.event('flutter_checks', {'run': 1});
          await OhrDiagnostics.i('Checks', 'a line from the Flutter checks');
          return '1 event, 1 line';
        });
        await _step('bad event refused', () async {
          try {
            await OhrDiagnostics.event('Bad Name');
          } on OhrInvalidConfig catch (e) {
            return e.field;
          }
          throw StateError('accepted a bad name');
        });
        await _step('stream: connection', () async =>
            (await OhrDeviceSdk.connectionChanges.first.timeout(const Duration(seconds: 5))).name);
        await _step('stream: connection, a second listener starts with the state too', () async {
          final first = OhrDeviceSdk.connectionChanges.listen((_) {});
          try {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            return (await OhrDeviceSdk.connectionChanges.first.timeout(const Duration(seconds: 5))).name;
          } finally {
            await first.cancel();
          }
        });
      case 'security':
        await _step('attest ec', () async {
          final a = await OhrAttestation.attest(Uint8List.fromList(utf8.encode('flutter-checks')));
          return '${a.ec.length} certificates, ${a.json['suite']}';
        });
        await _step('token ec', () async => '${(await OhrAttestation.token('https://example.test')).split('.').length} parts');
        await _step('attest ec+ml-dsa-65', () async {
          final a = await OhrAttestation.attest(Uint8List.fromList(utf8.encode('flutter-checks')), suite: OhrAttestationSuite.ecMlDsa65);
          return 'ec ${a.ec.length}, ml-dsa ${a.mlDsa65!.length}';
        });
        await _step('keys available', () async => '${await OhrKeys.isAvailable()}');
        await _step('kem x-wing', () async {
          final pub = await OhrKeys.generate('f.xwing', OhrKeyAlgorithm.xWing);
          final e = await OhrKeys.encapsulate(OhrKeyAlgorithm.xWing, pub);
          final s = await OhrKeys.decapsulate('f.xwing', e.ciphertext);
          _expect(listEquals(s, e.sharedSecret), 'secrets differ');
          return '${pub.length} B key, ${e.ciphertext.length} B ciphertext';
        });
        await _step('key attest', () async {
          final a = await OhrKeys.attest('f.xwing', Uint8List.fromList(utf8.encode('c')));
          _expect(a.owner.startsWith('app:'), a.owner);
          return 'cose ${a.coseSign1.length} B';
        });
        await _step('key list and delete', () async {
          _expect((await OhrKeys.list()).any((k) => k.alias == 'f.xwing'), 'not listed');
          await OhrKeys.delete('f.xwing');
          _expect(await OhrKeys.publicKey('f.xwing') == null, 'still there');
          return 'ok';
        });
        await _step('certificates', () async {
          if (!await OhrCertificates.canRequest()) return 'no issuing CA for this app';
          final c = await OhrCertificates.request('flutter-checks');
          return '${c.paths.length} paths, ${(await OhrCertificates.list()).length} listed';
        });
        final url = _args['tlsUrl'];
        if (url != null) {
          await _step('mutual TLS', () async {
            final r = await OhrCertificates.client(alias: _args['tlsAlias'] ?? 'flutter-checks').get(Uri.parse(url));
            return 'HTTP ${r.statusCode}, ${r.body.length} bytes';
          });
        }
      case 'push':
        await _step('register', () async {
          final t = await OhrPush.register([OhrSenderKey.fromBase64(_args['senderKey']!)]);
          debugPrint('CHECK TOKEN ${jsonEncode({'token': t.token, 'suite': t.suite.wire, 'publicKey': t.publicKeyBase64})}');
          return t.token;
        });
        await _step('token', () async => (await OhrPush.token())?.token);
      case 'unregister':
        await _step('unregister', () async {
          await OhrPush.unregister();
          _expect(await OhrPush.token() == null, 'token left');
          return 'no token';
        });
      case 'reconnect':
        await _reconnect();
      case 'heartbeat':
        await _step('kiosk start', OhrKiosk.start);
        await _step('heartbeat, then hang', () async {
          // Beats every 750 ms from this isolate; then the isolate stops for 30 s: the Agent restarts the app.
          await OhrKiosk.heartbeat(timeout: const Duration(seconds: 3));
          await Future<void>.delayed(const Duration(seconds: 2));
          debugPrint('CHECK HANGING');
          final until = DateTime.now().add(const Duration(seconds: 30));
          while (DateTime.now().isBefore(until)) {}
          throw StateError('still alive 30 s later');
        });
    }
    final s = 'CHECK DONE $_check: $_passed passed, $_failed failed';
    debugPrint(s);
    setState(() => _summary = s);
  }

  /// Streams outlive the Agent: the harness stops it after "CHECK READY reconnect".
  Future<void> _reconnect() async {
    final states = <String>[];
    final heard = <String, int>{};
    var back = false;
    final subs = [
      OhrDeviceSdk.connectionChanges.listen((c) {
        states.add(c.name);
        if (c == OhrConnection.connected && states.contains('reconnecting')) back = true;
      }),
      OhrPower.batteryChanges.listen((_) => back ? heard.update('battery', (n) => n + 1, ifAbsent: () => 1) : null),
      OhrNetwork.changes.listen((_) => back ? heard.update('network', (n) => n + 1, ifAbsent: () => 1) : null),
      OhrKiosk.modeChanges.listen((_) => back ? heard.update('kiosk', (n) => n + 1, ifAbsent: () => 1) : null),
    ];
    await Future<void>.delayed(const Duration(seconds: 1));
    debugPrint('CHECK READY reconnect');
    final until = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(until) && !(back && heard.length == 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await _step('agent stopped and came back', () {
      _expect(back, 'states ${states.join(' > ')}');
      return states.join(' > ');
    });
    await _step('streams heard again', () {
      _expect(heard.length == 3, 'heard $heard');
      return '$heard';
    });
    await _step('calls after', () async => (await OhrDevice.info()).deviceId);
    for (final s in subs) {
      await s.cancel();
    }
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_summary)))));
}

bool listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
