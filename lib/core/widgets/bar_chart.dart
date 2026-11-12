import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Simple vertical bar chart (daily sales). Bars are labelled with their value when there is room and the whole
/// chart carries a [semanticsLabel] summary, so it is not "colour only".
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.valueFormatter,
    required this.semanticsLabel,
    this.height = 180,
  });

  final List<double> values;
  final List<String> labels;
  final String Function(double) valueFormatter;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: CustomPaint(
              painter: _BarPainter(
                values: values,
                labels: labels,
                valueFormatter: valueFormatter,
                barColor: p.isDark ? AppColors.primaryOnDark : AppColors.primary,
                textColor: p.text,
                mutedColor: p.textSecondary,
                gridColor: p.border,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.valueFormatter,
    required this.barColor,
    required this.textColor,
    required this.mutedColor,
    required this.gridColor,
  });

  final List<double> values;
  final List<String> labels;
  final String Function(double) valueFormatter;
  final Color barColor;
  final Color textColor;
  final Color mutedColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const double labelH = 18;
    const double topPad = 16;
    final double chartH = size.height - labelH - topPad;
    final double maxV = values.fold<double>(0, math.max);
    final double scale = maxV <= 0 ? 0 : chartH / maxV;
    final double slot = size.width / values.length;
    final double barW = math.min(28, slot * 0.6);

    final Paint grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, topPad + chartH), Offset(size.width, topPad + chartH), grid);

    final Paint bar = Paint()..color = barColor;
    final int labelEvery = slot < 34 ? (34 / slot).ceil() : 1;
    for (int i = 0; i < values.length; i++) {
      final double h = values[i] * scale;
      final double cx = slot * i + slot / 2;
      final double barH = values[i] > 0 ? math.max(h, 3) : 0;
      final Rect r = Rect.fromLTWH(cx - barW / 2, topPad + chartH - barH, barW, barH);
      canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: const Radius.circular(6), topRight: const Radius.circular(6)), bar);

      if (slot >= 44 && values[i] > 0) {
        _text(canvas, valueFormatter(values[i]), Offset(cx, topPad + chartH - barH - 3), textColor, 10, above: true);
      }
      if (i % labelEvery == 0 && i < labels.length) {
        _text(canvas, labels[i], Offset(cx, topPad + chartH + 3), mutedColor, 10);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset anchor, Color color, double fontSize, {bool above = false}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: fontSize, fontFamily: 'Cairo')),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double dx = anchor.dx - tp.width / 2;
    final double dy = above ? anchor.dy - tp.height : anchor.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.values != values || old.labels != labels || old.barColor != barColor || old.textColor != textColor;
}
