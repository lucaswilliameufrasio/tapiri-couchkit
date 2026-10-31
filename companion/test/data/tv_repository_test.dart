import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/tv_repository.dart';

import '../test_server.dart';

void main() {
  late TvRepository repository;
  final servers = <FakeTv>[];

  setUp(() => repository = TvRepository(MemoryStore()));

  tearDown(() async {
    for (final server in servers) {
      await server.stop();
    }
    servers.clear();
  });

  Future<FakeTv> start(String title, {int? port}) async {
    final server = await FakeTv.start(title: title, port: port);
    servers.add(server);
    return server;
  }

  test('pareia pelo QR e guarda o endpoint', () async {
    final tv = await start('StickClock');
    final endpoint = await repository.pair(
      'http://127.0.0.1:${tv.port}/?k=${tv.token}',
    );

    expect(endpoint.kind, AppKind.stickclock);
    expect(await repository.load(), [endpoint]);
  });

  test('não pareia sem token', () async {
    final tv = await start('HomeCam');
    expect(
      () => repository.pair('http://127.0.0.1:${tv.port}/'),
      throwsA(isA<InvalidConnectionUrlException>()),
    );
  });

  test('não pareia se nenhum app do couchkit responde', () async {
    final tv = await start('Outra coisa');
    expect(
      () => repository.pair('http://127.0.0.1:${tv.port}/?k=x'),
      throwsA(isA<TvUnreachableException>()),
    );
  });

  test('parear de novo o mesmo app substitui, sem duplicar', () async {
    final first = await start('StickHub');
    await repository.pair('http://127.0.0.1:${first.port}/?k=old');
    final second = await start('StickHub');
    await repository.pair('http://127.0.0.1:${second.port}/?k=new');

    final saved = await repository.load();
    expect(saved, hasLength(1));
    expect(saved.single.token, 'new');
  });

  test('remove pelo id', () async {
    final tv = await start('PhoneCast');
    final endpoint = await repository.pair(
      'http://127.0.0.1:${tv.port}/?k=${tv.token}',
    );
    await repository.remove(endpoint.id);
    expect(await repository.load(), isEmpty);
  });

  test('isOnline distingue app certo, errado e fora do ar', () async {
    final tv = await start('PhoneBro Remote');
    final good = TvEndpoint(
      kind: AppKind.phonebro,
      host: '127.0.0.1',
      port: tv.port,
      token: 't',
    );
    expect(await repository.isOnline(good), isTrue);
    expect(
      await repository.isOnline(
        TvEndpoint(
          kind: AppKind.homecam,
          host: '127.0.0.1',
          port: tv.port,
          token: 't',
        ),
      ),
      isFalse,
    );
    await tv.stop();
    expect(await repository.isOnline(good), isFalse);
  });

  test('reencontra o app quando a porta muda', () async {
    var port = AppKind.phonecast.portStart;
    FakeTv? tv;
    while (tv == null && port <= AppKind.phonecast.portEnd) {
      try {
        tv = await start('PhoneCast', port: port);
      } on Exception {
        port++;
      }
    }
    expect(tv, isNotNull);

    const stale = TvEndpoint(
      kind: AppKind.phonecast,
      host: '127.0.0.1',
      port: 1,
      token: 'tok',
    );
    final moved = await repository.relocate(stale);

    expect(moved?.port, tv!.port);
    expect(moved?.token, 'tok');
    expect((await repository.load()).single.port, tv.port);
  });

  group('discover', () {
    Future<FakeTv> fixed(String title, int port, {String token = 'a1b2c3d4'}) {
      return FakeTv.start(title: title, port: port, token: token).then((tv) {
        servers.add(tv);
        return tv;
      });
    }

    test(
      'acha os apps que aceitam o token e ignora os de outro token',
      () async {
        await fixed('PhoneBro Remote', 48101);
        await fixed('HomeCam', 48102);
        await fixed('StickClock', 48103, token: 'outro999');
        final ranges = {
          AppKind.phonebro: (48101, 48101),
          AppKind.homecam: (48102, 48102),
          AppKind.stickclock: (48103, 48103),
        };

        final found = await repository.discover(
          '127.0.0.1',
          'a1b2c3d4',
          ranges: ranges,
        );

        expect(found.map((e) => e.kind).toSet(), {
          AppKind.phonebro,
          AppKind.homecam,
        });
        expect((await repository.load()).length, 2);
      },
    );

    test('adopt cadastra a TV quando o StickHub responde', () async {
      await fixed('StickHub', 48111);
      await fixed('HomeCam', 48112);
      final ranges = {
        AppKind.stickhub: (48111, 48111),
        AppKind.homecam: (48112, 48112),
      };

      final count = await repository.adopt(
        '127.0.0.1',
        'a1b2c3d4',
        attempts: 2,
        wait: const Duration(milliseconds: 10),
        ranges: ranges,
      );

      expect(count, 2);
      expect(await repository.tokenOf('127.0.0.1'), 'a1b2c3d4');
    });

    test('adopt devolve 0 se nenhum app responder', () async {
      final count = await repository.adopt(
        '127.0.0.1',
        'a1b2c3d4',
        attempts: 2,
        wait: const Duration(milliseconds: 10),
        ranges: {AppKind.stickhub: (48121, 48121)},
      );

      expect(count, 0);
      expect(await repository.tokenOf('127.0.0.1'), isNull);
    });
  });
}
