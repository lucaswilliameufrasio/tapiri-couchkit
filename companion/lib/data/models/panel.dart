/// Um painel web (Grafana, backoffice...). So guarda a URL e, se precisar,
/// um cabecalho de autenticacao: nada aqui conhece o servico de origem.
class Panel {
  const Panel({
    required this.id,
    required this.name,
    required this.url,
    this.header = '',
    this.refreshSeconds = 0,
  });

  final String id;
  final String name;
  final String url;

  /// Opcional, no formato `Nome: valor` (ex.: `Authorization: Bearer xxx`).
  final String header;

  /// 0 desliga a atualizacao automatica.
  final int refreshSeconds;

  Uri? get uri {
    final parsed = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (parsed == null || parsed.host.isEmpty) {
      return null;
    }
    return parsed;
  }

  Map<String, String> get headers {
    final index = header.indexOf(':');
    if (index <= 0) {
      return const {};
    }
    final name = header.substring(0, index).trim();
    final value = header.substring(index + 1).trim();
    if (name.isEmpty || value.isEmpty) {
      return const {};
    }
    return {name: value};
  }

  Panel copyWith({
    String? name,
    String? url,
    String? header,
    int? refreshSeconds,
  }) {
    return Panel(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      header: header ?? this.header,
      refreshSeconds: refreshSeconds ?? this.refreshSeconds,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'header': header,
    'refresh': refreshSeconds,
  };

  static Panel? tryFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final name = json['name'];
    final url = json['url'];
    if (id is! String || name is! String || url is! String) {
      return null;
    }
    final header = json['header'];
    final refresh = json['refresh'];
    return Panel(
      id: id,
      name: name,
      url: url,
      header: header is String ? header : '',
      refreshSeconds: refresh is int ? refresh : 0,
    );
  }
}
