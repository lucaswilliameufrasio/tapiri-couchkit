import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/core/network/tv_client.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';

import '../test_server.dart';

TvEndpoint endpointFor(FakeTv tv, {String? token}) => TvEndpoint(
  kind: AppKind.stickhub,
  host: '127.0.0.1',
  port: tv.port,
  token: token ?? tv.token,
);

void main() {
  late FakeTv tv;

  setUp(() async {
    tv = await FakeTv.start(
      title: 'StickHub',
      api: (path) => switch (path) {
        '/api/apps' => jsonEncode([
          {'pkg': 'a.b', 'label': 'App B', 'sys': false, 'launch': true},
        ]),
        '/api/info' => jsonEncode({'model': 'Amazon AFTMM', 'ramFree': 400}),
        _ => jsonEncode({'ok': true, 'msg': 'feito'}),
      },
    );
  });

  tearDown(() => tv.stop());

  test('envia o token em toda chamada', () async {
    await TvClient(endpointFor(tv)).getJson('/api/info');
    expect(tv.requests.single.queryParameters['k'], tv.token);
  });

  test('token errado vira TvUnauthorizedException', () async {
    final client = TvClient(endpointFor(tv, token: 'errado'));
    expect(
      () => client.getJson('/api/info'),
      throwsA(isA<TvUnauthorizedException>()),
    );
  });

  test('TV fora do ar vira TvUnreachableException', () async {
    final endpoint = endpointFor(tv);
    await tv.stop();
    expect(
      () => TvClient(endpoint).getJson('/api/info'),
      throwsA(isA<TvUnreachableException>()),
    );
    tv = await FakeTv.start(title: 'StickHub');
  });

  test('HubService lê lista (array) e info (objeto)', () async {
    final hub = HubService(TvClient(endpointFor(tv)));

    final apps = await hub.apps();
    expect(apps.single.label, 'App B');
    expect(apps.single.launchable, isTrue);

    final info = await hub.info();
    expect(info.model, 'Amazon AFTMM');
    expect(info.ramFreeMb, 400);
  });

  test('codifica parâmetros na query', () async {
    final hub = HubService(TvClient(endpointFor(tv)));
    await hub.openUrl('https://exemplo.com/a b?x=1&y=2');
    expect(
      tv.requests.last.queryParameters['url'],
      'https://exemplo.com/a b?x=1&y=2',
    );
  });
}
