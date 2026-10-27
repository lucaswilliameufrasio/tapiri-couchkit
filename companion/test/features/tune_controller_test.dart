import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/network/tv_client.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';
import 'package:couchkit_remote/features/tune/tune_controller.dart';

import '../test_server.dart';

void main() {
  late FakeTv tv;
  late TuneController controller;
  var adb = 'idle';
  var tune = '';

  setUp(() async {
    adb = 'idle';
    tune = '';
    tv = await FakeTv.start(
      title: 'StickHub',
      token: 'a1b2c3d4',
      api: (path) {
        if (path == '/api/tune') {
          return jsonEncode({'ok': true, 'msg': ''});
        }
        return jsonEncode({'state': adb, 'tune': tune});
      },
    );
    final endpoint = TvEndpoint(
      kind: AppKind.stickhub,
      host: '127.0.0.1',
      port: tv.port,
      token: tv.token,
    );
    controller = TuneController(HubService(TvClient(endpoint)));
  });

  tearDown(() async {
    controller.dispose();
    await tv.stop();
  });

  test('lê o estado do ADB e do perfil', () async {
    adb = 'waiting';
    await controller.refresh();
    expect(controller.status.waiting, isTrue);
    expect(controller.status.connected, isFalse);

    adb = 'ok';
    tune = 'rodando:debloat:3/21';
    await controller.refresh();
    expect(controller.status.connected, isTrue);
    expect(controller.status.running, isTrue);
  });

  test('erro do ADB vem sem o prefixo', () async {
    adb = 'error:Connection refused';
    await controller.refresh();
    expect(controller.status.error, 'Connection refused');
  });

  test('inicia um perfil com o nome certo e token', () async {
    adb = 'ok';
    final started = await controller.run('animacoes');

    expect(started, isTrue);
    final call = tv.requests.firstWhere((u) => u.path == '/api/tune');
    expect(call.queryParameters, {'k': 'a1b2c3d4', 'name': 'animacoes'});
  });
}
