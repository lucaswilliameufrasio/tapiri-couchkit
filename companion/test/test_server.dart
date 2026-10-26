import 'dart:convert';
import 'dart:io';

/// Servidor HTTP local que imita um app da TV (titulo + /api com token).
class FakeTv {
  FakeTv._(this._server, this.token);

  final HttpServer _server;
  final String token;
  final List<Uri> requests = [];
  final List<String> bodies = [];

  int get port => _server.port;

  static Future<FakeTv> start({
    required String title,
    String token = 'abc12345',
    int? port,
    String Function(String path)? api,
  }) async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port ?? 0,
    );
    final tv = FakeTv._(server, token);
    server.listen((request) async {
      tv.requests.add(request.uri);
      if (request.method == 'POST') {
        tv.bodies.add(await utf8.decoder.bind(request).join());
      }
      final response = request.response;
      if (request.uri.path == '/') {
        response.headers.contentType = ContentType.html;
        response.write('<html><title>$title</title></html>');
      } else if (request.uri.queryParameters['k'] != token) {
        response.statusCode = 403;
        response.write('forbidden');
      } else {
        response.headers.contentType = ContentType.json;
        response.write(api?.call(request.uri.path) ?? jsonEncode({'ok': true}));
      }
      await response.close();
    });
    return tv;
  }

  Future<void> stop() => _server.close(force: true);
}
