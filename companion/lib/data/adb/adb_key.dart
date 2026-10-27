import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Chave RSA que identifica este celular para o adbd da TV. Fica no cofre do
/// celular; depois de aprovada na TV ("Sempre permitir") nao pergunta mais.
class AdbKey {
  AdbKey({
    required this.modulus,
    required this.publicExponent,
    required this.privateExponent,
    required this.p,
    required this.q,
  });

  factory AdbKey.fromJson(Map<String, dynamic> json) {
    BigInt big(String key) => BigInt.parse('${json[key]}', radix: 16);
    return AdbKey(
      modulus: big('n'),
      publicExponent: big('e'),
      privateExponent: big('d'),
      p: big('p'),
      q: big('q'),
    );
  }

  /// DigestInfo do SHA-1: o adbd assina o token como se ele fosse o hash.
  static final _sha1Prefix = Uint8List.fromList([
    0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, //
    0x05, 0x00, 0x04, 0x14,
  ]);

  final BigInt modulus;
  final BigInt publicExponent;
  final BigInt privateExponent;
  final BigInt p;
  final BigInt q;

  /// Gera uma chave de 2048 bits em outro isolate (leva alguns segundos).
  static Future<AdbKey> generate() async {
    final json = await Isolate.run(_generateJson);
    return AdbKey.fromJson(json);
  }

  static Map<String, dynamic> _generateJson() {
    final seed = Random.secure();
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256))),
        ),
      );
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    final public = pair.publicKey;
    final private = pair.privateKey;
    return {
      'n': public.modulus!.toRadixString(16),
      'e': public.exponent!.toRadixString(16),
      'd': private.privateExponent!.toRadixString(16),
      'p': private.p!.toRadixString(16),
      'q': private.q!.toRadixString(16),
    };
  }

  Map<String, String> toJson() => {
    'n': modulus.toRadixString(16),
    'e': publicExponent.toRadixString(16),
    'd': privateExponent.toRadixString(16),
    'p': p.toRadixString(16),
    'q': q.toRadixString(16),
  };

  /// Assina o token do adbd (RSA PKCS#1 v1.5 sobre DigestInfo SHA-1 + token).
  Uint8List sign(Uint8List token) {
    final engine = PKCS1Encoding(RSAEngine())
      ..init(
        true,
        PrivateKeyParameter<RSAPrivateKey>(
          RSAPrivateKey(modulus, privateExponent, p, q),
        ),
      );
    return engine.process(Uint8List.fromList([..._sha1Prefix, ...token]));
  }

  /// Linha enviada ao adbd: chave no formato "mincrypt" do Android em base64,
  /// um espaco, o nome do cliente e um byte zero.
  Uint8List publicKeyLine([String name = 'couchkit@celular']) {
    final line = '${base64.encode(publicKeyBlob())} $name';
    return Uint8List.fromList([...utf8.encode(line), 0]);
  }

  /// struct RSAPublicKey: tamanho (64 palavras), n0inv, n, R^2 mod n e e.
  Uint8List publicKeyBlob() {
    final r32 = BigInt.one << 32;
    final n0inv = (r32 - modulus.modInverse(r32)) & (r32 - BigInt.one);
    final rr = (BigInt.one << 4096) % modulus;
    final data = ByteData(524);
    data.setUint32(0, 64, Endian.little);
    data.setUint32(4, n0inv.toInt(), Endian.little);
    final bytes = data.buffer.asUint8List();
    bytes.setRange(8, 264, _littleEndian(modulus, 256));
    bytes.setRange(264, 520, _littleEndian(rr, 256));
    data.setUint32(520, publicExponent.toInt(), Endian.little);
    return bytes;
  }

  static Uint8List _littleEndian(BigInt value, int length) {
    final out = Uint8List(length);
    var rest = value;
    for (var i = 0; i < length; i++) {
      out[i] = (rest & BigInt.from(0xff)).toInt();
      rest = rest >> 8;
    }
    return out;
  }
}
