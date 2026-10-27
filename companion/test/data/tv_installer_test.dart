import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/tv_adb.dart';
import 'package:couchkit_remote/data/tv_installer.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.ids);

  final Set<String> ids;

  @override
  Future<ByteData> load(String key) async {
    final id = key.split('/').last.replaceAll('.apk', '');
    if (!ids.contains(id)) {
      throw FlutterError('sem asset $key');
    }
    return ByteData.sublistView(Uint8List.fromList(List.filled(1000, 7)));
  }
}

void main() {
  const port = 45557;
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

  setUp(log.clear);

  TvInstaller installer(Set<String> ids) =>
      TvInstaller(TvAdb(MemoryStore(), port: port), bundle: _Bundle(ids));

  test('available lista só os APKs embutidos', () async {
    final found = await installer({'stickhub', 'phonebro'}).available();
    expect(found.map((a) => a.id), ['stickhub', 'phonebro']);
  });

  test('envia, recria o registro, instala e abre o StickHub', () async {
    final steps = <String>[];
    final apps = tvApps.where((a) => a.id == 'stickhub').toList();

    final failures = await installer({'stickhub'}).install(
      '127.0.0.1',
      apps,
      openFirst: true,
      onProgress: (app, step, {sent, detail}) => steps.add('${app.id}:$step'),
    );

    expect(failures, isEmpty);
    expect(steps.last, 'stickhub:${InstallStep.done}');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final text = log.toString();
    expect(text, contains('/data/local/tmp/ck-stickhub.apk,420 1000'));
    expect(text, contains('pm uninstall -k com.lucas.stickhub'));
    expect(text, contains('pm install -r /data/local/tmp/ck-stickhub.apk'));
    expect(text, contains('rm -f /data/local/tmp/ck-stickhub.apk'));
    expect(text, contains('am start -n com.lucas.stickhub/.MainActivity'));
  });

  test('app sem APK embutido falha sem derrubar os outros', () async {
    final apps = tvApps
        .where((a) => a.id == 'stickhub' || a.id == 'firehome')
        .toList();
    final done = <String>[];

    final failures = await installer({'firehome'}).install(
      '127.0.0.1',
      apps,
      onProgress: (app, step, {sent, detail}) {
        if (step == InstallStep.done) {
          done.add(app.id);
        }
      },
    );

    expect(done, ['firehome']);
    expect(failures.keys, ['stickhub']);
  });
}
