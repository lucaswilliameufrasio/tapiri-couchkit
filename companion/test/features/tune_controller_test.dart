import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/tune_profiles.dart';
import 'package:couchkit_remote/data/tv_adb.dart';
import 'package:couchkit_remote/features/tune/tune_controller.dart';

void main() {
  const port = 45556;
  late Process fake;
  late TuneController controller;
  final log = StringBuffer();

  setUpAll(() async {
    fake = await Process.start('python3', [
      '-u',
      '../tools/fake_adbd.py',
      '$port',
    ]);
    fake.stdout.transform(utf8.decoder).listen(log.write);
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });

  tearDownAll(() => fake.kill());

  setUp(() {
    log.clear();
    controller = TuneController(TvAdb(MemoryStore(), port: port), '127.0.0.1');
  });

  test('conectar mostra o modelo e passa pela aprovação', () async {
    final states = <TuneState>[];
    controller.addListener(() => states.add(controller.state));

    await controller.connect();

    expect(controller.state, TuneState.ready);
    expect(controller.model, 'fake:shell:getprop ro.product.model');
    expect(states, contains(TuneState.waiting));
  });

  test('aplicar roda cada comando e conta o progresso', () async {
    final profile = tuneProfiles.firstWhere((p) => p.id == 'animacoes');

    await controller.run(profile);

    expect(controller.state, TuneState.ready);
    expect(controller.done, profile.apply.length);
    expect(controller.lastDone, 'animacoes');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      log.toString(),
      contains('settings put global window_animation_scale 0.5'),
    );
  });

  test('desfazer usa a lista de volta', () async {
    final profile = tuneProfiles.firstWhere((p) => p.id == 'debloat');

    await controller.run(profile, undo: true);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(log.toString(), contains('pm enable com.amazon.gamehub'));
    expect(log.toString(), isNot(contains('disable-user')));
  });

  test('sem adbd vira estado de falha com mensagem', () async {
    final broken = TuneController(
      TvAdb(MemoryStore(), port: 45998),
      '127.0.0.1',
    );

    await broken.connect();

    expect(broken.state, TuneState.failed);
    expect(broken.error, isNotEmpty);
  });

  test('perfis: debloat cobre os pacotes e privacidade desfaz', () {
    final debloat = tuneProfiles.firstWhere((p) => p.id == 'debloat');
    final privacy = tuneProfiles.firstWhere((p) => p.id == 'privacidade');

    expect(debloat.apply.length, debloatPackages.length);
    expect(privacy.apply, isNot(privacy.undo));
    expect(tuneProfiles.last.undoable, isFalse);
  });
}
