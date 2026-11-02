import 'dart:io';
import 'dart:typed_data';

import 'package:couchkit_remote/data/atv/atv_identity.dart';
import 'package:couchkit_remote/data/atv/atv_messages.dart';
import 'package:couchkit_remote/data/atv/atv_pairing.dart';
import 'package:couchkit_remote/data/atv/protobuf.dart';

Uint8List hex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Tira o varint de tamanho da frente (todas as mensagens daqui tem < 128 B).
String body(Uint8List frame) => toHex(frame.sublist(1));

/// TV falsa: servidor TLS que fala o pareamento e o controle.
class FakeAtv {
  FakeAtv(this.identity);

  final AtvIdentity identity;
  late SecureServerSocket pair;
  late SecureServerSocket api;
  static const tail = '3A9C';

  /// Codigo que esta TV mostraria para [phone]: o 1o byte e o do hash.
  String codeFor(AtvIdentity phone) {
    final (cn, ce) = AtvIdentity.publicNumbers(phone.certDer);
    final (sn, se) = AtvIdentity.publicNumbers(identity.certDer);
    final hash = AtvPairing.secretHash(cn, ce, sn, se, tail);
    return hash[0].toRadixString(16).padLeft(2, '0').toUpperCase() + tail;
  }

  Uint8List? pairedCert;
  final received = <PbReader>[];
  final pairingSteps = <int>[];
  bool pairedOk = false;

  /// A TV de verdade aceita qualquer certificado de cliente no TLS (quem
  /// decide e o app, depois do pareamento). O Dart so aceita se confiar nele.
  static Future<FakeAtv> start(
    int pairPort,
    int apiPort,
    AtvIdentity phone,
  ) async {
    final tv = FakeAtv(await AtvIdentity.generate(name: 'tv'));
    final context = atvContext(tv.identity)
      ..setTrustedCertificatesBytes(phone.certPem.codeUnits);
    tv.pair = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      pairPort,
      context,
      requestClientCertificate: true,
    );
    tv.api = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      apiPort,
      context,
      requestClientCertificate: true,
    );
    tv.pair.listen(tv._onPair);
    tv.api.listen(tv._onApi);
    return tv;
  }

  Future<void> stop() async {
    await pair.close();
    await api.close();
  }

  void _onPair(SecureSocket socket) {
    final frames = PbFrames();
    socket.listen((data) {
      for (final frame in frames.add(data)) {
        final msg = PbReader(frame);
        if (msg.has(10)) {
          pairingSteps.add(10);
          socket.add(Polo.reply(11, body: PbWriter()..string(1, 'tv')));
        } else if (msg.has(20)) {
          pairingSteps.add(20);
          socket.add(Polo.reply(20));
        } else if (msg.has(30)) {
          pairingSteps.add(30);
          socket.add(Polo.reply(31));
        } else if (msg.has(40)) {
          pairingSteps.add(40);
          final client = socket.peerCertificate!.der;
          final (cn, ce) = AtvIdentity.publicNumbers(client);
          final (sn, se) = AtvIdentity.publicNumbers(identity.certDer);
          final want = AtvPairing.secretHash(cn, ce, sn, se, tail);
          final got = msg.message(40)!.bytes(1)!;
          if (toHex(got) == toHex(want)) {
            pairedCert = client;
            pairedOk = true;
            socket.add(Polo.reply(41, body: PbWriter()..bytes(1, want)));
          } else {
            socket.add(Polo.reply(0, status: 402));
          }
        }
      }
    });
  }

  void _onApi(SecureSocket socket) {
    final known = pairedCert;
    final client = socket.peerCertificate?.der;
    if (known == null || client == null || toHex(known) != toHex(client)) {
      socket.destroy();
      return;
    }
    final frames = PbFrames();
    var step = 0;
    socket.add(
      (PbWriter()..message(
            1,
            PbWriter()
              ..uint(1, 2 | 32 | 64 | 512 | 4 | 1)
              ..message(
                2,
                PbWriter()
                  ..string(1, 'Modelo')
                  ..string(2, 'Marca'),
              ),
          ))
          .toFrame(),
    );
    socket.listen((data) {
      for (final frame in frames.add(data)) {
        final msg = PbReader(frame);
        received.add(msg);
        if (step == 0 && msg.has(1)) {
          step = 1;
          socket.add(
            (PbWriter()..message(2, PbWriter()..uint(1, 0))).toFrame(),
          );
        } else if (step == 1 && msg.has(2)) {
          step = 2;
          socket.add(
            (PbWriter()..message(
                  21,
                  PbWriter()
                    ..uint(1, 4)
                    ..uint(2, 9),
                ))
                .toFrame(),
          );
          socket.add(
            (PbWriter()..message(40, PbWriter()..uint(1, 1))).toFrame(),
          );
          socket.add(
            (PbWriter()..message(
                  8,
                  PbWriter()
                    ..uint(1, 7)
                    ..uint(2, 1),
                ))
                .toFrame(),
          );
        }
      }
    });
  }
}
