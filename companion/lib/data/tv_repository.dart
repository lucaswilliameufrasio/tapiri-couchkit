import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/core/logging/logger.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';

/// Lista de apps pareados, identificacao do app por porta e reencontro
/// da porta quando o app da TV reinicia em outra.
class TvRepository {
  TvRepository(this._store, {Dio? dio, AppLogger? logger})
    : _logger = logger ?? const AppLogger('TvRepository'),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(milliseconds: 900),
              receiveTimeout: const Duration(milliseconds: 1500),
              validateStatus: (_) => true,
              responseType: ResponseType.plain,
            ),
          );

  static const _key = 'endpoints';

  final KeyValueStore _store;
  final Dio _dio;
  final AppLogger _logger;

  Future<List<TvEndpoint>> load() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    final result = <TvEndpoint>[];
    if (decoded is List) {
      for (final item in decoded) {
        final endpoint = TvEndpoint.tryFromJson(item);
        if (endpoint != null) {
          result.add(endpoint);
        }
      }
    }
    return result;
  }

  Future<void> save(TvEndpoint endpoint) async {
    final all = await load();
    final next = <TvEndpoint>[];
    var replaced = false;
    for (final item in all) {
      if (item.id == endpoint.id) {
        next.add(endpoint);
        replaced = true;
      } else {
        next.add(item);
      }
    }
    if (!replaced) {
      next.add(endpoint);
    }
    await _persist(next);
  }

  Future<void> remove(String id) async {
    final all = await load();
    final next = <TvEndpoint>[];
    for (final item in all) {
      if (item.id != id) {
        next.add(item);
      }
    }
    await _persist(next);
  }

  Future<void> _persist(List<TvEndpoint> items) {
    final json = <Object>[];
    for (final item in items) {
      json.add(item.toJson());
    }
    return _store.write(_key, jsonEncode(json));
  }

  /// Descobre qual app responde em host:port pelo <title> da pagina.
  Future<AppKind?> identify(String host, int port) async {
    try {
      final response = await _dio.getUri<String>(
        Uri(scheme: 'http', host: host, port: port, path: '/'),
      );
      if (response.statusCode != 200) {
        return null;
      }
      return AppKind.fromHtml(response.data ?? '');
    } on DioException {
      return null;
    }
  }

  /// Pareia a partir da URL/QR da TV e guarda o endpoint.
  Future<TvEndpoint> pair(String rawUrl) async {
    final url = ConnectionUrl.parse(rawUrl);
    final kind = await identify(url.host, url.port);
    if (kind == null) {
      throw const TvUnreachableException(
        'Nenhum app do couchkit respondeu nesse endereço',
      );
    }
    final endpoint = TvEndpoint(
      kind: kind,
      host: url.host,
      port: url.port,
      token: url.token,
    );
    await save(endpoint);
    return endpoint;
  }

  Future<bool> isOnline(TvEndpoint endpoint) async {
    final kind = await identify(endpoint.host, endpoint.port);
    return kind == endpoint.kind;
  }

  /// Procura o app na faixa de portas dele (o app escolhe a porta sozinho).
  Future<TvEndpoint?> relocate(TvEndpoint endpoint) async {
    final kind = endpoint.kind;
    final probes = <Future<int?>>[];
    for (var port = kind.portStart; port <= kind.portEnd; port++) {
      probes.add(_probe(endpoint.host, port, kind));
    }
    final found = await Future.wait(probes);
    for (final port in found) {
      if (port != null) {
        final moved = endpoint.withPort(port);
        await save(moved);
        _logger.info('porta reencontrada', {'app': kind.name, 'port': port});
        return moved;
      }
    }
    return null;
  }

  Future<int?> _probe(String host, int port, AppKind kind) async {
    final found = await identify(host, port);
    return found == kind ? port : null;
  }
}
