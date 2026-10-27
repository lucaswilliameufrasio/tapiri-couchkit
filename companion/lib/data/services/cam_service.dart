import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/core/network/tv_client.dart';
import 'package:couchkit_remote/data/models/cam_config.dart';

class CamService {
  CamService(this._client);

  final TvClient _client;

  Future<CamSettings> config() async {
    return CamSettings.fromJson(await _client.getJson('/api/cfg'));
  }

  /// Grava a configuracao inteira; devolve o que a TV normalizou e guardou.
  Future<CamSettings> save(CamSettings settings) async {
    return CamSettings.fromJson(
      await _client.postJson('/api/cfg', settings.toJson()),
    );
  }

  /// Cameras na ordem que a TV usa (inclui ocultas) e erros por servidor.
  Future<CamListing> cams() async {
    final json = await _client.getJson('/api/cams');
    final cams = <CamEntry>[];
    final raw = json['cams'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          cams.add(CamEntry.fromJson(item));
        }
      }
    }
    final errors = <String, String>{};
    final rawErrors = json['errors'];
    if (rawErrors is List) {
      for (final item in rawErrors) {
        if (item is Map<String, dynamic>) {
          errors['${item['server']}'] = '${item['error']}';
        }
      }
    }
    return CamListing(cams: cams, errors: errors);
  }

  /// Cadastra uma camera (RTSP, RTMP, ...) no go2rtc do servidor [server].
  Future<void> addToServer(String server, String name, String src) async {
    await _check(
      await _client.postJson('/api/add', {
        'server': server,
        'name': name,
        'src': src,
      }),
    );
  }

  Future<void> removeFromServer(String server, String name) async {
    await _check(
      await _client.postJson('/api/remove', {'server': server, 'name': name}),
    );
  }

  Future<void> _check(Json json) async {
    if (json['ok'] != true) {
      throw TvRequestException('${json['error'] ?? 'A TV recusou'}');
    }
  }
}
