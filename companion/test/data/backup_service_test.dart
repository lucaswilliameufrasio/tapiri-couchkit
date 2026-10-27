import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/backup/backup_crypto.dart';
import 'package:couchkit_remote/data/backup/backup_service.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/panel.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/panels_repository.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/tv_repository.dart';
import 'package:couchkit_remote/data/tv_service_factory.dart';

/// App da TV falso que guarda o JSON recebido na rota de config.
class _ConfigTv {
  _ConfigTv(this.path, this.config);

  final String path;
  Map<String, dynamic> config;
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.6', 0);
    server.listen((request) async {
      if (request.uri.path == path) {
        if (request.method == 'POST') {
          config = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
        }
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(config));
      }
      await request.response.close();
    });
  }
}

void main() {
  const crypto = BackupCrypto(iterations: 1000);
  late _ConfigTv cam;
  late _ConfigTv fire;

  setUp(() async {
    cam = _ConfigTv('/api/cfg', {
      'cols': 4,
      'servers': [
        {
          'id': 's1',
          'name': 'Casa',
          'url': 'http://g:1984',
          'user': 'admin',
          'pass': 'segredo',
        },
      ],
      'direct': <Object>[],
      'cams': <Object>[],
    });
    fire = _ConfigTv('/api/config', {'rows': 3});
    await cam.start();
    await fire.start();
  });

  tearDown(() async {
    await cam.server.close(force: true);
    await fire.server.close(force: true);
  });

  BackupService build(MemoryStore store) => BackupService(
    store,
    TvRepository(store),
    PanelsRepository(store),
    const TvServiceFactory(),
    crypto: crypto,
  );

  test(
    'exporta de um celular e restaura em outro, reenviando às TVs',
    () async {
      final a = MemoryStore();
      final tvsA = TvRepository(a);
      await tvsA.save(
        TvEndpoint(
          kind: AppKind.homecam,
          host: '127.0.0.6',
          port: cam.server.port,
          token: 'a1b2c3d4',
        ),
      );
      await tvsA.save(
        TvEndpoint(
          kind: AppKind.firehome,
          host: '127.0.0.6',
          port: fire.server.port,
          token: 'a1b2c3d4',
        ),
      );
      await tvsA.renameHost('127.0.0.6', 'Sala');
      await tvsA.selectHost('127.0.0.6');
      await PanelsRepository(a).save(
        const Panel(id: 'p1', name: 'Grafana', url: 'https://g.example/d'),
      );
      await a.write('adb_key', '{"n":"1"}');

      final file = await build(a).export('senha-de-teste');
      expect(utf8.decode(file).contains('segredo'), isFalse);
      expect(utf8.decode(file).contains('a1b2c3d4'), isFalse);

      // a TV perdeu a configuração; o celular B está vazio
      cam.config = {
        'cols': 2,
        'servers': <Object>[],
        'direct': <Object>[],
        'cams': <Object>[],
      };
      fire.config = {};
      final b = MemoryStore();
      final report = await build(b).restore(file, 'senha-de-teste');

      expect(report.tvs, 1);
      expect(report.panels, 1);
      expect(report.adbKey, isTrue);
      expect(report.failed, isEmpty);
      expect(report.pushed.length, 2);
      expect(await b.read('adb_key'), '{"n":"1"}');
      expect(await TvRepository(b).loadNames(), {'127.0.0.6': 'Sala'});
      expect(await TvRepository(b).selectedHost(), '127.0.0.6');
      expect((await TvRepository(b).load()).length, 2);
      expect((await PanelsRepository(b).load()).single.name, 'Grafana');
      expect(cam.config['cols'], 4);
      expect((cam.config['servers'] as List).single['pass'], 'segredo');
      expect(fire.config['rows'], 3);
    },
  );

  test('TV desligada fica de fora, sem derrubar o backup', () async {
    final a = MemoryStore();
    await TvRepository(a).save(
      const TvEndpoint(
        kind: AppKind.homecam,
        host: '127.0.0.6',
        port: 1,
        token: 'a1b2c3d4',
      ),
    );
    final file = await build(a).export('senha-de-teste');
    final report = await build(MemoryStore()).restore(file, 'senha-de-teste');
    expect(report.tvs, 1);
    expect(report.pushed, isEmpty);
  });

  test('senha errada não restaura nada', () async {
    final a = MemoryStore();
    final file = await build(a).export('certa-certa');
    final b = MemoryStore();
    await expectLater(
      build(b).restore(file, 'errada'),
      throwsA(isA<BackupException>()),
    );
    expect(await TvRepository(b).load(), isEmpty);
  });
}
