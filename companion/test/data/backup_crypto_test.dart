import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/backup/backup_crypto.dart';

void main() {
  // poucas rodadas só para o teste ser rápido; o padrão do app é 300 mil
  const crypto = BackupCrypto(iterations: 2000);
  final plain = Uint8List.fromList(utf8.encode('{"token":"a1b2c3d4"}'));

  test('cifra e decifra com a mesma senha', () async {
    final file = await crypto.encrypt(plain, 'senha forte 123');
    expect(await crypto.decrypt(file, 'senha forte 123'), plain);
  });

  test('o arquivo não deixa o conteúdo à vista', () async {
    final file = utf8.decode(await crypto.encrypt(plain, 'x'));
    expect(file.contains('a1b2c3d4'), isFalse);
    expect(file.contains('token'), isFalse);
  });

  test('cada backup usa sal e nonce novos', () async {
    final a = await crypto.encrypt(plain, 'x');
    final b = await crypto.encrypt(plain, 'x');
    expect(a, isNot(b));
  });

  test('senha errada é recusada com mensagem clara', () async {
    final file = await crypto.encrypt(plain, 'certa');
    expect(
      () => crypto.decrypt(file, 'errada'),
      throwsA(isA<BackupException>()),
    );
  });

  test('arquivo adulterado é recusado', () async {
    final file = await crypto.encrypt(plain, 'x');
    final envelope = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
    final data = base64Decode(envelope['data'] as String);
    data[0] ^= 1;
    envelope['data'] = base64Encode(data);
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    expect(
      () => crypto.decrypt(tampered, 'x'),
      throwsA(isA<BackupException>()),
    );
  });

  test('trocar as rodadas no envelope quebra a autenticação', () async {
    final file = await crypto.encrypt(plain, 'x');
    final envelope = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
    envelope['iter'] = 2001;
    final other = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    expect(() => crypto.decrypt(other, 'x'), throwsA(isA<BackupException>()));
  });

  test('arquivo qualquer não vira backup', () async {
    expect(
      () => crypto.decrypt(Uint8List.fromList([1, 2, 3]), 'x'),
      throwsA(isA<BackupException>()),
    );
  });

  test('custo real: o padrão do app leva poucos segundos', () async {
    final watch = Stopwatch()..start();
    await const BackupCrypto().encrypt(plain, 'x');
    expect(watch.elapsed.inSeconds, lessThan(20));
    // ignore: avoid_print
    print('PBKDF2 300k: ${watch.elapsedMilliseconds} ms');
  });
}
