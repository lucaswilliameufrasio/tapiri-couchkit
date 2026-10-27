import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/tv_repository.dart';
import 'package:couchkit_remote/features/home/home_controller.dart';

TvEndpoint endpoint(AppKind kind, String host, {String token = 'a1b2c3d4'}) {
  return TvEndpoint(kind: kind, host: host, port: kind.portStart, token: token);
}

void main() {
  late TvRepository repository;
  late HomeController controller;

  setUp(() async {
    repository = TvRepository(MemoryStore());
    // loopback: as sondas da descoberta são recusadas na hora
    await repository.save(endpoint(AppKind.stickhub, '127.0.0.3'));
    await repository.save(endpoint(AppKind.firehome, '127.0.0.3'));
    await repository.save(
      endpoint(AppKind.stickhub, '127.0.0.4', token: 'e5f6a7b8'),
    );
    controller = HomeController(repository);
    await controller.load();
  });

  test('começa na primeira TV e mostra só os apps dela', () {
    expect(controller.hosts, ['127.0.0.3', '127.0.0.4']);
    expect(controller.currentHost, '127.0.0.3');
    expect(controller.current.length, 2);
    expect(controller.hub?.token, 'a1b2c3d4');
  });

  test('trocar de TV troca o StickHub e lembra a escolha', () async {
    await controller.select('127.0.0.4');

    expect(controller.current.length, 1);
    expect(controller.hub?.token, 'e5f6a7b8');
    expect(await repository.selectedHost(), '127.0.0.4');
  });

  test('renomear usa o nome e vazio volta ao endereço', () async {
    await controller.rename('127.0.0.3', 'Sala');
    expect(controller.nameOf('127.0.0.3'), 'Sala');

    await controller.rename('127.0.0.3', '  ');
    expect(controller.nameOf('127.0.0.3'), '127.0.0.3');
  });

  test('remover a TV em uso passa para a outra e apaga tudo dela', () async {
    await controller.rename('127.0.0.3', 'Sala');
    await controller.removeHost('127.0.0.3');

    expect(controller.hosts, ['127.0.0.4']);
    expect(controller.currentHost, '127.0.0.4');
    expect((await repository.loadNames()).containsKey('127.0.0.3'), isFalse);
    final left = await repository.load();
    expect(left.every((e) => e.host == '127.0.0.4'), isTrue);
  });

  test('escolha de uma TV que sumiu cai na primeira', () async {
    await controller.select('127.0.0.4');
    await controller.removeHost('127.0.0.4');

    expect(controller.currentHost, '127.0.0.3');
  });
}
