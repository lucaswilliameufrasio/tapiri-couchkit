import 'dart:convert';
import 'dart:typed_data';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/backup/backup_crypto.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/cam_config.dart';
import 'package:couchkit_remote/data/models/panel.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/panels_repository.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/tv_repository.dart';
import 'package:couchkit_remote/data/tv_service_factory.dart';

/// O que a restauracao fez.
class RestoreReport {
  const RestoreReport({
    required this.tvs,
    required this.panels,
    required this.adbKey,
    required this.pushed,
    required this.failed,
  });

  final int tvs;
  final int panels;
  final bool adbKey;

  /// Configuracoes reenviadas as TVs ("HomeCam · 192.168.0.5").
  final List<String> pushed;

  /// Configuracoes que nao chegaram (TV desligada, token mudou...).
  final List<String> failed;
}

/// Backup criptografado de tudo que o Couchkit guarda: TVs e tokens, nomes,
/// paineis, chave ADB e as configuracoes do HomeCam e do FireHome em cada TV.
class BackupService {
  BackupService(
    this._store,
    this._tvs,
    this._panels,
    this._services, {
    this.crypto = const BackupCrypto(),
  });

  static const _adbKey = 'adb_key';

  final KeyValueStore _store;
  final TvRepository _tvs;
  final PanelsRepository _panels;
  final TvServiceFactory _services;
  final BackupCrypto crypto;

  Future<Uint8List> export(String password) async {
    final endpoints = await _tvs.load();
    final homecam = <String, Object>{};
    final firehome = <String, Object>{};
    await Future.wait([
      for (final e in endpoints)
        if (e.kind == AppKind.homecam)
          _try(() async {
            homecam[e.host] = (await _services.cam(e).config()).toJson();
          }),
      for (final e in endpoints)
        if (e.kind == AppKind.firehome)
          _try(() async {
            firehome[e.host] = await _services.firehome(e).config();
          }),
    ]);
    final payload = {
      'v': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'endpoints': [for (final e in endpoints) e.toJson()],
      'tvNames': await _tvs.loadNames(),
      'selectedHost': await _tvs.selectedHost(),
      'panels': [for (final p in await _panels.load()) p.toJson()],
      'adbKey': await _store.read(_adbKey),
      'homecam': homecam,
      'firehome': firehome,
    };
    return crypto.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      password,
    );
  }

  Future<RestoreReport> restore(Uint8List file, String password) async {
    final plain = await crypto.decrypt(file, password);
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } on Object {
      throw const BackupException('O conteúdo do backup está ilegível.');
    }

    final endpoints = <TvEndpoint>[];
    for (final item in _list(payload['endpoints'])) {
      final endpoint = TvEndpoint.tryFromJson(item);
      if (endpoint != null) {
        endpoints.add(endpoint);
        await _tvs.save(endpoint);
      }
    }
    final names = payload['tvNames'];
    if (names is Map) {
      for (final entry in names.entries) {
        await _tvs.renameHost('${entry.key}', '${entry.value}');
      }
    }
    final selected = payload['selectedHost'];
    if (selected is String && selected.isNotEmpty) {
      await _tvs.selectHost(selected);
    }
    var panels = 0;
    for (final item in _list(payload['panels'])) {
      final panel = Panel.tryFromJson(item);
      if (panel != null) {
        await _panels.save(panel);
        panels++;
      }
    }
    final key = payload['adbKey'];
    final hasKey = key is String && key.isNotEmpty;
    if (hasKey) {
      await _store.write(_adbKey, key);
    }

    final pushed = <String>[];
    final failed = <String>[];
    Future<void> push(
      String label,
      AppKind kind,
      Object? configs,
      Future<void> Function(TvEndpoint endpoint, Map<String, dynamic> config)
      send,
    ) async {
      if (configs is! Map) {
        return;
      }
      for (final entry in configs.entries) {
        final host = '${entry.key}';
        final value = entry.value;
        TvEndpoint? endpoint;
        for (final e in endpoints) {
          if (e.kind == kind && e.host == host) {
            endpoint = e;
          }
        }
        final name = '$label · $host';
        if (endpoint == null || value is! Map<String, dynamic>) {
          failed.add(name);
          continue;
        }
        try {
          await send(endpoint, value);
          pushed.add(name);
        } on Object {
          failed.add(name);
        }
      }
    }

    await push('HomeCam', AppKind.homecam, payload['homecam'], (
      e,
      config,
    ) async {
      await _services.cam(e).save(CamSettings.fromJson(config));
    });
    await push('FireHome', AppKind.firehome, payload['firehome'], (e, config) {
      return _services.firehome(e).save(config);
    });

    return RestoreReport(
      tvs: endpoints.map((e) => e.host).toSet().length,
      panels: panels,
      adbKey: hasKey,
      pushed: pushed,
      failed: failed,
    );
  }

  List<Object?> _list(Object? raw) => raw is List ? raw : const [];

  Future<void> _try(Future<void> Function() body) async {
    try {
      await body();
    } on Object {
      // TV desligada: fica fora do backup (o resto continua valendo)
    }
  }
}
