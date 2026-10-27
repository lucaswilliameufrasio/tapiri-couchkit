import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/data/models/panel.dart';
import 'package:couchkit_remote/data/panels_repository.dart';

class PanelsController extends ChangeNotifier {
  PanelsController(this._repository);

  final PanelsRepository _repository;

  List<Panel> panels = [];
  bool loading = true;

  Future<void> load() async {
    panels = await _repository.load();
    loading = false;
    notifyListeners();
  }

  Future<void> save(Panel panel) async {
    await _repository.save(panel);
    panels = await _repository.load();
    notifyListeners();
  }

  Future<void> remove(Panel panel) async {
    await _repository.remove(panel.id);
    panels = await _repository.load();
    notifyListeners();
  }
}
