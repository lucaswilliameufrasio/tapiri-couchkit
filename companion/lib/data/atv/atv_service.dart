import 'dart:convert';

import 'package:couchkit_remote/data/atv/atv_identity.dart';
import 'package:couchkit_remote/data/atv/atv_pairing.dart';
import 'package:couchkit_remote/data/atv/atv_remote.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';

/// Certificado do celular (gerado uma vez, no cofre) e sessoes do Android TV
/// Remote v2. Cada TV precisa ser pareada uma vez com o codigo da tela.
class AtvService {
  AtvService(this._store, {this.pairPort = 6467, this.apiPort = 6466});

  static const storeKey = 'atv_identity';

  final KeyValueStore _store;
  final int pairPort;
  final int apiPort;
  AtvIdentity? _identity;

  Future<AtvIdentity> identity() async {
    final cached = _identity;
    if (cached != null) {
      return cached;
    }
    final saved = await _store.read(storeKey);
    if (saved != null) {
      try {
        return _identity = AtvIdentity.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      } on FormatException {
        // corrompido: gera outro (as TVs pedem novo pareamento)
      }
    }
    final created = await AtvIdentity.generate();
    await _store.write(storeKey, jsonEncode(created.toJson()));
    return _identity = created;
  }

  Future<AtvRemote> remote() async =>
      AtvRemote(await identity(), apiPort: apiPort);

  Future<AtvPairing> pairing() async =>
      AtvPairing(await identity(), pairPort: pairPort);
}
