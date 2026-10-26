import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';

typedef Json = Map<String, dynamic>;

/// Cliente HTTP de um app da TV. Toda rota /api/* exige o token (?k=).
class TvClient {
  TvClient(this.endpoint, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 10),
              validateStatus: (_) => true,
              responseType: ResponseType.plain,
            ),
          );

  final TvEndpoint endpoint;
  final Dio _dio;

  Uri uri(String path, [Map<String, String?> query = const {}]) {
    final params = <String, String>{'k': endpoint.token};
    for (final entry in query.entries) {
      final value = entry.value;
      if (value != null) {
        params[entry.key] = value;
      }
    }
    return Uri(
      scheme: 'http',
      host: endpoint.host,
      port: endpoint.port,
      path: path,
      queryParameters: params,
    );
  }

  Future<Json> getJson(
    String path, [
    Map<String, String?> query = const {},
  ]) async {
    final decoded = await getAny(path, query);
    return decoded is Json ? decoded : {};
  }

  /// Resposta JSON de qualquer formato (objeto ou lista).
  Future<Object?> getAny(
    String path, [
    Map<String, String?> query = const {},
  ]) async {
    final response = await _guard(() => _dio.getUri<String>(uri(path, query)));
    return _decode(response.data);
  }

  Future<Json> upload(
    String path,
    Map<String, String?> query,
    Stream<List<int>> data,
    int length, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final response = await _guard(
      () => _dio.postUri<String>(
        uri(path, query),
        data: data,
        options: Options(
          headers: {Headers.contentLengthHeader: length},
          sendTimeout: const Duration(minutes: 30),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onSendProgress: onProgress,
      ),
    );
    final decoded = _decode(response.data);
    return decoded is Json ? decoded : {};
  }

  Future<Response<String>> _guard(
    Future<Response<String>> Function() request,
  ) async {
    final Response<String> response;
    try {
      response = await request();
    } on DioException catch (error) {
      throw TvUnreachableException(
        'Sem resposta de ${endpoint.host}:${endpoint.port}'
        ' (${error.type.name})',
      );
    }

    final status = response.statusCode ?? 0;
    if (status == 403) {
      throw const TvUnauthorizedException();
    }
    if (status >= 400) {
      throw TvRequestException('A TV respondeu $status', status: status);
    }
    return response;
  }

  Object? _decode(String? body) {
    if (body == null || body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
