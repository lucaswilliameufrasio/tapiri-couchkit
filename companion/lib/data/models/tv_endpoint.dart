import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';

/// Um app da TV: tipo, endereco e token. Um por tipo e por host.
class TvEndpoint {
  const TvEndpoint({
    required this.kind,
    required this.host,
    required this.port,
    required this.token,
  });

  final AppKind kind;
  final String host;
  final int port;
  final String token;

  String get id => '${kind.name}@$host';

  Uri get baseUri => Uri(scheme: 'http', host: host, port: port);

  TvEndpoint withPort(int newPort) =>
      TvEndpoint(kind: kind, host: host, port: newPort, token: token);

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'host': host,
    'port': port,
    'token': token,
  };

  static TvEndpoint? tryFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final kind = AppKind.byName('${json['kind']}');
    final host = json['host'];
    final port = json['port'];
    final token = json['token'];
    if (kind == null || host is! String || port is! int || token is! String) {
      return null;
    }
    return TvEndpoint(kind: kind, host: host, port: port, token: token);
  }

  @override
  bool operator ==(Object other) =>
      other is TvEndpoint &&
      other.kind == kind &&
      other.host == host &&
      other.port == port &&
      other.token == token;

  @override
  int get hashCode => Object.hash(kind, host, port, token);
}

/// Dados lidos do QR / URL mostrado pela TV, ainda sem saber qual app e.
class ConnectionUrl {
  const ConnectionUrl({
    required this.host,
    required this.port,
    required this.token,
  });

  final String host;
  final int port;
  final String token;

  /// Aceita `http://ip:porta/?k=token`, com ou sem esquema. Exige o token.
  factory ConnectionUrl.parse(String raw) {
    var text = raw.trim();
    if (!text.contains('://')) {
      text = 'http://$text';
    }
    final uri = Uri.tryParse(text);
    final token = uri?.queryParameters['k'] ?? '';
    if (uri == null || uri.host.isEmpty || token.isEmpty) {
      throw const InvalidConnectionUrlException();
    }
    return ConnectionUrl(
      host: uri.host,
      port: uri.hasPort ? uri.port : 80,
      token: token,
    );
  }
}
