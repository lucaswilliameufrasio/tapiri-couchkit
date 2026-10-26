class DependencyNotFoundException implements Exception {
  DependencyNotFoundException(this.type);

  final Type type;

  @override
  String toString() => 'DependencyNotFoundException: $type';
}

/// Container de dependencias simples (singletons, lazy e factories).
class Injector {
  final Map<Type, Object> _singletons = {};
  final Map<Type, Object Function()> _lazy = {};
  final Map<Type, Object Function()> _factories = {};

  void registerSingleton<T extends Object>(T instance) {
    _singletons[T] = instance;
  }

  void registerLazySingleton<T extends Object>(T Function() builder) {
    _lazy[T] = builder;
  }

  void registerFactory<T extends Object>(T Function() builder) {
    _factories[T] = builder;
  }

  T get<T extends Object>() {
    final singleton = _singletons[T];
    if (singleton != null) {
      return singleton as T;
    }

    final lazy = _lazy.remove(T);
    if (lazy != null) {
      final instance = lazy() as T;
      _singletons[T] = instance;
      return instance;
    }

    final factory = _factories[T];
    if (factory != null) {
      return factory() as T;
    }

    throw DependencyNotFoundException(T);
  }

  void reset() {
    _singletons.clear();
    _lazy.clear();
    _factories.clear();
  }
}
