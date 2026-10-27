import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couchkit_remote/features/remote/dpad.dart';
import 'package:couchkit_remote/features/remote/remote_controller.dart';

void main() {
  testWidgets('toques em cada zona viram a tecla certa', (tester) async {
    final keys = <RemoteKey>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: 300, child: DPad(onPress: keys.add)),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(DPad));
    for (final offset in const [
      Offset(0, -110),
      Offset(0, 110),
      Offset(-110, 0),
      Offset(110, 0),
      Offset(0, 0),
    ]) {
      await tester.tapAt(center + offset);
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(keys, [
      RemoteKey.up,
      RemoteKey.down,
      RemoteKey.left,
      RemoteKey.right,
      RemoteKey.ok,
    ]);
  });

  testWidgets('segurar uma seta repete a tecla', (tester) async {
    final keys = <RemoteKey>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: 300, child: DPad(onPress: keys.add)),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DPad)) + const Offset(0, 110),
    );
    await tester.pump(const Duration(milliseconds: 460));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pump();
    expect(keys.length, greaterThanOrEqualTo(3));
    expect(keys.every((k) => k == RemoteKey.down), isTrue);
  });
}
