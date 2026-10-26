import 'dart:convert';
import 'dart:io';

import 'package:couchkit_remote/core/network/tv_client.dart';

class LauncherApp {
  const LauncherApp({required this.pkg, required this.label});

  final String pkg;
  final String label;
}

/// Personalizacao do launcher FireHome (tema, linhas, apps, papel de parede).
class FireHomeService {
  FireHomeService(this._client);

  final TvClient _client;

  Future<Json> config() => _client.getJson('/api/config');

  Future<void> save(Json config) async {
    final body = utf8.encode(jsonEncode(config));
    await _client.upload('/api/config', {}, Stream.value(body), body.length);
  }

  Future<List<LauncherApp>> apps() async {
    final raw = await _client.getAny('/api/apps');
    final result = <LauncherApp>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          result.add(
            LauncherApp(pkg: '${item['pkg']}', label: '${item['label']}'),
          );
        }
      }
    }
    return result;
  }

  Uri previewUri(int tick) => _client.uri('/api/preview', {'t': '$tick'});

  Uri iconUri(String pkg) => _client.uri('/api/icon', {'pkg': pkg});

  Future<String> uploadWallpaper(File file) async {
    final json = await _client.upload(
      '/api/wallpaper',
      {},
      file.openRead(),
      await file.length(),
    );
    return '${json['msg'] ?? ''}';
  }

  Future<void> clearWallpaper() async {
    await _client.getJson('/api/wallpaperclear');
  }

  Future<void> reset() async {
    await _client.getJson('/api/reset');
  }
}
