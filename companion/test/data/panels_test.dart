import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/data/models/panel.dart';
import 'package:couchkit_remote/data/panels_repository.dart';
import 'package:couchkit_remote/data/secure_storage_service.dart';

void main() {
  group('Panel', () {
    test('aceita URL sem esquema e rejeita lixo', () {
      expect(
        const Panel(id: '1', name: 'a', url: 'grafana.exemplo.com/d/x').uri,
        Uri.parse('https://grafana.exemplo.com/d/x'),
      );
      expect(const Panel(id: '1', name: 'a', url: '???').uri, isNull);
    });

    test('separa o cabeçalho só no primeiro dois-pontos', () {
      const panel = Panel(
        id: '1',
        name: 'a',
        url: 'x.com',
        header: 'Authorization: Bearer a:b',
      );
      expect(panel.headers, {'Authorization': 'Bearer a:b'});
      expect(const Panel(id: '1', name: 'a', url: 'x.com').headers, isEmpty);
    });
  });

  group('PanelsRepository', () {
    late PanelsRepository repository;

    setUp(() => repository = PanelsRepository(MemoryStore()));

    test('salva, edita pelo id e remove', () async {
      await repository.save(const Panel(id: '1', name: 'A', url: 'a.com'));
      await repository.save(const Panel(id: '2', name: 'B', url: 'b.com'));
      await repository.save(
        const Panel(id: '1', name: 'A2', url: 'a.com', refreshSeconds: 60),
      );

      var panels = await repository.load();
      expect(panels.map((p) => p.name), ['A2', 'B']);
      expect(panels.first.refreshSeconds, 60);

      await repository.remove('1');
      panels = await repository.load();
      expect(panels.map((p) => p.id), ['2']);
    });
  });
}
