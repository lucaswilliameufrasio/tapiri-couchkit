import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/network/tv_client.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/services/firehome_service.dart';
import 'package:couchkit_remote/features/firehome/firehome_controller.dart';

import '../test_server.dart';

Map<String, Object?> initialConfig() => {
  'theme': {
    'bg': ['#0B1020', '#1B1140', '#3A1550'],
    'accent': '#5CC8FF',
    'radius': 14,
    'scale': 100,
    'labelSize': 14,
  },
  'wallpaper': {'on': false, 'dim': 55},
  'header': {'clock': true, 'greeting': '', 'city': ''},
  'hint': true,
  'rows': [
    {'id': 'fav', 'type': 'pins', 'title': 'Favoritos', 'show': true},
    {'id': 'all', 'type': 'all', 'title': 'Todos', 'show': true},
  ],
  'pins': ['a.one', 'b.two', 'c.three'],
  'hidden': <String>[],
  'tools': ['settings'],
  'names': <String, String>{},
};

void main() {
  late FakeTv tv;
  late FireHomeController controller;

  setUp(() async {
    tv = await FakeTv.start(
      title: 'FireHome',
      api: (path) => switch (path) {
        '/api/config' => jsonEncode(initialConfig()),
        '/api/apps' => jsonEncode([
          {'pkg': 'a.one', 'label': 'Um'},
          {'pkg': 'b.two', 'label': 'Dois'},
        ]),
        _ => jsonEncode({'ok': true}),
      },
    );
    final endpoint = TvEndpoint(
      kind: AppKind.firehome,
      host: '127.0.0.1',
      port: tv.port,
      token: tv.token,
    );
    controller = FireHomeController(FireHomeService(TvClient(endpoint)));
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await tv.stop();
  });

  test('carrega configuração e apps', () {
    expect(controller.error, isNull);
    expect(controller.pins, ['a.one', 'b.two', 'c.three']);
    expect(controller.labelFor('a.one'), 'Um');
    expect(controller.labelFor('zzz'), 'zzz');
  });

  test('várias edições seguidas viram um único POST', () async {
    controller.togglePin('b.two');
    controller.toggleHidden('a.one');
    controller.rename('a.one', '  Meu app ');
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(tv.bodies, hasLength(1));
    final saved = jsonDecode(tv.bodies.single) as Map<String, dynamic>;
    expect(saved['pins'], ['a.one', 'c.three']);
    expect(saved['hidden'], ['a.one']);
    expect((saved['names'] as Map)['a.one'], 'Meu app');
  });

  test('reordenar favoritos mantém todos', () async {
    controller.movePin(0, 2);
    expect(controller.pins, ['b.two', 'c.three', 'a.one']);
    controller.movePin(2, 0);
    expect(controller.pins, ['a.one', 'b.two', 'c.three']);
  });

  test('nome vazio remove o apelido', () {
    controller.rename('a.one', 'X');
    expect(controller.labelFor('a.one'), 'X');
    controller.rename('a.one', '   ');
    expect(controller.labelFor('a.one'), 'Um');
  });

  test('nova linha personalizada entra no fim', () {
    controller.addCustomRow();
    final last = controller.rows.last as Map<String, dynamic>;
    expect(last['type'], 'custom');
    expect(last['apps'], isEmpty);
  });
}
