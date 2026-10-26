import 'dart:io';

import 'package:couchkit_remote/core/network/tv_client.dart';

class CastState {
  const CastState({
    required this.active,
    required this.title,
    required this.kind,
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.volume,
    required this.volumeMax,
  });

  factory CastState.fromJson(Json json) {
    int number(String key) => (json[key] as num?)?.toInt() ?? 0;
    return CastState(
      active: json['active'] == true,
      title: '${json['title'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      playing: json['playing'] == true,
      positionMs: number('pos'),
      durationMs: number('dur'),
      volume: number('vol'),
      volumeMax: number('volMax'),
    );
  }

  final bool active;
  final String title;
  final String kind;
  final bool playing;
  final int positionMs;
  final int durationMs;
  final int volume;
  final int volumeMax;
}

class CastService {
  CastService(this._client);

  final TvClient _client;

  Future<CastState> state() async {
    return CastState.fromJson(await _client.getJson('/api/state'));
  }

  Future<String> sendLink(String url) async {
    final json = await _client.getJson('/api/link', {'url': url});
    return '${json['msg'] ?? ''}';
  }

  Future<String> sendFile(
    File file, {
    String? mimeType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await file.length();
    final json = await _client.upload(
      '/api/upload',
      {'name': file.uri.pathSegments.last, 'type': mimeType},
      file.openRead(),
      length,
      onProgress: onProgress,
    );
    return '${json['msg'] ?? ''}';
  }

  Future<void> toggle() => _ctl('toggle');

  Future<void> seekBy(int seconds) => _ctl('seek', seconds);

  Future<void> seekTo(int seconds) => _ctl('to', seconds);

  Future<void> stop() => _ctl('stop');

  Future<void> volumeUp() =>
      _client.getJson('/api/ctl', {'cmd': 'vol', 'v': 'up'});

  Future<void> volumeDown() =>
      _client.getJson('/api/ctl', {'cmd': 'vol', 'v': 'down'});

  Future<void> mute() => _ctl('mute');

  Future<void> _ctl(String cmd, [int? value]) {
    return _client.getJson('/api/ctl', {
      'cmd': cmd,
      'v': value == null ? null : '$value',
    });
  }
}
