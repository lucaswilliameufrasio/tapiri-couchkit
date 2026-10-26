import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'dart:io';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/services/firehome_service.dart';
import 'package:couchkit_remote/features/firehome/firehome_controller.dart';

class _Preset {
  const _Preset(this.name, this.bg, this.accent);

  final String name;
  final List<String> bg;
  final String accent;
}

const _presets = [
  _Preset('Aurora', ['#0B1020', '#1B1140', '#3A1550'], '#5CC8FF'),
  _Preset('Oceano', ['#041a2b', '#06406b', '#0a7c8c'], '#7fe8ff'),
  _Preset('Floresta', ['#081c14', '#0f3a2a', '#1a5a45'], '#7FE8B0'),
  _Preset('Grafite', ['#0e0e10', '#1a1a1f', '#2a2a33'], '#ffffff'),
  _Preset('Pôr do sol', ['#2b0f1f', '#6b1f3a', '#c2573a'], '#ffd27f'),
  _Preset('Vinho', ['#1a0710', '#3a0f24', '#5c1a3a'], '#ff9fc8'),
];

const _toolLabels = {
  'settings': 'Configurações',
  'clean': 'Limpar RAM',
  'wifi': 'Rede',
  'customize': 'Personalizar (QR)',
};

Color _parse(Object? value, Color fallback) {
  final text = '$value'.replaceFirst('#', '');
  final number = int.tryParse(text, radix: 16);
  if (number == null) {
    return fallback;
  }
  return Color(text.length == 6 ? 0xFF000000 | number : number);
}

class FireHomePage extends StatelessWidget {
  const FireHomePage({required this.service, super.key});

  static const route = '/firehome';

  final FireHomeService service;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FireHomeController(service)..load(),
      child: const _FireHomeView(),
    );
  }
}

class _FireHomeView extends StatelessWidget {
  const _FireHomeView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('FireHome'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(c.status, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
      body: c.loading
          ? const Center(child: CircularProgressIndicator())
          : c.error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: c.load,
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              children: [
                _Preview(controller: c),
                const _Section(
                  title: 'Aparência',
                  initiallyExpanded: true,
                  child: _Appearance(),
                ),
                const _Section(title: 'Papel de parede', child: _Wallpaper()),
                const _Section(title: 'Cabeçalho', child: _HeaderSettings()),
                const _Section(
                  title: 'Linhas da tela inicial',
                  initiallyExpanded: true,
                  child: _Rows(),
                ),
                const _Section(title: 'Favoritos (ordem)', child: _Pins()),
                const _Section(title: 'Apps', child: _Apps()),
                const _Section(
                  title: 'Ferramentas (linha Sistema)',
                  child: _Tools(),
                ),
                const _Section(title: 'Avançado', child: _Advanced()),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [child],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});

  final FireHomeController controller;

  @override
  Widget build(BuildContext context) {
    final uri = controller.service.previewUri(controller.previewTick);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: Image.network(
                uri.toString(),
                gaplessPlayback: true,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Abra o FireHome na TV para ver a prévia',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar prévia'),
            onPressed: controller.refreshPreview,
          ),
        ),
      ],
    );
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    final bg = c.theme['bg'] as List<dynamic>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _presets)
              Tooltip(
                message: preset.name,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => c.edit(() {
                    c.theme['bg'] = List<dynamic>.of(preset.bg);
                    c.theme['accent'] = preset.accent;
                  }),
                  child: Container(
                    width: 56,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          for (final hex in preset.bg)
                            _parse(hex, Colors.black),
                        ],
                      ),
                      border: Border.all(
                        color: _parse(preset.accent, Colors.white),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _ColorField(
          label: 'Fundo (início)',
          value: '${bg[0]}',
          onChanged: (v) => c.edit(() => bg[0] = v),
        ),
        _ColorField(
          label: 'Fundo (meio)',
          value: '${bg[1]}',
          onChanged: (v) => c.edit(() => bg[1] = v),
        ),
        _ColorField(
          label: 'Fundo (fim)',
          value: '${bg[2]}',
          onChanged: (v) => c.edit(() => bg[2] = v),
        ),
        _ColorField(
          label: 'Cor de destaque',
          value: '${c.theme['accent']}',
          onChanged: (v) => c.edit(() => c.theme['accent'] = v),
        ),
        _Slide(
          label: 'Cantos',
          value: c.theme['radius'],
          min: 0,
          max: 40,
          onChanged: (v) => c.edit(() => c.theme['radius'] = v),
        ),
        _Slide(
          label: 'Tamanho dos cartões',
          value: c.theme['scale'],
          min: 60,
          max: 150,
          onChanged: (v) => c.edit(() => c.theme['scale'] = v),
        ),
        _Slide(
          label: 'Tamanho do texto',
          value: c.theme['labelSize'],
          min: 10,
          max: 24,
          onChanged: (v) => c.edit(() => c.theme['labelSize'] = v),
        ),
      ],
    );
  }
}

class _ColorField extends StatefulWidget {
  const _ColorField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_ColorField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value &&
        _text.text.toLowerCase() != widget.value.toLowerCase()) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$')
        .hasMatch(_text.text);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _parse(_text.text, Colors.black),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.label)),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _text,
              autocorrect: false,
              decoration: InputDecoration(
                isDense: true,
                errorText: valid ? null : 'ex.: #1B1140',
              ),
              onChanged: (v) {
                setState(() {});
                if (RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$').hasMatch(v)) {
                  widget.onChanged(v);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final Object? value;
  final double min;
  final double max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = ((value as num?) ?? min).toDouble().clamp(min, max);
    return Row(
      children: [
        Expanded(flex: 4, child: Text(label)),
        Expanded(
          flex: 5,
          child: Slider(
            value: current,
            min: min,
            max: max,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Usar papel de parede'),
          value: c.wallpaper['on'] == true,
          onChanged: (v) => c.edit(() => c.wallpaper['on'] = v),
        ),
        _Slide(
          label: 'Escurecer',
          value: c.wallpaper['dim'],
          min: 0,
          max: 90,
          onChanged: (v) => c.edit(() => c.wallpaper['dim'] = v),
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: const Text('Escolher imagem'),
                onPressed: () async {
                  final picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                  );
                  if (picked == null || !context.mounted) {
                    return;
                  }
                  try {
                    final message = await c.uploadWallpaper(File(picked.path));
                    if (context.mounted) {
                      showMessage(context, message);
                    }
                  } catch (error) {
                    if (context.mounted) {
                      showMessage(context, describeError(error));
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: c.clearWallpaper,
              child: const Text('Remover'),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderSettings extends StatefulWidget {
  const _HeaderSettings();

  @override
  State<_HeaderSettings> createState() => _HeaderSettingsState();
}

class _HeaderSettingsState extends State<_HeaderSettings> {
  late final TextEditingController _greeting;
  late final TextEditingController _city;

  @override
  void initState() {
    super.initState();
    final c = context.read<FireHomeController>();
    _greeting = TextEditingController(text: '${c.header['greeting'] ?? ''}');
    _city = TextEditingController(text: '${c.header['city'] ?? ''}');
  }

  @override
  void dispose() {
    _greeting.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    Widget toggle(String label, Json map, String key) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: map[key] == true,
        onChanged: (v) => c.edit(() => map[key] = v),
      );
    }

    return Column(
      children: [
        toggle('Relógio', c.header, 'clock'),
        toggle('Formato 24 horas', c.header, 'h24'),
        toggle('Data', c.header, 'date'),
        toggle('RAM livre', c.header, 'ram'),
        toggle('Dica no rodapé', c.config, 'hint'),
        const SizedBox(height: 8),
        TextField(
          controller: _greeting,
          decoration: const InputDecoration(
            labelText: 'Saudação',
            hintText: 'ex.: Boa noite, Lucas',
          ),
          onChanged: (v) => c.edit(() => c.header['greeting'] = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          decoration: const InputDecoration(
            labelText: 'Cidade (clima)',
            hintText: 'ex.: Recife',
          ),
          onChanged: (v) => c.edit(() => c.header['city'] = v),
        ),
      ],
    );
  }
}

typedef Json = Map<String, dynamic>;

class _Rows extends StatelessWidget {
  const _Rows();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    return Column(
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorderItem: c.moveRow,
          children: [
            for (var i = 0; i < c.rows.length; i++)
              _RowTile(key: ValueKey(c.rows[i]['id']), index: i),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Nova linha'),
            onPressed: c.addCustomRow,
          ),
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.index, super.key});

  final int index;

  static const _types = {
    'pins': 'Favoritos',
    'all': 'Todos os apps',
    'tools': 'Ferramentas',
    'custom': 'Personalizada',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    final row = c.rows[index] as Json;
    final custom = row['type'] == 'custom';
    return Card(
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.drag_handle),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '${row['title']}',
                    decoration: InputDecoration(
                      isDense: true,
                      helperText: _types['${row['type']}'],
                    ),
                    onChanged: (v) => c.edit(() => row['title'] = v),
                  ),
                ),
                if (custom)
                  IconButton(
                    tooltip: 'Remover linha',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => c.edit(() => c.rows.removeAt(index)),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Visível'),
                  selected: row['show'] == true,
                  onSelected: (v) => c.edit(() => row['show'] = v),
                ),
                FilterChip(
                  label: const Text('Cartões grandes'),
                  selected: row['big'] == true,
                  onSelected: (v) => c.edit(() => row['big'] = v),
                ),
                if (custom)
                  ActionChip(
                    avatar: const Icon(Icons.apps, size: 18),
                    label: Text(
                      'Apps (${(row['apps'] as List<dynamic>).length})',
                    ),
                    onPressed: () => _pickApps(context, c, row),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickApps(BuildContext context, FireHomeController c, Json row) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setState) {
          final selected = row['apps'] as List<dynamic>;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(sheet).size.height * 0.7,
              child: ListView(
                children: [
                  for (final app in c.apps)
                    CheckboxListTile(
                      value: selected.contains(app.pkg),
                      title: Text(c.labelFor(app.pkg)),
                      subtitle: Text(
                        app.pkg,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onChanged: (v) {
                        c.edit(() {
                          if (v == true) {
                            selected.add(app.pkg);
                          } else {
                            selected.remove(app.pkg);
                          }
                        });
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Pins extends StatelessWidget {
  const _Pins();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    if (c.pins.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Nenhum favorito. Use a estrela na lista de apps.'),
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorderItem: c.movePin,
      children: [
        for (final pkg in c.pins)
          ListTile(
            key: ValueKey('pin-$pkg'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.drag_handle),
            title: Text(c.labelFor('$pkg')),
            subtitle: Text('$pkg', style: const TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => c.togglePin('$pkg'),
            ),
          ),
      ],
    );
  }
}

class _Apps extends StatefulWidget {
  const _Apps();

  @override
  State<_Apps> createState() => _AppsState();
}

class _AppsState extends State<_Apps> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    final query = _query.toLowerCase();
    final visible = <LauncherApp>[];
    for (final app in c.apps) {
      if (query.isEmpty ||
          app.label.toLowerCase().contains(query) ||
          app.pkg.contains(query)) {
        visible.add(app);
      }
    }
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar app',
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        for (final app in visible)
          ListTile(
            key: ValueKey('app-${app.pkg}'),
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 40,
              height: 40,
              child: Image.network(
                c.service.iconUri(app.pkg).toString(),
                errorBuilder: (context, error, stack) =>
                    const Icon(Icons.android),
              ),
            ),
            title: TextFormField(
              initialValue: '${c.names[app.pkg] ?? ''}',
              decoration: InputDecoration(
                isDense: true,
                hintText: app.label,
                border: InputBorder.none,
              ),
              onChanged: (v) => c.rename(app.pkg, v),
            ),
            subtitle: Text(app.pkg, style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Favorito',
                  icon: Icon(
                    c.isPinned(app.pkg) ? Icons.star : Icons.star_border,
                  ),
                  onPressed: () => c.togglePin(app.pkg),
                ),
                IconButton(
                  tooltip: c.isHidden(app.pkg) ? 'Mostrar' : 'Esconder',
                  icon: Icon(
                    c.isHidden(app.pkg)
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () => c.toggleHidden(app.pkg),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tools extends StatelessWidget {
  const _Tools();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FireHomeController>();
    final order = <String>[for (final t in c.tools) '$t'];
    for (final id in _toolLabels.keys) {
      if (!order.contains(id)) {
        order.add(id);
      }
    }
    return Column(
      children: [
        for (final id in order)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_toolLabels[id] ?? id),
            value: c.tools.contains(id),
            onChanged: (v) => c.edit(() {
              if (v) {
                c.tools.add(id);
              } else {
                c.tools.remove(id);
              }
            }),
          ),
      ],
    );
  }
}

class _Advanced extends StatelessWidget {
  const _Advanced();

  @override
  Widget build(BuildContext context) {
    final c = context.read<FireHomeController>();
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.restore),
        label: const Text('Restaurar padrões'),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('Restaurar o launcher?'),
              content: const Text(
                'Todas as personalizações do FireHome serão perdidas.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('Restaurar'),
                ),
              ],
            ),
          );
          if (ok == true) {
            await c.reset();
          }
        },
      ),
    );
  }
}
