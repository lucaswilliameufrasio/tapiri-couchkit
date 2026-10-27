import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/adb/adb_connection.dart';
import 'package:couchkit_remote/data/adb/adb_key.dart';
import 'package:couchkit_remote/data/adb/adb_message.dart';

void main() {
  late AdbKey key;

  setUpAll(() async {
    key = await AdbKey.generate();
  });

  group('AdbKey', () {
    test('a chave pública segue o formato do Android (mincrypt)', () {
      final blob = key.publicKeyBlob();
      final data = ByteData.sublistView(blob);
      final r32 = BigInt.one << 32;

      expect(blob.length, 524);
      expect(data.getUint32(0, Endian.little), 64);
      // n0inv * n[0] == -1 (mod 2^32)
      final n0inv = BigInt.from(data.getUint32(4, Endian.little));
      expect((n0inv * (key.modulus % r32) + BigInt.one) % r32, BigInt.zero);
      expect(data.getUint32(520, Endian.little), 65537);
      expect(blob[8], (key.modulus & BigInt.from(0xff)).toInt());
    });

    test('a assinatura confere com a chave pública (PKCS#1 + SHA-1)', () {
      final token = Uint8List.fromList(List.generate(20, (i) => i * 7));
      final signature = key.sign(token);

      final decoded = BigInt.parse(
        signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16,
      ).modPow(key.publicExponent, key.modulus);
      final bytes = decoded.toRadixString(16).padLeft(510, '0');
      final tail = bytes.substring(bytes.length - (15 + 20) * 2);

      expect(signature.length, 256);
      expect(bytes.startsWith('01ff'), isTrue);
      expect(tail, '3021300906052b0e03021a05000414${_hex(token)}');
    });

    test('guarda e lê a chave sem perder nada', () {
      final again = AdbKey.fromJson(key.toJson());
      expect(again.modulus, key.modulus);
      expect(again.sign(Uint8List(20)), key.sign(Uint8List(20)));
    });
  });

  test('mensagem ADB: cabeçalho, soma e magic', () {
    final message = AdbMessage(
      AdbCommand.open,
      1,
      0,
      Uint8List.fromList([1, 2, 3]),
    );
    final bytes = message.encode();
    final header = ByteData.sublistView(bytes);

    expect(bytes.length, 27);
    expect(header.getUint32(12, Endian.little), 3);
    expect(header.getUint32(16, Endian.little), 6);
    expect(header.getUint32(20, Endian.little), AdbCommand.open ^ 0xffffffff);
  });

  group('contra o adbd falso (tools/fake_adbd.py)', () {
    const port = 45555;
    Process? fake;
    final log = StringBuffer();

    setUpAll(() async {
      final script = File('../tools/fake_adbd.py');
      fake = await Process.start('python3', ['-u', script.path, '$port']);
      fake!.stdout.transform(utf8.decoder).listen(log.write);
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });

    tearDownAll(() => fake?.kill());

    test('chave nova pede aprovação; depois entra sem perguntar', () async {
      var asked = false;
      final first = await AdbConnection.open(
        '127.0.0.1',
        key,
        port: port,
        onWaitingApproval: () => asked = true,
      );
      expect(await first.shell('echo ola'), 'fake:shell:echo ola');
      await first.close();
      expect(asked, isTrue);

      var askedAgain = false;
      final second = await AdbConnection.open(
        '127.0.0.1',
        key,
        port: port,
        onWaitingApproval: () => askedAgain = true,
      );
      expect(await second.shell('id'), 'fake:shell:id');
      await second.close();
      expect(askedAgain, isFalse);
    });

    test('envia um arquivo grande por sync, em pedaços', () async {
      final connection = await AdbConnection.open('127.0.0.1', key, port: port);
      final bytes = Uint8List.fromList(List.generate(300000, (i) => i % 251));
      var lastSent = 0;
      await connection.push(
        bytes,
        '/data/local/tmp/ck.apk',
        onProgress: (sent, total) => lastSent = sent,
      );
      await connection.close();

      expect(lastSent, 300000);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(log.toString(), contains('/data/local/tmp/ck.apk,420 300000'));
    });

    test('porta sem adbd vira AdbException legível', () async {
      expect(
        () => AdbConnection.open('127.0.0.1', key, port: 45999),
        throwsA(isA<AdbException>()),
      );
    });
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
