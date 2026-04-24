// lib/ui/home/widgets/budget_ring.dart (oder dein entsprechender Pfad)

import 'dart:math';

import 'package:flutter/material.dart';

class BudgetRing extends StatelessWidget {
  final double monthlyBudget;
  final double spent;
  final VoidCallback onTap;
  final bool isEditing;

  const BudgetRing({
    super.key,
    required this.monthlyBudget,
    required this.spent,
    required this.onTap,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    // Positiv: noch Budget übrig
    // Negativ: Budget überzogen
    final double remaining = monthlyBudget - spent;
    final bool isOverBudget = remaining < 0;

    // Normalisiert auf -1.0 bis 1.0
    final double normalized =
        monthlyBudget > 0 ? remaining / monthlyBudget : 0.0;
    final double progress = normalized.clamp(-1.0, 1.0);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.all(isEditing ? 8 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isEditing
              ? Border.all(
                  color: Theme.of(context).colorScheme.secondary,
                  width: 2,
                )
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return CustomPaint(
                  size: const Size(300, 300),
                  painter: _RingPainter(value),
                );
              },
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${remaining.toStringAsFixed(2)} €',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isOverBudget ? Colors.redAccent : null,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'von ${monthlyBudget.toStringAsFixed(0)} €',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                if (isEditing) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tippen zum Ändern',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  /// Fortschritt im Bereich -1.0 bis 1.0
  ///
  ///  1.0  => 100 % Budget übrig (voller grüner Ring)
  ///  0.0  => genau am Budget (kein farbiger Ring)
  /// -1.0  => 100 % überzogen (voller roter Ring in Gegenrichtung)
  final double progress;

  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final double strokeWidth = 18.0;
    final double radius = min(size.width, size.height) / 2 - strokeWidth;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Paint backgroundPaint = Paint()
      ..color = const Color(0xFF303030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Fortschritt auf -1..1 begrenzen
    final double clamped = progress.clamp(-1.0, 1.0);
    final bool isNegative = clamped < 0;
    final double magnitude = clamped.abs();

    // Farben: Grün bei unter Budget, Rot bei über Budget
    final List<Color> colors = isNegative
        ? const [
            Color(0xFFFF5252), // Rot
            Color(0xFFFF8A80), // Hellrot
          ]
        : const [
            Color(0xFF4CAF50), // Grün
            Color(0xFF8BC34A), // Hellgrün
          ];

    final Paint foregroundPaint = Paint()
      ..shader = LinearGradient(
        colors: colors,
      ).createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Hintergrundkreis
    canvas.drawCircle(center, radius, backgroundPaint);

    // Nichts zeichnen, wenn magnitude == 0 (genau am Budget)
    if (magnitude <= 0) return;

    final double sweepAngle = 2 * pi * magnitude;
    const double baseStartAngle = -pi / 2; // oben (12 Uhr)

    // Bei negativem Fortschritt in die andere Richtung zeichnen
    final double startAngle =
        isNegative ? baseStartAngle - sweepAngle : baseStartAngle;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
