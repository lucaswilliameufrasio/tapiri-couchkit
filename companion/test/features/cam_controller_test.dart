import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/core/network/tv_client.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/services/cam_service.dart';
import 'package:couchkit_remote/features/cam/cam_controller.dart';

/// HomeCam falso: guarda a config, lista streams e registra add/remove.
class _FakeHomeCam {
  Map<String, dynamic> cfg = {
    'cols': 3,
    'servers': [
      {
        'id': 's1',
        'name': 'Casa',
        'url': 'http://x:1984',
        'user': '',
        'pass': '',
      },
    ],
    'direct': <Object>[],
    'cams': <Object>[],
  };
  final streams = ['garagem', 'quintal'];
  final calls = <String>[];
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.5', 0);
    server.listen((request) async {
      final path = request.uri.path;
      final body = await utf8.decoder.bind(request).join();
      Object reply = {'ok': true};
      if (path == '/api/cfg') {
        if (request.method == 'POST') {
          cfg = jsonDecode(body) as Map<String, dynamic>;
        }
        reply = cfg;
      } else if (path == '/api/cams') {
        reply = {'ok': true, 'cams': _cams(), 'errors': <Object>[]};
      } else if (path == '/api/add' || path == '/api/remove') {
        calls.add('$path $body');
        if (path == '/api/add') {
          streams.add((jsonDecode(body) as Map)['name'] as String);
        }
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reply));
      await request.response.close();
    });
  }

  List<Map<String, Object>> _cams() {
    final order = (cfg['cams'] as List).cast<Map>();
    final all = <String, Map<String, Object>>{
      for (final s in streams)
        's1/$s': {
          'key': 's1/$s',
          'name': s,
          'hidden': false,
          'direct': false,
          'server': 's1',
          'stream': s,
        },
      for (final d in (cfg['direct'] as List).cast<Map>())
        'd:${d['id']}': {
          'key': 'd:${d['id']}',
          'name': '${d['name']}',
          'hidden': false,
          'direct': true,
          'server': '',
          'stream': '',
        },
    };
    final out = <Map<String, Object>>[];
    for (final o in order) {
      final entry = all.remove(o['key']);
      if (entry != null) {
        if ('${o['name']}'.isNotEmpty) {
          entry['name'] = '${o['name']}';
        }
        entry['hidden'] = o['hidden'] == true;
        out.add(entry);
      }
    }
    return [...out, ...all.values];
  }
}

void main() {
  late _FakeHomeCam fake;
  late CamController controller;
  var seq = 0;

  setUp(() async {
    fake = _FakeHomeCam();
    await fake.start();
    final endpoint = TvEndpoint(
      kind: AppKind.homecam,
      host: '127.0.0.5',
      port: fake.server.port,
      token: 'a1b2c3d4',
    );
    seq = 0;
    controller = CamController(
      CamService(TvClient(endpoint)),
      newId: () => 'id${seq++}',
    );
    await controller.load();
  });

  tearDown(() => fake.server.close(force: true));

  test('carrega servidores e câmeras', () {
    expect(controller.settings.servers.single.name, 'Casa');
    expect(controller.listing.cams.map((c) => c.name), ['garagem', 'quintal']);
  });

  test('reordenar, renomear e ocultar gravam na TV', () async {
    await controller.reorder(0, 1); // garagem passa a ser a segunda
    expect(controller.listing.cams.first.name, 'quintal');

    await controller.rename(controller.listing.cams.first, 'Pátio');
    await controller.toggleHidden(controller.listing.cams.last);

    final saved = (fake.cfg['cams'] as List).cast<Map>();
    expect(saved.map((c) => c['key']), ['s1/quintal', 's1/garagem']);
    expect(saved.first['name'], 'Pátio');
    expect(saved.last['name'], '', reason: 'nome original não vira apelido');
    expect(saved.last['hidden'], true);
  });

  test('servidor com senha é salvo e colunas mudam', () async {
    await controller.saveServer(
      controller.newServer(
        name: 'Sítio',
        url: 'http://y:1984',
        user: 'admin',
        pass: 'segredo',
      ),
    );
    await controller.setCols(4);

    final servers = (fake.cfg['servers'] as List).cast<Map>();
    expect(servers.last['id'], 'sid0');
    expect(servers.last['user'], 'admin');
    expect(servers.last['pass'], 'segredo');
    expect(fake.cfg['cols'], 4);
  });

  test('adicionar câmera no go2rtc e RTSP direto', () async {
    await controller.addCamera(
      name: 'Sala',
      src: 'rtmp://10.0.0.9/live',
      serverId: 's1',
    );
    expect(fake.calls.single, contains('"name":"Sala"'));
    expect(controller.listing.cams.map((c) => c.name), contains('Sala'));

    await controller.addCamera(name: 'Porta', src: 'rtsp://u:p@10.0.0.7/s');
    expect((fake.cfg['direct'] as List).single['name'], 'Porta');
    expect(controller.listing.cams.any((c) => c.direct), isTrue);

    expect(
      () => controller.addCamera(name: 'X', src: 'rtmp://10.0.0.8/live'),
      throwsA(isA<TvRequestException>()),
    );
  });

  test('remover câmera direta tira da lista e da ordem', () async {
    await controller.addCamera(name: 'Porta', src: 'rtsp://10.0.0.7/s');
    final direct = controller.listing.cams.firstWhere((c) => c.direct);
    await controller.removeCamera(direct);
    expect(fake.cfg['direct'], isEmpty);
    expect(controller.listing.cams.any((c) => c.direct), isFalse);
  });
}
