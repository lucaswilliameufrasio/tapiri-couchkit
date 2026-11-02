import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/atv/atv_identity.dart';
import 'package:couchkit_remote/data/atv/atv_messages.dart';
import 'package:couchkit_remote/data/atv/protobuf.dart';

/// Contexto TLS com o certificado do celular (a TV nao tem CA: aceitamos o
/// certificado dela, que e o que o proprio app oficial faz).
SecurityContext atvContext(AtvIdentity identity) {
  return SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(identity.certPem.codeUnits)
    ..usePrivateKeyBytes(identity.keyPem.codeUnits);
}

/// Pareamento com uma Android TV: a TV mostra um codigo de 6 digitos
/// (hexadecimal) e o celular prova que o viu com um hash dos dois certificados.
class AtvPairing {
  AtvPairing(this.identity, {this.pairPort = 6467});

  final AtvIdentity identity;
  final int pairPort;

  static const _timeout = Duration(seconds: 10);

  SecureSocket? _socket;
  StreamSubscription<Uint8List>? _sub;
  final _frames = PbFrames();
  final _queue = <PbReader>[];
  Completer<void>? _wake;
  bool _closed = false;

  /// Abre a conexao e faz a troca inicial; ao retornar a TV mostra o codigo.
  Future<void> start(String host, {String clientName = 'Couchkit'}) async {
    try {
      _socket = await SecureSocket.connect(
        host,
        pairPort,
        context: atvContext(identity),
        onBadCertificate: (_) => true,
        timeout: _timeout,
      );
    } on Object catch (e) {
      throw AtvException('A TV não respondeu ao pareamento ($e)');
    }
    _sub = _socket!.listen(
      (data) {
        for (final frame in _frames.add(data)) {
          _queue.add(PbReader(frame));
        }
        _poke();
      },
      onDone: () {
        _closed = true;
        _poke();
      },
      onError: (Object _) {
        _closed = true;
        _poke();
      },
    );
    _socket!.add(Polo.pairingRequest(clientName));
    await _expect(11);
    _socket!.add(Polo.options());
    await _expect(20);
    _socket!.add(Polo.configuration());
    await _expect(31);
  }

  /// Confere o codigo digitado e envia o segredo. Lanca [AtvException] se a
  /// TV recusar (codigo errado).
  Future<void> finish(String code) async {
    final text = code.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(text)) {
      throw const AtvException('O código tem 6 caracteres (0-9 e A-F).');
    }
    final socket = _socket;
    final server = socket?.peerCertificate;
    if (socket == null || server == null) {
      throw const AtvException('Sem conexão com a TV.');
    }
    final (cn, ce) = AtvIdentity.publicNumbers(identity.certDer);
    final (sn, se) = AtvIdentity.publicNumbers(server.der);
    final hash = secretHash(cn, ce, sn, se, text.substring(2));
    final expected = int.parse(text.substring(0, 2), radix: 16);
    if (hash[0] != expected) {
      throw const AtvException('Código incorreto. Confira o que a TV mostra.');
    }
    socket.add(Polo.secret(hash));
    await _expect(41, badSecret: 'A TV recusou o código.');
  }

  /// sha256(modulo cliente, expoente cliente, modulo TV, expoente TV, codigo[2:]).
  static Uint8List secretHash(
    BigInt clientModulus,
    BigInt clientExponent,
    BigInt serverModulus,
    BigInt serverExponent,
    String codeTail,
  ) {
    List<int> hex(String text) {
      final even = text.length.isOdd ? '0$text' : text;
      return [
        for (var i = 0; i < even.length; i += 2)
          int.parse(even.substring(i, i + 2), radix: 16),
      ];
    }

    String big(BigInt v) => v.toRadixString(16).toUpperCase();
    final digest = SHA256Digest();
    for (final part in [
      hex(big(clientModulus)),
      hex('0${big(clientExponent)}'),
      hex(big(serverModulus)),
      hex('0${big(serverExponent)}'),
      hex(codeTail),
    ]) {
      digest.update(Uint8List.fromList(part), 0, part.length);
    }
    final out = Uint8List(32);
    digest.doFinal(out, 0);
    return out;
  }

  void _poke() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) {
      wake.complete();
    }
  }

  Future<void> _expect(int field, {String? badSecret}) async {
    final deadline = DateTime.now().add(_timeout);
    while (_queue.isEmpty) {
      if (_closed) {
        throw const AtvException('A TV encerrou o pareamento.');
      }
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        throw const AtvException('A TV demorou demais para responder.');
      }
      final wake = _wake = Completer<void>();
      await wake.future.timeout(left, onTimeout: () {});
    }
    final message = _queue.removeAt(0);
    if (message.uint(2) != Polo.statusOk) {
      throw AtvException(badSecret ?? 'A TV recusou o pareamento.');
    }
    if (!message.has(field)) {
      throw AtvException('Resposta inesperada da TV (esperava $field).');
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    _socket?.destroy();
    _socket = null;
  }
}
