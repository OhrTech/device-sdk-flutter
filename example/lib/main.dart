import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ohrtech_device/ohrtech_device.dart';

import 'checks.dart';

/// Runs in a background isolate for each push message, whether the app is open or not.
@pragma('vm:entry-point')
Future<void> onPushMessage(OhrPushMessage message) async {
  final text = utf8.decode(message.data);
  // The device checks' failing handler: the hub then shows the message as dropped (app_handler).
  if (text.contains('"fail"')) throw StateError('the handler failed, as asked');
  debugPrint('PUSH RECEIVED ${message.id} (${message.pushId}): $text');
}

@pragma('vm:entry-point')
Future<void> onPushDropped(String pushId, String reason) async {
  debugPrint('PUSH DROPPED $pushId: $reason');
}

@pragma('vm:entry-point')
Future<void> onPushToken(OhrPushToken? token) async {
  debugPrint('PUSH TOKEN now $token');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OhrPush.setHandlers(onMessage: onPushMessage, onDropped: onPushDropped, onTokenChanged: onPushToken);
  // `am start … --es route /checks/<name>?…`: the device checks instead of the sample.
  final route = PlatformDispatcher.instance.defaultRouteName;
  runApp(route.startsWith('/checks/') ? ChecksApp(Uri.parse(route)) : const SampleApp());
}

/// A kiosk app's page: who the device is, kiosk on and off, and the Agent's Wi-Fi screen below.
class SampleApp extends StatelessWidget {
  const SampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OhrTech SDK (Flutter)',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: const SamplePage(),
      );
}

class SamplePage extends StatefulWidget {
  const SamplePage({super.key});

  @override
  State<SamplePage> createState() => _SamplePageState();
}

class _SamplePageState extends State<SamplePage> {
  String _status = 'Asking the Agent…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await OhrDevice.info();
      final access = await OhrAccess.info();
      _show('${info.deviceId} · ${info.fleet?.name} · Agent ${info.agentVersion}\nmay use: ${(access.areas.toList()..sort()).join(', ')}');
    } on OhrException catch (e) {
      _show('Device SDK: ${e.message}');
    }
  }

  void _show(String s) {
    debugPrint(s);
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    try {
      await action();
      _show(label);
    } on OhrException catch (e) {
      _show('$label: ${e.runtimeType}: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OhrTech SDK (Flutter)')),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(_status)),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => _run('kiosk on', OhrKiosk.start), child: const Text('Kiosk on')),
            FilledButton(onPressed: () => _run('kiosk off', OhrKiosk.stop), child: const Text('Kiosk off')),
          ]),
          Expanded(
            child: OhrWifiView(
              onConnected: (ssid) => _show('joined $ssid'),
              onError: (e) => _show('Wi-Fi screen: ${e.message}'),
            ),
          ),
        ]),
      );
}
