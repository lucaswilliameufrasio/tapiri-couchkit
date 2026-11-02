
import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/atv/atv_identity.dart';
import 'package:couchkit_remote/data/atv/atv_messages.dart';
import 'package:couchkit_remote/data/atv/atv_pairing.dart';
import 'package:couchkit_remote/data/atv/atv_remote.dart';
import 'package:couchkit_remote/data/atv/protobuf.dart';

import '../atv_fake.dart';

void main() {
  group('mensagens iguais às do protoc (.proto oficiais)', () {
    test('pareamento', () {
      expect(
        body(Polo.pairingRequest('Couchkit')),
        '080210c80152150a0961747672656d6f74651208436f7563686b6974',
      );
      expect(body(Polo.options()), '080210c801a201080a04080310061801');
      expect(body(Polo.configuration()), '080210c801f201080a04080310061001');
      expect(
        body(Polo.secret(List.generate(32, (i) => i))),
        '080210c801c202220a20'
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
      );
    });

    test('comandos', () {
      expect(
        body(RemoteMsg.configure(611)),
        '0a1c08e304121718012201312a0961747672656d6f74653205312e302e30',
      );
      expect(body(RemoteMsg.setActive(611)), '120308e304');
      expect(body(RemoteMsg.pingResponse(7)), '4a020807');
      expect(body(RemoteMsg.key(19)), '520408131003');
      expect(
        body(RemoteMsg.text('olá x', 4, 9)),
        'aa0116080410091a100801120c080410041a066f6cc3a12078',
      );
      expect(
        body(RemoteMsg.appLink('https://www.youtube.com')),
        'd205190a1768747470733a2f2f7777772e796f75747562652e636f6d',
      );
    });

    test('lê mensagem codificada pelo protoc', () {
      final msg = PbReader(
        hex('0a1c08e304121718012201312a0961747672656d6f74653205312e302e30'),
      );
      expect(msg.message(1)!.uint(1), 611);
      expect(msg.message(1)!.message(2)!.string(5), 'atvremote');
    });

    test('PbFrames junta mensagens picadas e coladas', () {
      final a = RemoteMsg.key(19);
      final b = RemoteMsg.key(20);
      final frames = PbFrames();
      final all = [...a, ...b];
      expect(frames.add(all.sublist(0, 3)), isEmpty);
      final out = frames.add(all.sublist(3));
      expect(out.length, 2);
      expect(PbReader(out[1]).message(10)!.uint(1), 20);
    });
  });

  test('hash do código igual ao da biblioteca de referência (Python)', () {
    final cn = BigInt.parse(
      'C3${'A1B2C3D4E5F60718293A4B5C6D7E8F90' * 15}',
      radix: 16,
    );
    final sn = BigInt.parse(
      'B7${'0123456789ABCDEFFEDCBA9876543210' * 15}',
      radix: 16,
    );
    final hash = AtvPairing.secretHash(
      cn,
      BigInt.from(65537),
      sn,
      BigInt.from(65537),
      '3A9C',
    );
    expect(
      toHex(hash),
      '0a8bfdf591cc83b9d963700444d1ad1a090b419ff38b8047d1769553e3c847a1',
    );
  });

  group('com TV falsa (TLS de verdade)', () {
    late FakeAtv tv;
    late AtvIdentity phone;
    const pairPort = 46467;
    const apiPort = 46466;

    setUpAll(() async {
      phone = await AtvIdentity.generate();
      tv = await FakeAtv.start(pairPort, apiPort, phone);
    });

    tearDownAll(() => tv.stop());

    test('sem parear, a TV derruba a conexão e pede pareamento', () async {
      final remote = AtvRemote(phone, apiPort: apiPort);
      await expectLater(
        remote.connect('127.0.0.1'),
        throwsA(
          isA<AtvException>().having((e) => e.needsPairing, 'pareamento', true),
        ),
      );
    });

    test('código errado é recusado antes de ir para a TV', () async {
      final pairing = AtvPairing(phone, pairPort: pairPort);
      await pairing.start('127.0.0.1');
      await expectLater(pairing.finish('000000'), throwsA(isA<AtvException>()));
      expect(tv.pairedOk, isFalse);
      await pairing.close();
    });

    test('pareia com o código certo e depois controla a TV', () async {
      final pairing = AtvPairing(phone, pairPort: pairPort);
      await pairing.start('127.0.0.1');
      expect(tv.pairingSteps, containsAllInOrder([10, 20, 30]));
      await pairing.finish(tv.codeFor(phone).toLowerCase());
      await pairing.close();
      expect(tv.pairedOk, isTrue);

      final remote = AtvRemote(phone, apiPort: apiPort);
      await remote.connect('127.0.0.1');
      expect(remote.isOn, isTrue);

      remote
        ..sendKey(19)
        ..sendKey(23, direction: 3)
        ..sendText('abc');
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final keys = [
        for (final m in tv.received)
          if (m.has(10)) m.message(10)!.uint(1),
      ];
      expect(keys, [19, 23]);
      final text = tv.received.firstWhere((m) => m.has(21)).message(21)!;
      expect(text.uint(1), 4);
      expect(text.uint(2), 9);
      expect(text.message(3)!.message(2)!.string(3), 'abc');
      // a TV mandou um ping e o cliente respondeu
      expect(
        tv.received.any((m) => m.has(9) && m.message(9)!.uint(1) == 7),
        isTrue,
      );
      // o cliente aceitou só o que a TV disse suportar (611 & 1|2|4|32|64|512)
      final configure = tv.received.firstWhere((m) => m.has(1));
      expect(configure.message(1)!.uint(1), 1 | 2 | 4 | 32 | 64 | 512);
      await remote.close();
    });

    test('TV desligada: erro de alcance, não de pareamento', () async {
      final remote = AtvRemote(phone, apiPort: 46999);
      await expectLater(
        remote.connect('127.0.0.1'),
        throwsA(
          isA<AtvException>().having(
            (e) => e.needsPairing,
            'pareamento',
            false,
          ),
        ),
      );
    });
  });
}
