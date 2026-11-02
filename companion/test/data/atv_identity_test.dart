import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/data/atv/atv_identity.dart';

void main() {
  test(
    'gera um certificado que o OpenSSL aceita e lê o modulo/expoente',
    () async {
      final identity = await AtvIdentity.generate();
      final dir = Directory.systemTemp.createTempSync('ck-atv');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/c.pem').writeAsStringSync(identity.certPem);
      File('${dir.path}/k.pem').writeAsStringSync(identity.keyPem);

      final text =
          Process.runSync('openssl', [
                'x509', '-in', '${dir.path}/c.pem', '-noout', '-text', //
              ]).stdout
              as String;
      expect(text, contains('Signature Algorithm: sha256WithRSAEncryption'));
      expect(text, contains('CN=couchkit'));
      expect(text, contains('CA:TRUE'));
      expect(text, contains('DNS:couchkit'));

      final check = Process.runSync('openssl', [
        'rsa', '-in', '${dir.path}/k.pem', '-check', '-noout', //
      ]);
      expect('${check.stdout}', contains('RSA key ok'));

      final certMod =
          Process.runSync('openssl', [
                'x509', '-in', '${dir.path}/c.pem', '-noout', '-modulus', //
              ]).stdout
              as String;
      final keyMod =
          Process.runSync('openssl', [
                'rsa', '-in', '${dir.path}/k.pem', '-noout', '-modulus', //
              ]).stdout
              as String;
      expect(certMod, keyMod);

      final (n, e) = AtvIdentity.publicNumbers(identity.certDer);
      expect(certMod.trim(), 'Modulus=${n.toRadixString(16).toUpperCase()}');
      expect(e, BigInt.from(65537));

      final verify = Process.runSync('openssl', [
        'verify', '-CAfile', '${dir.path}/c.pem', '${dir.path}/c.pem', //
      ]);
      expect('${verify.stdout}', contains('OK'));
    },
  );
}
