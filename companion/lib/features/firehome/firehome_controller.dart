import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';
import 'package:couchkit_remote/core/network/tv_client.dart';
import 'package:couchkit_remote/data/services/firehome_service.dart';

/// Mantem a configuracao em memoria e salva sozinho (debounce) a cada edicao.
class FireHomeController extends ChangeNotifier {
  FireHomeController(this._service);

  final FireHomeService _service;

  Json config = {};
  List<LauncherApp> apps = [];
  bool loading = true;
  String? error;
  String status = '';
  int previewTick = 0;
  Timer? _debounce;

  FireHomeService get service => _service;

  Json get theme => config['theme'] as Json;
  Json get wallpaper => config['wallpaper'] as Json;
  Json get header => config['header'] as Json;
  List<dynamic> get rows => config['rows'] as List<dynamic>;
  List<dynamic> get pins => config['pins'] as List<dynamic>;
  List<dynamic> get hidden => config['hidden'] as List<dynamic>;
  List<dynamic> get tools => config['tools'] as List<dynamic>;
  Json get names => config['names'] as Json;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      config = await _service.config();
      apps = await _service.apps();
      status = 'Conectado';
      previewTick++;
    } on AppException catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  String labelFor(String pkg) {
    final custom = names[pkg];
    if (custom is String && custom.isNotEmpty) {
      return custom;
    }
    for (final app in apps) {
      if (app.pkg == pkg) {
        return app.label;
      }
    }
    return pkg;
  }

  /// Aplica a edicao, avisa a UI e agenda o salvamento.
  void edit(void Function() change) {
    change();
    status = 'Salvando…';
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _flush);
  }

  Future<void> _flush() async {
    try {
      await _service.save(config);
      status = 'Salvo';
      await Future<void>.delayed(const Duration(milliseconds: 700));
      previewTick++;
    } on AppException catch (e) {
      status = e.message;
    }
    notifyListeners();
  }

  Future<String> uploadWallpaper(File file) async {
    status = 'Enviando imagem…';
    notifyListeners();
    try {
      final message = await _service.uploadWallpaper(file);
      await load();
      return message;
    } on AppException catch (e) {
      status = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> clearWallpaper() async {
    await _service.clearWallpaper();
    await load();
  }

  Future<void> reset() async {
    await _service.reset();
    await load();
  }

  void movePin(int from, int to) {
    edit(() {
      final item = pins.removeAt(from);
      pins.insert(to, item);
    });
  }

  void moveRow(int from, int to) {
    edit(() {
      final item = rows.removeAt(from);
      rows.insert(to, item);
    });
  }

  void refreshPreview() {
    previewTick++;
    notifyListeners();
  }

  bool isPinned(String pkg) => pins.contains(pkg);

  bool isHidden(String pkg) => hidden.contains(pkg);

  void togglePin(String pkg) {
    edit(() {
      if (!pins.remove(pkg)) {
        pins.add(pkg);
      }
    });
  }

  void toggleHidden(String pkg) {
    edit(() {
      if (!hidden.remove(pkg)) {
        hidden.add(pkg);
      }
    });
  }

  void rename(String pkg, String value) {
    edit(() {
      final text = value.trim();
      if (text.isEmpty) {
        names.remove(pkg);
      } else {
        names[pkg] = text;
      }
    });
  }

  void addCustomRow() {
    edit(() {
      rows.add({
        'id': 'r${DateTime.now().millisecondsSinceEpoch}',
        'type': 'custom',
        'title': 'Nova linha',
        'show': true,
        'big': false,
        'apps': <dynamic>[],
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
