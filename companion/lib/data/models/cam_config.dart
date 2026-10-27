/// Servidor go2rtc que a TV consulta (com autenticacao basica opcional).
class CamServerConfig {
  const CamServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.user = '',
    this.pass = '',
  });

  factory CamServerConfig.fromJson(Map<String, dynamic> json) {
    return CamServerConfig(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      url: '${json['url'] ?? ''}',
      user: '${json['user'] ?? ''}',
      pass: '${json['pass'] ?? ''}',
    );
  }

  final String id;
  final String name;
  final String url;
  final String user;
  final String pass;

  bool get hasAuth => user.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'user': user,
    'pass': pass,
  };
}

/// Camera RTSP que a TV abre direto, sem go2rtc.
class CamDirect {
  const CamDirect({required this.id, required this.name, required this.url});

  factory CamDirect.fromJson(Map<String, dynamic> json) {
    return CamDirect(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      url: '${json['url'] ?? ''}',
    );
  }

  final String id;
  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};
}

/// Posicao, apelido e visibilidade de uma camera. A ordem da lista vale.
class CamEntry {
  const CamEntry({
    required this.key,
    required this.name,
    this.hidden = false,
    this.direct = false,
    this.stream = '',
  });

  factory CamEntry.fromJson(Map<String, dynamic> json) {
    return CamEntry(
      key: '${json['key'] ?? ''}',
      name: '${json['name'] ?? ''}',
      hidden: json['hidden'] == true,
      direct: json['direct'] == true,
      stream: '${json['stream'] ?? ''}',
    );
  }

  final String key;
  final String name;
  final bool hidden;
  final bool direct;
  final String stream;

  /// "idDoServidor" de uma camera go2rtc ("" se for RTSP direto).
  String get serverId {
    final slash = key.indexOf('/');
    return direct || slash < 0 ? '' : key.substring(0, slash);
  }

  CamEntry copyWith({String? name, bool? hidden}) {
    return CamEntry(
      key: key,
      name: name ?? this.name,
      hidden: hidden ?? this.hidden,
      direct: direct,
      stream: stream,
    );
  }

  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'hidden': hidden};
}

/// Tudo que o HomeCam guarda: servidores, cameras diretas, ordem e colunas.
class CamSettings {
  const CamSettings({
    this.cols = 3,
    this.servers = const [],
    this.direct = const [],
    this.cams = const [],
  });

  factory CamSettings.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) build) {
      final result = <T>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            result.add(build(item));
          }
        }
      }
      return result;
    }

    final cols = json['cols'];
    return CamSettings(
      cols: cols is int ? cols : 3,
      servers: list(json['servers'], CamServerConfig.fromJson),
      direct: list(json['direct'], CamDirect.fromJson),
      cams: list(json['cams'], CamEntry.fromJson),
    );
  }

  final int cols;
  final List<CamServerConfig> servers;
  final List<CamDirect> direct;
  final List<CamEntry> cams;

  CamSettings copyWith({
    int? cols,
    List<CamServerConfig>? servers,
    List<CamDirect>? direct,
    List<CamEntry>? cams,
  }) {
    return CamSettings(
      cols: cols ?? this.cols,
      servers: servers ?? this.servers,
      direct: direct ?? this.direct,
      cams: cams ?? this.cams,
    );
  }

  Map<String, dynamic> toJson() => {
    'cols': cols,
    'servers': [for (final s in servers) s.toJson()],
    'direct': [for (final d in direct) d.toJson()],
    'cams': [for (final c in cams) c.toJson()],
  };
}

/// Lista de cameras como a TV enxerga agora, mais os servidores com falha.
class CamListing {
  const CamListing({required this.cams, required this.errors});

  final List<CamEntry> cams;
  final Map<String, String> errors;
}
