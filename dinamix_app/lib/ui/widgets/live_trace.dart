import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Fixed-size ring of values for a live trace (no allocation per sample).
class TraceBuffer {
  TraceBuffer(this.capacity) : _v = Float64List(capacity);

  final int capacity;
  final Float64List _v;
  int _head = 0;
  int length = 0;

  void add(double value) {
    _v[_head] = value.isFinite ? value : 0;
    _head = (_head + 1) % capacity;
    if (length < capacity) length++;
  }

  double at(int i) => _v[(_head - length + i + capacity) % capacity];

  double get maxValue {
    var m = 0.0;
    for (var i = 0; i < length; i++) {
      m = math.max(m, at(i));
    }
    return m;
  }

  void clear() {
    _head = 0;
    length = 0;
  }
}

/// Compact real-time chart with an optional reference line (e.g. a provisional
/// threshold, labelled as such).
class LiveTrace extends StatelessWidget {
  const LiveTrace({
    super.key,
    required this.buffer,
    required this.color,
    required this.label,
    required this.unit,
    this.reference,
    this.referenceLabel,
    this.minRange = 1,
    this.height = 74,
    this.revision = 0,
  });

  final TraceBuffer buffer;
  final Color color;
  final String label;
  final String unit;
  final double? reference;
  final String? referenceLabel;
  final double minRange;
  final double height;

  /// Changes at every new sample, so that the painter repaints.
  final int revision;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final last = buffer.length == 0 ? 0.0 : buffer.at(buffer.length - 1);
    return Semantics(
      label: '$label ${last.toStringAsFixed(2)} $unit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${last.toStringAsFixed(last.abs() >= 100 ? 0 : 2)} $unit',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: height,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _TracePainter(buffer, color, reference, referenceLabel, minRange, revision, muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.b, this.color, this.reference, this.referenceLabel, this.minRange, this.revision, this.muted);

  final TraceBuffer b;
  final Color color;
  final double? reference;
  final String? referenceLabel;
  final double minRange;
  final int revision;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = muted.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final top = math.max(minRange, math.max(b.maxValue, reference ?? 0) * 1.15);
    double y(double v) => size.height - (v / top).clamp(0, 1) * size.height;
    if (reference != null) {
      final ry = y(reference!);
      final dash = Paint()
        ..color = muted.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, ry), Offset(x + 4, ry), dash);
      }
      if (referenceLabel != null) {
        final tp = TextPainter(
          text: TextSpan(text: referenceLabel, style: TextStyle(color: muted, fontSize: 9.5)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width - 2, math.max(0, ry - tp.height - 1)));
      }
    }
    if (b.length < 2) return;
    final path = Path();
    for (var i = 0; i < b.length; i++) {
      final x = size.width * i / (b.capacity - 1);
      final p = Offset(x, y(b.at(i)));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width * (b.length - 1) / (b.capacity - 1), size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _TracePainter old) => old.revision != revision || old.color != color;
}
