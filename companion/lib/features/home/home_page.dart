import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:couchkit_remote/core/di/injector.dart';
import 'package:couchkit_remote/core/navigation/router.dart';
import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/models/tv_endpoint.dart';
import 'package:couchkit_remote/features/home/home_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const route = '/';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    final router = context.read<Injector>().get<RouterService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Couchkit'),
        actions: [
          IconButton(
            tooltip: 'Verificar de novo',
            icon: const Icon(Icons.refresh),
            onPressed: controller.refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Adicionar'),
        onPressed: () => router.push<void>(context, '/add'),
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.endpoints.isEmpty
          ? const _EmptyState()
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: _EndpointList(controller: controller, router: router),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tv, size: 72),
            const SizedBox(height: 16),
            Text('Nenhuma TV ainda', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Abra um app do couchkit na TV, aperte MENU para ver o QR '
              'code e escaneie por aqui.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _EndpointList extends StatelessWidget {
  const _EndpointList({required this.controller, required this.router});

  final HomeController controller;
  final RouterService router;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final group in controller.byHost.entries) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.tv, size: 18),
              const SizedBox(width: 8),
              Text(group.key, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      );
      for (final endpoint in group.value) {
        children.add(
          _EndpointCard(
            endpoint: endpoint,
            presence: controller.presence[endpoint.id] ?? Presence.checking,
            onOpen: () => router.push<void>(
              context,
              '/${endpoint.kind.name}',
              args: endpoint,
            ),
            onRemove: () async {
              final ok = await _confirmRemove(context, endpoint);
              if (ok == true) {
                await controller.remove(endpoint);
              }
            },
          ),
        );
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: children,
    );
  }

  Future<bool?> _confirmRemove(BuildContext context, TvEndpoint endpoint) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover ${endpoint.kind.label}?'),
        content: const Text('O token guardado neste celular será apagado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({
    required this.endpoint,
    required this.presence,
    required this.onOpen,
    required this.onRemove,
  });

  final TvEndpoint endpoint;
  final Presence presence;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final kind = endpoint.kind;
    final (label, color) = switch (presence) {
      Presence.online => ('online', Colors.green),
      Presence.offline => ('offline', Colors.redAccent),
      Presence.checking => ('verificando…', Colors.grey),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: kind.color,
          foregroundColor: Colors.white,
          child: Icon(kind.icon),
        ),
        title: Text(kind.label),
        subtitle: Row(
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${kind.description} · $label',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Remover',
          icon: const Icon(Icons.delete_outline),
          onPressed: onRemove,
        ),
        onTap: presence == Presence.offline
            ? () => showMessage(
                context,
                'A TV não responde. Abra o app na TV e puxe para atualizar.',
              )
            : onOpen,
      ),
    );
  }
}
