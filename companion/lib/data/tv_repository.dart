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
  static const _selectedKey = 'selected_host';
  static const _namesKey = 'tv_names';

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

  /// Remove todos os apps de uma TV (e o nome dela).
  Future<void> removeHost(String host) async {
    final all = await load();
    final next = <TvEndpoint>[];
    for (final item in all) {
      if (item.host != host) {
        next.add(item);
      }
    }
    await _persist(next);
    final names = await loadNames();
    if (names.remove(host) != null) {
      await _store.write(_namesKey, jsonEncode(names));
    }
    if (await selectedHost() == host) {
      await _store.delete(_selectedKey);
    }
  }

  Future<String?> selectedHost() => _store.read(_selectedKey);

  Future<void> selectHost(String host) => _store.write(_selectedKey, host);

  /// Nomes dados pelo usuario as TVs (host -> nome).
  Future<Map<String, String>> loadNames() async {
    final raw = await _store.read(_namesKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    final decoded = jsonDecode(raw);
    final result = <String, String>{};
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        if (entry.key is String && entry.value is String) {
          result[entry.key as String] = entry.value as String;
        }
      }
    }
    return result;
  }

  Future<void> renameHost(String host, String name) async {
    final names = await loadNames();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      names.remove(host);
    } else {
      names[host] = trimmed;
    }
    await _store.write(_namesKey, jsonEncode(names));
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

  /// Token do StickHub ja pareado nesse host, se houver.
  Future<String?> tokenOf(String host) async {
    for (final endpoint in await load()) {
      if (endpoint.host == host && endpoint.kind == AppKind.stickhub) {
        return endpoint.token;
      }
    }
    return null;
  }

  /// Cadastra uma TV configurada pelo ADB: espera os apps subirem e guarda
  /// os que aceitam [token]. Devolve quantos achou (0 = nenhum respondeu).
  Future<int> adopt(
    String host,
    String token, {
    int attempts = 15,
    Duration wait = const Duration(seconds: 2),
    Map<AppKind, (int, int)>? ranges,
  }) async {
    for (var i = 0; i < attempts; i++) {
      final found = await discover(host, token, ranges: ranges);
      if (found.any((e) => e.kind == AppKind.stickhub)) {
        return found.length;
      }
      await Future<void>.delayed(wait);
    }
    return 0;
  }

  /// Procura, no mesmo host, os outros apps da TV que aceitam este token.
  /// Os apps compartilham o token do StickHub, entao um pareamento basta.
  /// [ranges] existe para os testes usarem portas menores.
  Future<List<TvEndpoint>> discover(
    String host,
    String token, {
    Map<AppKind, (int, int)>? ranges,
  }) async {
    final probes = <Future<TvEndpoint?>>[];
    for (final kind in AppKind.values) {
      final (start, end) = ranges?[kind] ?? (kind.portStart, kind.portEnd);
      for (var port = start; port <= end; port++) {
        probes.add(_probeWithToken(host, port, kind, token));
      }
    }
    final found = <TvEndpoint>[];
    for (final endpoint in await Future.wait(probes)) {
      if (endpoint != null) {
        await save(endpoint);
        found.add(endpoint);
      }
    }
    _logger.info('apps descobertos', {'host': host, 'count': found.length});
    return found;
  }

  Future<TvEndpoint?> _probeWithToken(
    String host,
    int port,
    AppKind kind,
    String token,
  ) async {
    if (await identify(host, port) != kind) {
      return null;
    }
    final endpoint = TvEndpoint(
      kind: kind,
      host: host,
      port: port,
      token: token,
    );
    return await _acceptsToken(endpoint) ? endpoint : null;
  }

  /// O app responde 403 a token errado e qualquer outra coisa a token certo.
  Future<bool> _acceptsToken(TvEndpoint endpoint) async {
    try {
      final response = await _dio.getUri<String>(
        endpoint.baseUri.replace(
          path: '/api/ping',
          queryParameters: {'k': endpoint.token},
        ),
      );
      return response.statusCode != null && response.statusCode != 403;
    } on DioException {
      return false;
    }
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
