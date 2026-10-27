import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/adb/adb_key.dart';
import 'package:couchkit_remote/data/adb/adb_message.dart';

/// Cliente ADB minimo sobre TCP: autentica com a chave do celular, roda
/// comandos de shell e envia arquivos (sync). O adbd da Fire OS aceita um
/// cliente por vez, entao abra, use e feche.
class AdbConnection {
  AdbConnection._(this._socket) {
    _socket.listen(
      _onData,
      onDone: _onDone,
      onError: (Object _) => _onDone(),
      cancelOnError: true,
    );
  }

  static const _version = 0x01000000;
  static const _ourMaxData = 256 * 1024;
  static const _localId = 1;
  static const _syncChunk = 64 * 1024;

  final Socket _socket;
  Uint8List _buffer = Uint8List(0);
  Completer<void>? _wake;
  bool _closed = false;
  int _maxData = _ourMaxData;
  final _pendingWrites = <Uint8List>[];

  /// Conecta e autentica. [onWaitingApproval] avisa quando a TV esta
  /// mostrando "Permitir depuracao USB?" (1a vez com esta chave).
  static Future<AdbConnection> open(
    String host,
    AdbKey key, {
    int port = 5555,
    Duration connectTimeout = const Duration(seconds: 5),
    Duration authTimeout = const Duration(seconds: 90),
    void Function()? onWaitingApproval,
  }) async {
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: connectTimeout);
    } on SocketException {
      throw const AdbException(
        'Não achei o ADB da TV. Ligue a Depuração ADB em Configurações → '
        'Meu Fire TV → Opções do desenvolvedor.',
      );
    } on TimeoutException {
      throw const AdbException('A TV não respondeu na porta 5555.');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final connection = AdbConnection._(socket);
    try {
      await connection._handshake(key, authTimeout, onWaitingApproval);
    } catch (_) {
      await connection.close();
      rethrow;
    }
    return connection;
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _socket.close();
    } on Object {
      // ja fechado
    }
  }

  /// Roda um comando e devolve a saida (stdout+stderr), sem os \r do pty.
  Future<String> shell(
    String command, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final remoteId = await _openStream('shell:$command');
    final out = BytesBuilder();
    while (true) {
      final message = await _readMessage(timeout);
      if (message.command == AdbCommand.write) {
        out.add(message.data);
        await _send(AdbCommand.okay, _localId, remoteId);
      } else if (message.command == AdbCommand.close) {
        break;
      }
    }
    return utf8
        .decode(out.takeBytes(), allowMalformed: true)
        .replaceAll('\r\n', '\n')
        .trim();
  }

  /// Envia [bytes] para [remotePath] (protocolo sync, seguro para binario).
  Future<void> push(
    Uint8List bytes,
    String remotePath, {
    int mode = 0x1a4,
    void Function(int sent, int total)? onProgress,
  }) async {
    final remoteId = await _openStream('sync:');
    final target = utf8.encode('$remotePath,$mode');
    await _syncWrite(remoteId, _syncPacket('SEND', target));
    var sent = 0;
    while (sent < bytes.length) {
      final end = sent + _syncChunk < bytes.length
          ? sent + _syncChunk
          : bytes.length;
      await _syncWrite(
        remoteId,
        _syncPacket('DATA', Uint8List.sublistView(bytes, sent, end)),
      );
      sent = end;
      onProgress?.call(sent, bytes.length);
    }
    final mtime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final done = ByteData(8)..setUint32(4, mtime, Endian.little);
    done.buffer.asUint8List().setRange(0, 4, ascii.encode('DONE'));
    await _syncWrite(remoteId, done.buffer.asUint8List());

    final reply = await _readSyncReply(remoteId);
    if (reply.length < 4 || ascii.decode(reply.sublist(0, 4)) != 'OKAY') {
      final detail = reply.length > 8 ? utf8.decode(reply.sublist(8)) : '';
      throw AdbException('A TV recusou o arquivo: $detail');
    }
    await _send(AdbCommand.close, _localId, remoteId);
    // o adbd responde com CLSE: sem consumir, o proximo OPEN le essa sobra
    var message = await _readMessage(const Duration(seconds: 15));
    while (message.command != AdbCommand.close) {
      message = await _readMessage(const Duration(seconds: 15));
    }
  }

  Uint8List _syncPacket(String id, List<int> payload) {
    final packet = ByteData(8 + payload.length);
    packet.buffer.asUint8List().setRange(0, 4, ascii.encode(id));
    packet.setUint32(4, payload.length, Endian.little);
    packet.buffer.asUint8List().setRange(8, 8 + payload.length, payload);
    return packet.buffer.asUint8List();
  }

  Future<void> _syncWrite(int remoteId, Uint8List data) async {
    await _send(AdbCommand.write, _localId, remoteId, data);
    await _expectOkay();
  }

  Future<Uint8List> _readSyncReply(int remoteId) async {
    while (true) {
      final message = await _readMessage(const Duration(seconds: 30));
      if (message.command == AdbCommand.write) {
        await _send(AdbCommand.okay, _localId, remoteId);
        return message.data;
      }
      if (message.command == AdbCommand.close) {
        throw const AdbException('A TV fechou a transferência.');
      }
    }
  }

  Future<void> _expectOkay() async {
    while (true) {
      final message = await _readMessage(const Duration(seconds: 30));
      if (message.command == AdbCommand.okay) {
        return;
      }
      if (message.command == AdbCommand.write) {
        // resposta antecipada (ex.: FAIL do sync); guarda e confirma
        _pendingWrites.add(message.data);
        await _send(AdbCommand.okay, _localId, message.arg0);
      } else if (message.command == AdbCommand.close) {
        throw const AdbException('A TV fechou a transferência.');
      }
    }
  }

  Future<int> _openStream(String service) async {
    await _send(
      AdbCommand.open,
      _localId,
      0,
      Uint8List.fromList([...utf8.encode(service), 0]),
    );
    final reply = await _readMessage(const Duration(seconds: 15));
    if (reply.command != AdbCommand.okay) {
      throw AdbException('A TV recusou "$service".');
    }
    return reply.arg0;
  }

  Future<void> _handshake(
    AdbKey key,
    Duration authTimeout,
    void Function()? onWaitingApproval,
  ) async {
    await _send(
      AdbCommand.connect,
      _version,
      _ourMaxData,
      Uint8List.fromList([...utf8.encode('host::couchkit'), 0]),
    );
    var message = await _readMessage(const Duration(seconds: 10));
    var signed = false;
    var keySent = false;
    while (message.command == AdbCommand.auth) {
      if (message.arg0 != AdbAuth.token) {
        throw const AdbException('Autenticação inesperada do adbd.');
      }
      if (keySent) {
        throw const AdbException('A TV negou a autorização.');
      }
      if (!signed) {
        await _send(
          AdbCommand.auth,
          AdbAuth.signature,
          0,
          key.sign(message.data),
        );
        signed = true;
      } else {
        onWaitingApproval?.call();
        await _send(AdbCommand.auth, AdbAuth.publicKey, 0, key.publicKeyLine());
        keySent = true;
      }
      message = await _readMessage(
        keySent ? authTimeout : const Duration(seconds: 10),
      );
    }
    if (message.command != AdbCommand.connect) {
      throw const AdbException('O adbd não aceitou a conexão.');
    }
    if (message.arg1 > 0 && message.arg1 < _maxData) {
      _maxData = message.arg1;
    }
  }

  Future<void> _send(int command, int arg0, int arg1, [Uint8List? data]) async {
    if (_closed) {
      throw const AdbException('Conexão com a TV fechada.');
    }
    _socket.add(AdbMessage(command, arg0, arg1, data ?? Uint8List(0)).encode());
    await _socket.flush();
  }

  void _onData(List<int> chunk) {
    final next = Uint8List(_buffer.length + chunk.length);
    next.setRange(0, _buffer.length, _buffer);
    next.setRange(_buffer.length, next.length, chunk);
    _buffer = next;
    _wake?.complete();
    _wake = null;
  }

  void _onDone() {
    _closed = true;
    _wake?.complete();
    _wake = null;
  }

  Future<Uint8List> _take(int count, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < count) {
      if (_closed) {
        throw const AdbException(
          'A TV fechou a conexão. Se o ADB do PC estiver conectado, '
          'desconecte-o (o adbd aceita um cliente por vez).',
        );
      }
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        throw const AdbException('A TV demorou demais para responder.');
      }
      final wake = _wake = Completer<void>();
      await wake.future.timeout(left, onTimeout: () {});
    }
    final out = Uint8List.sublistView(_buffer, 0, count);
    _buffer = Uint8List.sublistView(_buffer, count);
    return Uint8List.fromList(out);
  }

  Future<AdbMessage> _readMessage(Duration timeout) async {
    final header = ByteData.sublistView(
      await _take(AdbMessage.headerLength, timeout),
    );
    final length = header.getUint32(12, Endian.little);
    if (length > _ourMaxData) {
      throw const AdbException('Mensagem inválida do adbd.');
    }
    final data = length == 0 ? Uint8List(0) : await _take(length, timeout);
    return AdbMessage(
      header.getUint32(0, Endian.little),
      header.getUint32(4, Endian.little),
      header.getUint32(8, Endian.little),
      data,
    );
  }
}
