import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Certificado de cliente do celular para o Android TV Remote v2. A TV guarda
/// este certificado quando o pareamento (codigo de 6 digitos) termina e depois
/// so aceita comandos de quem o apresenta.
class AtvIdentity {
  const AtvIdentity({required this.certPem, required this.keyPem});

  factory AtvIdentity.fromJson(Map<String, dynamic> json) =>
      AtvIdentity(certPem: '${json['cert']}', keyPem: '${json['key']}');

  final String certPem;
  final String keyPem;

  Map<String, String> toJson() => {'cert': certPem, 'key': keyPem};

  /// Gera chave RSA 2048 + certificado autoassinado (alguns segundos).
  static Future<AtvIdentity> generate({String name = 'couchkit'}) async {
    final json = await Isolate.run(() => _generate(name));
    return AtvIdentity.fromJson(json);
  }

  static Map<String, String> _generate(String name) {
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
    final n = public.modulus!;
    final e = public.exponent!;

    final dn = _seq([
      _der(0x31, _seq([_oid('2.5.4.3'), _der(0x0c, utf8.encode(name))])),
    ]);
    final sha256Rsa = _seq([_oid('1.2.840.113549.1.1.11'), _der(0x05, [])]);
    final now = DateTime.now().toUtc();
    final tbs = _seq([
      _der(0xa0, _int(BigInt.two)),
      _int(BigInt.from(1000)),
      sha256Rsa,
      dn,
      _seq([_utc(now), _utc(now.add(const Duration(days: 3650)))]),
      dn,
      _seq([
        _seq([_oid('1.2.840.113549.1.1.1'), _der(0x05, [])]),
        _der(0x03, [
          0,
          ..._seq([_int(n), _int(e)]),
        ]),
      ]),
      _der(
        0xa3,
        _seq([
          _seq([
            _oid('2.5.29.19'),
            _der(
              0x04,
              _seq([
                _der(0x01, [0xff]),
                _int(BigInt.zero),
              ]),
            ),
          ]),
          _seq([
            _oid('2.5.29.17'),
            _der(0x04, _seq([_der(0x82, utf8.encode(name))])),
          ]),
        ]),
      ),
    ]);
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(private));
    final signature = signer.generateSignature(tbs).bytes;
    final cert = _seq([
      tbs,
      sha256Rsa,
      _der(0x03, [0, ...signature]),
    ]);

    final p = private.p!;
    final q = private.q!;
    final d = private.privateExponent!;
    final key = _seq([
      _int(BigInt.zero),
      _int(n),
      _int(e),
      _int(d),
      _int(p),
      _int(q),
      _int(d % (p - BigInt.one)),
      _int(d % (q - BigInt.one)),
      _int(q.modInverse(p)),
    ]);
    return {
      'cert': _pem('CERTIFICATE', cert),
      'key': _pem('RSA PRIVATE KEY', key),
    };
  }

  /// Modulo e expoente da chave publica de um certificado X.509 (DER).
  static (BigInt, BigInt) publicNumbers(Uint8List certDer) {
    final tbs = _children(_children(certDer).first.value).first;
    final fields = _children(tbs.value);
    final base = fields.first.tag == 0xa0 ? 1 : 0;
    final spki = _children(fields[base + 5].value);
    final bits = spki[1].value;
    final rsa = _children(
      _children(Uint8List.sublistView(bits, 1)).first.value,
    );
    return (_bigInt(rsa[0].value), _bigInt(rsa[1].value));
  }

  /// DER do certificado deste celular (para o calculo do codigo de pareamento).
  Uint8List get certDer {
    final body = certPem
        .split('\n')
        .where((line) => !line.startsWith('-----') && line.isNotEmpty)
        .join();
    return base64Decode(body);
  }

  static BigInt _bigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}

class _Tlv {
  const _Tlv(this.tag, this.value);

  final int tag;
  final Uint8List value;
}

List<_Tlv> _children(Uint8List data) {
  final out = <_Tlv>[];
  var pos = 0;
  while (pos < data.length) {
    final tag = data[pos++];
    var length = data[pos++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | data[pos++];
      }
    }
    out.add(_Tlv(tag, Uint8List.sublistView(data, pos, pos + length)));
    pos += length;
  }
  return out;
}

Uint8List _der(int tag, List<int> content) {
  final head = <int>[tag];
  if (content.length < 0x80) {
    head.add(content.length);
  } else {
    final length = <int>[];
    var v = content.length;
    while (v > 0) {
      length.insert(0, v & 0xff);
      v >>= 8;
    }
    head
      ..add(0x80 | length.length)
      ..addAll(length);
  }
  return Uint8List.fromList([...head, ...content]);
}

Uint8List _seq(List<List<int>> items) =>
    _der(0x30, [for (final item in items) ...item]);

Uint8List _int(BigInt value) {
  if (value == BigInt.zero) {
    return _der(0x02, [0]);
  }
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) {
    hex = '0$hex';
  }
  final bytes = <int>[
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  if (bytes.first & 0x80 != 0) {
    bytes.insert(0, 0);
  }
  return _der(0x02, bytes);
}

Uint8List _oid(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final out = <int>[parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7f];
    var v = part >> 7;
    while (v > 0) {
      chunk.insert(0, (v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.addAll(chunk);
  }
  return _der(0x06, out);
}

Uint8List _utc(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final text =
      '${two(t.year % 100)}${two(t.month)}${two(t.day)}'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  return _der(0x17, ascii.encode(text));
}

String _pem(String label, List<int> der) {
  final body = base64Encode(der);
  final lines = [
    for (var i = 0; i < body.length; i += 64)
      body.substring(i, min(i + 64, body.length)),
  ];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}
