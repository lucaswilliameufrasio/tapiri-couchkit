import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';

/// Arquivo de backup: AES-256-GCM com chave derivada da senha (PBKDF2-SHA256).
/// O envelope e um JSON; so [data] e secreto, o resto (sal, nonce, rodadas)
/// precisa ficar a vista para abrir o arquivo.
class BackupCrypto {
  const BackupCrypto({this.iterations = 300000});

  static const _app = 'couchkit-backup';
  static const _version = 1;

  final int iterations;

  Future<Uint8List> encrypt(Uint8List plain, String password) async {
    final random = Random.secure();
    final salt = _random(random, 16);
    final nonce = _random(random, 12);
    final iter = iterations;
    final sealed = await Isolate.run(() {
      final key = _derive(password, salt, iter);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, nonce, _aad(iter)));
      return cipher.process(plain);
    });
    final envelope = {
      'app': _app,
      'v': _version,
      'kdf': 'pbkdf2-sha256',
      'iter': iter,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'data': base64Encode(sealed),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Future<Uint8List> decrypt(Uint8List file, String password) async {
    final Map<String, dynamic> envelope;
    final Uint8List salt;
    final Uint8List nonce;
    final Uint8List data;
    final int iter;
    try {
      envelope = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
      if (envelope['app'] != _app || envelope['v'] != _version) {
        throw const FormatException('formato');
      }
      salt = base64Decode('${envelope['salt']}');
      nonce = base64Decode('${envelope['nonce']}');
      data = base64Decode('${envelope['data']}');
      iter = envelope['iter'] as int;
    } on Object {
      throw const BackupException('Este arquivo não é um backup do Couchkit.');
    }
    if (iter < 1 || iter > 5000000) {
      throw const BackupException('Backup com parâmetros inválidos.');
    }
    try {
      return await Isolate.run(() {
        final key = _derive(password, salt, iter);
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(KeyParameter(key), 128, nonce, _aad(iter)),
          );
        return cipher.process(data);
      });
    } on InvalidCipherTextException {
      throw const BackupException('Senha incorreta ou arquivo danificado.');
    }
  }

  static Uint8List _random(Random random, int length) {
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _aad(int iter) {
    return Uint8List.fromList(utf8.encode('$_app:v$_version:$iter'));
  }

  static Uint8List _derive(String password, Uint8List salt, int iter) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iter, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }
}
