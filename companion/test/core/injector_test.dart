import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/core/di/injector.dart';

class _Service {}

void main() {
  test('singleton devolve sempre a mesma instância', () {
    final injector = Injector()..registerSingleton<_Service>(_Service());
    expect(identical(injector.get<_Service>(), injector.get<_Service>()), true);
  });

  test('lazy constrói uma vez só', () {
    var built = 0;
    final injector = Injector()
      ..registerLazySingleton<_Service>(() {
        built++;
        return _Service();
      });
    injector.get<_Service>();
    injector.get<_Service>();
    expect(built, 1);
  });

  test('factory devolve instâncias novas', () {
    final injector = Injector()..registerFactory<_Service>(_Service.new);
    expect(
      identical(injector.get<_Service>(), injector.get<_Service>()),
      false,
    );
  });

  test('falha ao pedir algo não registrado', () {
    expect(
      () => Injector().get<_Service>(),
      throwsA(isA<DependencyNotFoundException>()),
    );
  });
}
