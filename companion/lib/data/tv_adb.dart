import 'dart:convert';

import 'package:couchkit_remote/data/adb/adb_connection.dart';
import 'package:couchkit_remote/data/adb/adb_key.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';

/// Chave ADB do celular (gerada uma vez) e abertura de sessoes na TV.
class TvAdb {
  TvAdb(this._store, {this.port = 5555});

  static const _keyName = 'adb_key';

  final KeyValueStore _store;
  final int port;

  Future<AdbKey> key() async {
    final saved = await _store.read(_keyName);
    if (saved != null) {
      try {
        return AdbKey.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      } on FormatException {
        // chave corrompida: gera outra (a TV pede nova autorizacao)
      }
    }
    final created = await AdbKey.generate();
    await _store.write(_keyName, jsonEncode(created.toJson()));
    return created;
  }

  /// Abre uma sessao ADB; lembre de fechar para liberar o adbd.
  Future<AdbConnection> open(
    String host, {
    void Function()? onWaitingApproval,
  }) async {
    return AdbConnection.open(
      host,
      await key(),
      port: port,
      onWaitingApproval: onWaitingApproval,
    );
  }
}
