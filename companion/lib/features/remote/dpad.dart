import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:couchkit_remote/features/remote/remote_controller.dart';

/// Direcional circular (como o do app da Amazon): quatro setas em arco e o
/// OK no centro. Segurar uma seta repete a tecla.
class DPad extends StatefulWidget {
  const DPad({required this.onPress, super.key});

  final void Function(RemoteKey key) onPress;

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> {
  RemoteKey? _pressed;
  Timer? _repeat;

  static const _okRadius = 0.34;

  RemoteKey _zone(Offset point, double size) {
    final center = Offset(size / 2, size / 2);
    final delta = point - center;
    if (delta.distance < size / 2 * _okRadius) {
      return RemoteKey.ok;
    }
    final angle = math.atan2(delta.dy, delta.dx); // 0 = direita, pi/2 = baixo
    if (angle >= -math.pi / 4 && angle < math.pi / 4) {
      return RemoteKey.right;
    }
    if (angle >= math.pi / 4 && angle < 3 * math.pi / 4) {
      return RemoteKey.down;
    }
    if (angle >= -3 * math.pi / 4 && angle < -math.pi / 4) {
      return RemoteKey.up;
    }
    return RemoteKey.left;
  }

  void _down(Offset point, double size) {
    final key = _zone(point, size);
    setState(() => _pressed = key);
    widget.onPress(key);
    _repeat?.cancel();
    if (key != RemoteKey.ok) {
      _repeat = Timer(const Duration(milliseconds: 450), () {
        _repeat = Timer.periodic(
          const Duration(milliseconds: 160),
          (_) => widget.onPress(key),
        );
      });
    }
  }

  void _up() {
    _repeat?.cancel();
    if (_pressed != null) {
      setState(() => _pressed = null);
    }
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _down(details.localPosition, size),
            onTapUp: (_) => _up(),
            onTapCancel: _up,
            onPanStart: (details) => _down(details.localPosition, size),
            onPanEnd: (_) => _up(),
            onPanCancel: _up,
            child: Semantics(
              label: 'Direcional',
              child: CustomPaint(
                painter: _DPadPainter(
                  pressed: _pressed,
                  base: scheme.surfaceContainerHigh,
                  active: scheme.primary,
                  center: scheme.surfaceContainerHighest,
                  arrow: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DPadPainter extends CustomPainter {
  _DPadPainter({
    required this.pressed,
    required this.base,
    required this.active,
    required this.center,
    required this.arrow,
  });

  final RemoteKey? pressed;
  final Color base;
  final Color active;
  final Color center;
  final Color arrow;

  static const _sectors = {
    RemoteKey.right: 0.0,
    RemoteKey.down: math.pi / 2,
    RemoteKey.left: math.pi,
    RemoteKey.up: -math.pi / 2,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2;
    final inner = outer * 0.40;
    const half = math.pi / 4 - 0.05;
    for (final entry in _sectors.entries) {
      final mid = entry.value;
      final path = Path()
        ..arcTo(
          Rect.fromCircle(center: c, radius: outer * 0.96),
          mid - half,
          half * 2,
          true,
        )
        ..arcTo(
          Rect.fromCircle(center: c, radius: inner),
          mid + half,
          -half * 2,
          false,
        )
        ..close();
      final color = pressed == entry.key ? active : base;
      canvas
        ..drawPath(path, Paint()..color = color)
        ..drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 12
            ..strokeJoin = StrokeJoin.round,
        );
      final at = c + Offset.fromDirection(mid, outer * 0.70);
      _chevron(canvas, at, mid);
    }
    canvas.drawCircle(
      c,
      outer * 0.34,
      Paint()..color = pressed == RemoteKey.ok ? active : center,
    );
  }

  void _chevron(Canvas canvas, Offset at, double direction) {
    final tip = Offset.fromDirection(direction, 9);
    final a = Offset.fromDirection(direction + 2.4, 14);
    final b = Offset.fromDirection(direction - 2.4, 14);
    final path = Path()
      ..moveTo(at.dx + a.dx + tip.dx / 3, at.dy + a.dy + tip.dy / 3)
      ..lineTo(at.dx + tip.dx, at.dy + tip.dy)
      ..lineTo(at.dx + b.dx + tip.dx / 3, at.dy + b.dy + tip.dy / 3);
    canvas.drawPath(
      path,
      Paint()
        ..color = arrow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DPadPainter old) => old.pressed != pressed;
}
