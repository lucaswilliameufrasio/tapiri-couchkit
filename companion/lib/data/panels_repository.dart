import 'dart:convert';

import 'package:couchkit_remote/data/models/panel.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';

/// Paineis guardados no cofre do celular (o cabecalho pode ter um token).
class PanelsRepository {
  PanelsRepository(this._store);

  static const _key = 'panels';

  final KeyValueStore _store;

  Future<List<Panel>> load() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw);
    final result = <Panel>[];
    if (decoded is List) {
      for (final item in decoded) {
        final panel = Panel.tryFromJson(item);
        if (panel != null) {
          result.add(panel);
        }
      }
    }
    return result;
  }

  Future<void> save(Panel panel) async {
    final all = await load();
    final next = <Panel>[];
    var replaced = false;
    for (final item in all) {
      if (item.id == panel.id) {
        next.add(panel);
        replaced = true;
      } else {
        next.add(item);
      }
    }
    if (!replaced) {
      next.add(panel);
    }
    await _persist(next);
  }

  Future<void> remove(String id) async {
    final all = await load();
    final next = <Panel>[];
    for (final item in all) {
      if (item.id != id) {
        next.add(item);
      }
    }
    await _persist(next);
  }

  Future<void> _persist(List<Panel> panels) {
    final json = <Object>[];
    for (final panel in panels) {
      json.add(panel.toJson());
    }
    return _store.write(_key, jsonEncode(json));
  }
}
