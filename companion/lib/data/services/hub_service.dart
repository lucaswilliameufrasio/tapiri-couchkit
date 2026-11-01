import 'dart:io';

import 'package:couchkit_remote/core/network/tv_client.dart';

class DeviceInfo {
  const DeviceInfo({
    required this.model,
    required this.android,
    required this.ramTotalMb,
    required this.ramFreeMb,
    required this.diskTotalMb,
    required this.diskFreeMb,
    required this.uptimeSeconds,
  });

  factory DeviceInfo.fromJson(Json json) {
    int number(String key) => (json[key] as num?)?.toInt() ?? 0;
    return DeviceInfo(
      model: '${json['model'] ?? ''}',
      android: '${json['android'] ?? ''}',
      ramTotalMb: number('ramTotal'),
      ramFreeMb: number('ramFree'),
      diskTotalMb: number('diskTotal'),
      diskFreeMb: number('diskFree'),
      uptimeSeconds: number('uptime'),
    );
  }

  final String model;
  final String android;
  final int ramTotalMb;
  final int ramFreeMb;
  final int diskTotalMb;
  final int diskFreeMb;
  final int uptimeSeconds;
}

class InstalledApp {
  const InstalledApp({
    required this.pkg,
    required this.label,
    required this.system,
    required this.launchable,
    required this.version,
  });

  factory InstalledApp.fromJson(Map<String, dynamic> json) {
    return InstalledApp(
      pkg: '${json['pkg']}',
      label: '${json['label']}',
      system: json['sys'] == true,
      launchable: json['launch'] == true,
      version: '${json['ver'] ?? ''}',
    );
  }

  final String pkg;
  final String label;
  final bool system;
  final bool launchable;
  final String version;
}

class HubService {
  HubService(this._client);

  final TvClient _client;

  Future<DeviceInfo> info() async {
    return DeviceInfo.fromJson(await _client.getJson('/api/info'));
  }

  Future<List<InstalledApp>> apps() async {
    final raw = await _client.getAny('/api/apps');
    final result = <InstalledApp>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          result.add(InstalledApp.fromJson(item));
        }
      }
    }
    return result;
  }

  Uri iconUri(String pkg) => _client.uri('/api/icon', {'pkg': pkg});

  Future<String> launch(String pkg) => _message('launch', pkg);

  Future<String> stop(String pkg) => _message('stop', pkg);

  Future<String> uninstall(String pkg) => _message('uninstall', pkg);

  Future<String> details(String pkg) => _message('details', pkg);

  Future<void> openUrl(String url) async {
    await _client.getJson('/api/openurl', {'url': url});
  }

  Future<void> clean() async {
    await _client.getJson('/api/clean');
  }

  Future<String> installApk(
    File file, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await file.length();
    final name = file.uri.pathSegments.last;
    final json = await _client.upload(
      '/api/install',
      {'name': name},
      file.openRead(),
      length,
      onProgress: onProgress,
    );
    return '${json['msg'] ?? ''}';
  }

  Future<String> _message(String cmd, String pkg) async {
    final json = await _client.getJson('/api/$cmd', {'pkg': pkg});
    return '${json['msg'] ?? ''}';
  }
}
