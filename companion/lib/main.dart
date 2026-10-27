import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:couchkit_remote/core/di/injector.dart';
import 'package:couchkit_remote/core/navigation/router.dart';
import 'package:couchkit_remote/core/ui/theme.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';
import 'package:couchkit_remote/data/panels_repository.dart';
import 'package:couchkit_remote/data/tv_adb.dart';
import 'package:couchkit_remote/data/tv_repository.dart';
import 'package:couchkit_remote/data/tv_service_factory.dart';
import 'package:couchkit_remote/features/home/home_controller.dart';
import 'package:couchkit_remote/features/panels/panels_controller.dart';
import 'package:couchkit_remote/features/routes.dart';
import 'package:couchkit_remote/features/shell/shell_page.dart';

Injector buildInjector() {
  final injector = Injector();
  injector.registerSingleton<KeyValueStore>(SecureStorageService());
  injector.registerLazySingleton<TvAdb>(
    () => TvAdb(injector.get<KeyValueStore>()),
  );
  injector.registerLazySingleton<TvRepository>(
    () => TvRepository(injector.get<KeyValueStore>()),
  );
  injector.registerLazySingleton<PanelsRepository>(
    () => PanelsRepository(injector.get<KeyValueStore>()),
  );
  injector.registerSingleton<TvServiceFactory>(const TvServiceFactory());
  injector.registerLazySingleton<RouterService>(() {
    return RouterService()..initialize([AppRoutes(injector)]);
  });
  return injector;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CouchkitApp(injector: buildInjector()));
}

class CouchkitApp extends StatelessWidget {
  const CouchkitApp({required this.injector, super.key});

  final Injector injector;

  @override
  Widget build(BuildContext context) {
    final router = injector.get<RouterService>();
    return MultiProvider(
      providers: [
        Provider<Injector>.value(value: injector),
        ChangeNotifierProvider(
          create: (_) =>
              PanelsController(injector.get<PanelsRepository>())..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => HomeController(injector.get<TvRepository>())..load(),
        ),
      ],
      child: MaterialApp(
        title: 'Couchkit',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        initialRoute: ShellPage.route,
        onGenerateRoute: router.onGenerateRoute,
      ),
    );
  }
}
