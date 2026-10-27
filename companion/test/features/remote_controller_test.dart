import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/tv_adb.dart';
import 'package:couchkit_remote/features/remote/remote_controller.dart';

void main() {
  const port = 45558;
  late Process fake;
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

  test('teclas saem na ordem e o texto é higienizado', () async {
    final controller = RemoteController(
      TvAdb(MemoryStore(), port: port),
      '127.0.0.1',
    );
    await controller.connect();
    expect(controller.state, RemoteState.ready);

    controller
      ..press(RemoteKey.down)
      ..press(RemoteKey.ok)
      ..type("oi mundo; rm -rf /'")
      ..press(RemoteKey.back);
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final lines = log.toString().split('\n');
    final sent = lines.where((l) => l.contains('input ')).toList();
    expect(sent.length, 4);
    expect(sent[0], contains('input keyevent 20'));
    expect(sent[1], contains('input keyevent 23'));
    expect(sent[2], contains("input text 'oi%smundo%srm%s-rf%s'"));
    expect(sent[3], contains('input keyevent 4'));
  });

  test('sem adbd fica em falha com mensagem', () async {
    final controller = RemoteController(
      TvAdb(MemoryStore(), port: 45997),
      '127.0.0.1',
    );
    await controller.connect();
    expect(controller.state, RemoteState.failed);
    expect(controller.error, isNotEmpty);
    controller.dispose();
  });
}
