import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/data/atv/atv_service.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/tv_adb.dart';
import 'package:couchkit_remote/features/remote/remote_controller.dart';

import '../atv_fake.dart';

void main() {
  const pairPort = 46567;
  const apiPort = 46566;
  late AtvService service;
  late FakeAtv tv;

  setUpAll(() async {
    service = AtvService(MemoryStore(), pairPort: pairPort, apiPort: apiPort);
    tv = await FakeAtv.start(pairPort, apiPort, await service.identity());
  });

  tearDownAll(() => tv.stop());

  RemoteController controller() => RemoteController(
    TvAdb(MemoryStore(), port: 45999),
    '127.0.0.1',
    atv: service,
  );

  test(
    'pareia pelo controller, controla sem ADB e reconecta sozinho',
    () async {
      final remote = controller();
      await remote.connect();
      expect(remote.state, RemoteState.needsPairing);

      await remote.startPairing();
      expect(remote.state, RemoteState.enterCode);

      await remote.submitCode('ZZZZZZ');
      expect(remote.error, isNotNull);
      expect(remote.state, RemoteState.enterCode);

      await remote.submitCode(tv.codeFor(await service.identity()));
      expect(remote.state, RemoteState.ready);
      expect(remote.viaAtv, isTrue);

      remote
        ..press(RemoteKey.up)
        ..press(RemoteKey.ok)
        ..press(RemoteKey.home)
        ..press(RemoteKey.volumeUp)
        ..type('olá')
        ..backspace()
        ..openSettings();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final keys = [
        for (final m in tv.received)
          if (m.has(10)) m.message(10)!.uint(1),
      ];
      expect(keys, [19, 23, 3, 24, 67, 176]);
      expect(
        tv.received.firstWhere((m) => m.has(21) && m.message(21)!.has(3)),
        isNotNull,
      );
      remote.dispose();
    },
  );

  test('sem Remote v2 (Fire TV) cai no ADB e avisa se ele falhar', () async {
    final offline = AtvService(MemoryStore(), pairPort: 46901, apiPort: 46902);
    final remote = RemoteController(
      TvAdb(MemoryStore(), port: 45999),
      '127.0.0.1',
      atv: offline,
    );
    await remote.connect();
    expect(remote.viaAtv, isFalse);
    expect(remote.state, RemoteState.failed);
    remote.dispose();
  });
}
