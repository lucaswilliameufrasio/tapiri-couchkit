import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/models/cam_config.dart';
import 'package:couchkit_remote/data/services/cam_service.dart';

/// Configuracao do HomeCam: servidores, cameras, ordem e colunas.
/// Cada mudanca grava na TV na hora e recarrega a lista real.
class CamController extends ChangeNotifier {
  CamController(this._service, {String Function()? newId})
    : _newId =
          newId ??
          (() => DateTime.now().millisecondsSinceEpoch.toRadixString(36));

  final CamService _service;
  final String Function() _newId;

  CamSettings settings = const CamSettings();
  CamListing listing = const CamListing(cams: [], errors: {});
  bool loading = true;
  bool busy = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      settings = await _service.config();
      listing = await _service.cams();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String serverName(String id) {
    for (final server in settings.servers) {
      if (server.id == id) {
        return server.name;
      }
    }
    return id;
  }

  Future<void> saveServer(CamServerConfig server) async {
    final servers = <CamServerConfig>[];
    var replaced = false;
    for (final item in settings.servers) {
      if (item.id == server.id) {
        servers.add(server);
        replaced = true;
      } else {
        servers.add(item);
      }
    }
    if (!replaced) {
      servers.add(server);
    }
    await _save(settings.copyWith(servers: servers));
  }

  CamServerConfig newServer({
    required String name,
    required String url,
    String user = '',
    String pass = '',
  }) {
    return CamServerConfig(
      id: 's${_newId()}',
      name: name,
      url: url,
      user: user,
      pass: pass,
    );
  }

  Future<void> removeServer(String id) async {
    await _save(
      settings.copyWith(
        servers: [
          for (final s in settings.servers)
            if (s.id != id) s,
        ],
      ),
    );
  }

  Future<void> setCols(int cols) => _save(settings.copyWith(cols: cols));

  Future<void> reorder(int from, int to) async {
    final list = [...listing.cams];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    await _saveOrder(list);
  }

  Future<void> rename(CamEntry entry, String name) async {
    await _saveOrder([
      for (final item in listing.cams)
        if (item.key == entry.key) item.copyWith(name: name.trim()) else item,
    ]);
  }

  Future<void> toggleHidden(CamEntry entry) async {
    await _saveOrder([
      for (final item in listing.cams)
        if (item.key == entry.key)
          item.copyWith(hidden: !item.hidden)
        else
          item,
    ]);
  }

  /// [serverId] nulo = RTSP direto na TV (sem go2rtc).
  Future<void> addCamera({
    required String name,
    required String src,
    String? serverId,
  }) async {
    await _run(() async {
      if (serverId != null) {
        await _service.addToServer(serverId, name, src);
      } else {
        if (!RegExp(r'^rtsps?://.+', caseSensitive: false).hasMatch(src)) {
          throw const TvRequestException(
            'Sem go2rtc só dá para abrir RTSP. Para RTMP e outras fontes, '
            'escolha um servidor go2rtc.',
          );
        }
        final direct = [
          ...settings.direct,
          CamDirect(id: _newId(), name: name, url: src),
        ];
        settings = await _service.save(settings.copyWith(direct: direct));
      }
      listing = await _service.cams();
    });
  }

  Future<void> removeCamera(CamEntry entry) async {
    await _run(() async {
      if (entry.direct) {
        final id = entry.key.substring(2);
        settings = await _service.save(
          settings.copyWith(
            direct: [
              for (final d in settings.direct)
                if (d.id != id) d,
            ],
            cams: [
              for (final c in settings.cams)
                if (c.key != entry.key) c,
            ],
          ),
        );
      } else {
        await _service.removeFromServer(entry.serverId, entry.stream);
        settings = await _service.save(
          settings.copyWith(
            cams: [
              for (final c in settings.cams)
                if (c.key != entry.key) c,
            ],
          ),
        );
      }
      listing = await _service.cams();
    });
  }

  /// Guarda so o que difere do nome original (o resto acompanha o go2rtc).
  Future<void> _saveOrder(List<CamEntry> order) {
    return _save(
      settings.copyWith(
        cams: [
          for (final entry in order)
            CamEntry(
              key: entry.key,
              name: entry.name == entry.stream ? '' : entry.name,
              hidden: entry.hidden,
            ),
        ],
      ),
    );
  }

  Future<void> _save(CamSettings next) {
    return _run(() async {
      settings = await _service.save(next);
      listing = await _service.cams();
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    busy = true;
    notifyListeners();
    try {
      await body();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
