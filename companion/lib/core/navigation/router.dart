import 'package:flutter/material.dart';

typedef RouteBuilder = Widget Function(BuildContext context, Object? args);

abstract class RouteModule {
  void register(RouterService router);
}

/// Rotas nomeadas, registradas por modulo de feature.
class RouterService {
  final Map<String, RouteBuilder> _routes = {};

  void initialize(List<RouteModule> modules) {
    for (final module in modules) {
      module.register(this);
    }
  }

  void register(String path, RouteBuilder builder) {
    _routes[path] = builder;
  }

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = _routes[settings.name];
    if (builder == null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: Center(child: Text('Rota não encontrada: ${settings.name}')),
        ),
      );
    }
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (context) => builder(context, settings.arguments),
    );
  }

  Future<T?> push<T>(BuildContext context, String path, {Object? args}) {
    return Navigator.of(context).pushNamed<T>(path, arguments: args);
  }
}
