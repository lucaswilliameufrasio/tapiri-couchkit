import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:couchkit_remote/core/di/injector.dart';
import 'package:couchkit_remote/core/navigation/router.dart';
import 'package:couchkit_remote/core/ui/widgets.dart';
import 'package:couchkit_remote/data/models/panel.dart';
import 'package:couchkit_remote/data/services/hub_service.dart';
import 'package:couchkit_remote/features/panels/panel_view_page.dart';
import 'package:couchkit_remote/features/panels/panels_controller.dart';

/// Lista de paineis web (Grafana, backoffice...), abertos aqui ou na TV.
class PanelsTab extends StatelessWidget {
  const PanelsTab({required this.hub, super.key});

  final HubService? hub;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PanelsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Painéis')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo painel'),
        onPressed: () => _edit(context, controller),
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.panels.isEmpty
          ? const EmptyPane(
              icon: Icons.dashboard_outlined,
              title: 'Nenhum painel ainda',
              message:
                  'Guarde aqui as URLs dos seus dashboards (Grafana, '
                  'backoffice…). Abra no celular ou mande para a TV com um '
                  'toque. Para Grafana, use ?kiosk na URL.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: controller.panels.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final panel = controller.panels[index];
                return _PanelCard(
                  panel: panel,
                  onOpen: () =>
                      context.read<Injector>().get<RouterService>().push<void>(
                        context,
                        PanelViewPage.route,
                        args: (panel, hub),
                      ),
                  onEdit: () => _edit(context, controller, panel),
                  onDelete: () => controller.remove(panel),
                );
              },
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    PanelsController controller, [
    Panel? existing,
  ]) async {
    final result = await showModalBottomSheet<Panel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PanelForm(existing: existing),
    );
    if (result != null) {
      await controller.save(result);
    }
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.panel,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Panel panel;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            children: [
              IconBadge(icon: Icons.insights, color: scheme.primary, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      panel.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      panel.uri?.host ?? panel.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else {
                    onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'delete', child: Text('Remover')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelForm extends StatefulWidget {
  const _PanelForm({this.existing});

  final Panel? existing;

  @override
  State<_PanelForm> createState() => _PanelFormState();
}

class _PanelFormState extends State<_PanelForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _url = TextEditingController(text: widget.existing?.url);
  late final _header = TextEditingController(text: widget.existing?.header);
  late int _refresh = widget.existing?.refreshSeconds ?? 0;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _header.dispose();
    super.dispose();
  }

  void _submit() {
    final draft = Panel(
      id:
          widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      url: _url.text.trim(),
      header: _header.text.trim(),
      refreshSeconds: _refresh,
    );
    if (draft.name.isEmpty || draft.uri == null) {
      setState(() => _error = 'Informe um nome e uma URL válida.');
      return;
    }
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? 'Novo painel' : 'Editar painel',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://grafana.exemplo.com/d/abc?kiosk',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _header,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Cabeçalho de autenticação (opcional)',
                hintText: 'Authorization: Bearer …',
                helperText: 'Só vale no celular; a TV abre sem ele.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _refresh,
              decoration: const InputDecoration(labelText: 'Atualizar sozinho'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Nunca')),
                DropdownMenuItem(value: 30, child: Text('A cada 30 s')),
                DropdownMenuItem(value: 60, child: Text('A cada 1 min')),
                DropdownMenuItem(value: 300, child: Text('A cada 5 min')),
              ],
              onChanged: (value) => setState(() => _refresh = value ?? 0),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _submit, child: const Text('Salvar')),
          ],
        ),
      ),
    );
  }
}
