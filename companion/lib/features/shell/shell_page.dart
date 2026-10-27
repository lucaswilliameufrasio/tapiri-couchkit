import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:couchkit_remote/core/di/injector.dart';
import 'package:couchkit_remote/core/navigation/router.dart';
import 'package:couchkit_remote/data/tv_service_factory.dart';
import 'package:couchkit_remote/features/home/home_controller.dart';
import 'package:couchkit_remote/features/home/home_tab.dart';
import 'package:couchkit_remote/features/launcher/launcher_tab.dart';
import 'package:couchkit_remote/features/panels/panels_tab.dart';

/// Casca do app: Inicio, Apps da TV e Paineis.
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  static const route = '/';

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final injector = context.read<Injector>();
    final endpoint = context.watch<HomeController>().hub;
    final hub = endpoint == null
        ? null
        : injector.get<TvServiceFactory>().hub(endpoint);
    final router = injector.get<RouterService>();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeTab(hub: hub, endpoint: endpoint),
          LauncherTab(
            hub: hub,
            endpoint: endpoint,
            onPair: () => router.push<void>(context, '/add'),
          ),
          PanelsTab(hub: hub),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: 'Apps da TV',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Painéis',
          ),
        ],
      ),
    );
  }
}
