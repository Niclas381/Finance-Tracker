import 'package:flutter/material.dart';

/// Wiederverwendbarer Monatskalender:
/// - identisches Design wie in HistoryPage
/// - farbliche Markierung abhängig vom Tagesbudget
/// - optional markierter Tag (nur dickere Umrandung)
class MonthSpendingCalendar extends StatelessWidget {
  final DateTime month;
  final Map<int, double> spendingPerDay;
  final double perDayBudget;

  /// optional aktuell ausgewählter Tag (1..31)
  final int? selectedDay;

  /// Callback bei Tap auf einen Tag
  final void Function(int day) onDayTap;

  const MonthSpendingCalendar({
    super.key,
    required this.month,
    required this.spendingPerDay,
    required this.perDayBudget,
    this.selectedDay,
    required this.onDayTap,
  });

  Color _colorForDay(double spent, ThemeData theme) {
    if (spent <= 0 || perDayBudget <= 0) {
      return theme.colorScheme.surfaceVariant;
    }

    final ratio = (spent / perDayBudget).clamp(0.0, 1.5);

    const green = Color(0xFF4CAF50);
    const red = Color(0xFFF44336);

    if (ratio <= 0.6) {
      return green;
    } else if (ratio <= 1.0) {
      final linearT = (ratio - 0.6) / 0.4; // 0..1
      final easedT = linearT * linearT; // sanfter Übergang
      return Color.lerp(green, red, easedT)!;
    } else {
      return red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = month.year;
    final m = month.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, m);
    final firstWeekday = DateTime(year, m, 1).weekday; // 1 = Mo
    final leadingEmpty = firstWeekday - 1;
    final itemCount = leadingEmpty + daysInMonth;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wochentagsleiste – exakt wie in HistoryPage
        Row(
          children: const [
            _WeekdayLabel('Mo'),
            _WeekdayLabel('Di'),
            _WeekdayLabel('Mi'),
            _WeekdayLabel('Do'),
            _WeekdayLabel('Fr'),
            _WeekdayLabel('Sa'),
            _WeekdayLabel('So'),
          ],
        ),
        const SizedBox(height: 4),
        // Grid – Design 1:1 aus HistoryPage übernommen
        GridView.builder(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.02,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index < leadingEmpty) {
              return const SizedBox.shrink();
            }

            final day = index - leadingEmpty + 1;
            final spent = spendingPerDay[day] ?? 0.0;
            final color = _colorForDay(spent, theme);

            final isToday = DateUtils.isSameDay(
              DateTime.now(),
              DateTime(year, m, day),
            );

            final isSelected = selectedDay != null && selectedDay == day;

            // Wie im Verlauf: gleiche Farbe für Rand,
            // nur bei "heute" bzw. "selected" etwas dicker
            final borderWidth = (isSelected || isToday) ? 2.0 : 1.0;

            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onDayTap(day),
              child: Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: color,
                    width: borderWidth,
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$day',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 3),
                          Icon(
                            Icons.circle,
                            size: 5,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            '${spent.toStringAsFixed(2)} €',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[400],
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
    );
  }
}
