import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ResourceGraph extends StatelessWidget {
  final List<double> history;
  final String label;
  final String currentValue;
  final Color color;
  final double maxVal;
  final String unit;

  const ResourceGraph({
    super.key,
    required this.history,
    required this.label,
    required this.currentValue,
    required this.color,
    this.maxVal = 100.0,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.03),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                textBaseline: TextBaseline.alphabetic,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                children: [
                  Text(
                    currentValue,
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    unit,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _GraphPainter(
                  history: history,
                  color: color,
                  maxVal: maxVal,
                ),
                child: Container(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<double> history;
  final Color color;
  final double maxVal;

  _GraphPainter({
    required this.history,
    required this.color,
    required this.maxVal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final paintLine = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true;

    final double width = size.width;
    final double height = size.height;

    // Draw grid lines (horizontal 25%, 50%, 75%)
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      final double y = height * (i * 0.25);
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    final int maxPoints = history.length;
    if (maxPoints < 2) return;

    final double stepX = width / (maxPoints - 1);

    final path = Path();
    final fillPath = Path();

    // Map points to canvas coordinates
    Offset getOffset(int index, double val) {
      final double x = index * stepX;
      // Clamp to ensure it doesn't draw outside the bounding box
      final double normalizedVal = val.clamp(0.0, maxVal);
      final double y = height - (normalizedVal / maxVal) * height;
      return Offset(x, y);
    }

    final firstOffset = getOffset(0, history.first);
    path.moveTo(firstOffset.dx, firstOffset.dy);
    fillPath.moveTo(firstOffset.dx, height);
    fillPath.lineTo(firstOffset.dx, firstOffset.dy);

    for (int i = 1; i < history.length; i++) {
      final offset = getOffset(i, history[i]);
      path.lineTo(offset.dx, offset.dy);
      fillPath.lineTo(offset.dx, offset.dy);
    }

    fillPath.lineTo(getOffset(history.length - 1, history.last).dx, height);
    fillPath.close();

    // Paint the filled area with a gradient
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, height),
        [
          color.withOpacity(0.22),
          color.withOpacity(0.0),
        ],
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paintLine);

    // Draw a small glowing point at the last position
    final lastIndex = history.length - 1;
    final lastOffset = getOffset(lastIndex, history.last);

    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawCircle(lastOffset, 6.0, glowPaint);

    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(lastOffset, 2.5, pointPaint);
    canvas.drawCircle(lastOffset, 4.0, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    // Only repaint if history has changed or properties changed
    if (oldDelegate.color != color || oldDelegate.maxVal != maxVal || oldDelegate.history.length != history.length) {
      return true;
    }
    // Deep check
    for (int i = 0; i < history.length; i++) {
      if (oldDelegate.history[i] != history[i]) return true;
    }
    return false;
  }
}
