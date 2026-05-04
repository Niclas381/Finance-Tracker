import 'dart:math';

import 'package:flutter/material.dart';

class CategoryWheel extends StatelessWidget {
  final String label;
  final String categoryKey;
  final double spent;
  final double budget;
  final bool isEditing;

  const CategoryWheel({
    super.key,
    required this.label,
    required this.categoryKey,
    required this.spent,
    required this.budget,
    this.isEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    final progress = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      height: 170, // fixe Höhe -> alle Kacheln gleich groß
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isEditing
              ? BorderSide(
                  color: Theme.of(context).colorScheme.secondary,
                  width: 1.5,
                )
              : BorderSide.none,
        ),
        elevation: isEditing ? 4 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: progress),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedValue, _) {
                    return CustomPaint(
                      painter: _CategoryRingPainter(animatedValue),
                      child: Center(
                        child: Text(
                          '${(animatedValue * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Label
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              // Betrag
              Text(
                '${spent.toStringAsFixed(2)} / ${budget.toStringAsFixed(0)} €',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight:
                          isEditing ? FontWeight.bold : FontWeight.normal,
                      color: isEditing
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).textTheme.bodySmall?.color,
                    ),
              ),
              // Kein zusätzlicher "Tippen zum Ändern"-Text mehr,
              // der Rahmen/Farbe reicht als Hinweis im Edit-Mode.
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRingPainter extends CustomPainter {
  final double progress;
  _CategoryRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 8.0;
    final radius = min(size.width, size.height) / 2 - strokeWidth;
    final center = Offset(size.width / 2, size.height / 2);

    final backgroundPaint = Paint()
      ..color = const Color(0xFF303030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final foregroundPaint = Paint()
      ..color = const Color(0xFF4CAF50) // GRÜN (Original)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    final sweepAngle = 2 * pi * progress;
    final startAngle = -pi / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      foregroundPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CategoryRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}