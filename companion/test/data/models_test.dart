import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/data/models/app_kind.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';

void main() {
  group('ConnectionUrl.parse', () {
    test('le host, porta e token', () {
      final url = ConnectionUrl.parse('http://10.0.0.5:8950/?k=a1b2c3d4');
      expect(url.host, '10.0.0.5');
      expect(url.port, 8950);
      expect(url.token, 'a1b2c3d4');
    });

    test('aceita sem esquema', () {
      final url = ConnectionUrl.parse('10.0.0.5:8800/?k=e5f6a7b8');
      expect(url.host, '10.0.0.5');
      expect(url.port, 8800);
    });

    test('recusa endereço sem token', () {
      expect(
        () => ConnectionUrl.parse('http://10.0.0.5:8950/'),
        throwsA(isA<InvalidConnectionUrlException>()),
      );
      expect(
        () => ConnectionUrl.parse('http://10.0.0.5:8950/?k='),
        throwsA(isA<InvalidConnectionUrlException>()),
      );
    });
  });

  group('AppKind.fromHtml', () {
    test('identifica cada app pelo título', () {
      expect(
        AppKind.fromHtml('<html><title>PhoneBro Remote</title>'),
        AppKind.phonebro,
      );
      expect(AppKind.fromHtml('<title>StickHub</title>'), AppKind.stickhub);
      expect(AppKind.fromHtml('<title>HomeCam</title>'), AppKind.homecam);
      expect(AppKind.fromHtml('<title>FireHome</title>'), AppKind.firehome);
    });

    test('ignora páginas desconhecidas', () {
      expect(AppKind.fromHtml('<title>Router admin</title>'), isNull);
      expect(AppKind.fromHtml('sem título'), isNull);
    });
  });

  group('TvEndpoint', () {
    test('ida e volta em JSON', () {
      const endpoint = TvEndpoint(
        kind: AppKind.phonecast,
        host: '10.0.0.5',
        port: 8850,
        token: 'tok',
      );
      expect(TvEndpoint.tryFromJson(endpoint.toJson()), endpoint);
      expect(endpoint.id, 'phonecast@10.0.0.5');
    });

    test('descarta JSON inválido', () {
      expect(TvEndpoint.tryFromJson({'kind': 'x'}), isNull);
      expect(TvEndpoint.tryFromJson('lixo'), isNull);
    });
  });
}
