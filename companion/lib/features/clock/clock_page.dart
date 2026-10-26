import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/services/clock_service.dart';

class ClockPage extends StatefulWidget {
  const ClockPage({required this.service, super.key});

  static const route = '/stickclock';

  final ClockService service;

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  final _city = TextEditingController();
  final _item = TextEditingController();
  ClockData? _data;

  ClockService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _city.dispose();
    _item.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await guarded(context, _service.get);
    if (data != null && mounted) {
      setState(() {
        _data = data;
        if (_city.text.isEmpty) {
          _city.text = data.city;
        }
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    await guarded(context, action);
    await _load();
  }

  Future<void> _setCity() async {
    final label = await guarded(context, () => _service.setCity(_city.text));
    if (mounted && label != null) {
      showMessage(context, label.isEmpty ? 'Cidade definida' : label);
    }
    await _load();
  }

  Future<void> _add() async {
    final text = _item.text.trim();
    if (text.isEmpty) {
      return;
    }
    _item.clear();
    await _run(() => _service.add(text));
  }

  @override
  Widget build(BuildContext context) {
    final notes = _data?.notes ?? const <ClockNote>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('StickClock'),
        actions: [
          IconButton(
            tooltip: 'Limpar concluídos',
            icon: const Icon(Icons.done_all),
            onPressed: () => _run(_service.clearDone),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _city,
              decoration: InputDecoration(
                labelText: 'Cidade (clima)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: _setCity,
                ),
              ),
              onSubmitted: (_) => _setCity(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _item,
              decoration: InputDecoration(
                labelText: 'Novo item da lista',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _add,
                ),
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return Dismissible(
                    key: ValueKey('$index-${note.text}'),
                    background: Container(color: Colors.redAccent),
                    onDismissed: (_) => _run(() => _service.remove(index)),
                    child: CheckboxListTile(
                      value: note.done,
                      onChanged: (_) => _run(() => _service.toggle(index)),
                      title: Text(
                        note.text,
                        style: TextStyle(
                          decoration: note.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
