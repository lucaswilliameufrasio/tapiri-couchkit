import 'package:couchkit_remote/core/network/tv_client.dart';

class CamConfig {
  const CamConfig({required this.url, required this.ok, required this.cams});

  final String url;
  final bool ok;
  final List<String> cams;
}

class CamService {
  CamService(this._client);

  final TvClient _client;

  Future<CamConfig> get() async => _parse(await _client.getJson('/api/get'));

  Future<CamConfig> setUrl(String url) async {
    return _parse(await _client.getJson('/api/set', {'u': url}));
  }

  CamConfig _parse(Json json) {
    final cams = <String>[];
    final raw = json['cams'];
    if (raw is List) {
      for (final item in raw) {
        cams.add('$item');
      }
    }
    return CamConfig(
      url: '${json['url'] ?? ''}',
      ok: json['ok'] == true,
      cams: cams,
    );
  }
}
