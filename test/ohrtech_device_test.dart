import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohrtech_device/ohrtech_device.dart';
import 'package:ohrtech_device/src/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('errors', () {
    test('each code becomes its OhrException', () {
      OhrException e(String code, [Map<String, Object?>? details]) =>
          ohrException(PlatformException(code: code, message: 'm', details: details));
      expect(e('NotManaged'), isA<OhrNotManaged>());
      expect((e('NotAllowed', {'area': 'wifi'}) as OhrNotAllowed).area, 'wifi');
      expect((e('FleetLocked', {'key': 'wifi.enabled'}) as OhrFleetLocked).key, 'wifi.enabled');
      final u = e('Unsupported', {'reason': 'too old', 'needsAgent': 1061}) as OhrUnsupported;
      expect(u.reason, 'too old');
      expect(u.needsAgent, 1061);
      final i = e('InvalidConfig', {'field': 'alias', 'reason': '1 to 64'}) as OhrInvalidConfig;
      expect((i.field, i.reason), ('alias', '1 to 64'));
      expect((e('Refused', {'reason': 'no issuing CA'}) as OhrRefused).reason, 'no issuing CA');
      expect((e('Failed', {'reason': 'x'}) as OhrFailed).reason, 'x');
      expect(e('SomethingNew'), isA<OhrFailed>());
    });

    test('anything else is OhrFailed', () {
      expect(ohrException(StateError('boom')), isA<OhrFailed>());
      const passed = OhrNotManaged('m');
      expect(identical(ohrException(passed), passed), isTrue);
    });
  });

  group('shared streams', () {
    test('one source for every listener, cancelled with the last', () async {
      var opened = 0, cancelled = 0;
      late StreamController<int> source;
      final s = shared<int, String>(() {
        opened++;
        source = StreamController<int>.broadcast(onCancel: () => cancelled++);
        return source.stream;
      }, (v) => 'v$v');
      final a = <String>[], b = <String>[];
      final sa = s.listen(a.add);
      final sb = s.listen(b.add);
      source.add(1);
      await pumpEventQueue();
      expect(opened, 1);
      expect(a, ['v1']);
      expect(b, ['v1']);
      await sa.cancel();
      expect(cancelled, 0);
      await sb.cancel();
      expect(cancelled, 1);
    });

    test('errors arrive as OhrException', () async {
      final source = StreamController<int>.broadcast();
      final s = shared<int, int>(() => source.stream, (v) => v);
      final errors = <Object>[];
      final sub = s.listen(null, onError: errors.add);
      source.addError(PlatformException(code: 'NotAllowed', message: 'm', details: {'area': 'usb'}));
      await pumpEventQueue();
      expect((errors.single as OhrNotAllowed).area, 'usb');
      await sub.cancel();
    });
  });

  test('WifiConfig builds the Wi-Fi model', () {
    expect(WifiConfig.psk('Shop', 'secret123'), {'ssid': 'Shop', 'security': 'psk', 'password': 'secret123'});
    expect(WifiConfig.open('Guest', hidden: true), {'ssid': 'Guest', 'security': 'open', 'hidden': true});
    expect(WifiConfig.sae('Lab', 'pw-12345')['security'], 'sae');
  });

  test('the heartbeat refuses a timeout out of range before asking the Agent', () async {
    await expectLater(OhrKiosk.heartbeat(timeout: const Duration(seconds: 1)), throwsA(isA<OhrInvalidConfig>()));
  });
}
