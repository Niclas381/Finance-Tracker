import 'package:flutter/material.dart';

const _bg = Color(0xFF07070F);
const _cardBg = Color(0xFF110F22);
const _active = Color(0xFF9D7FFF);
const _activeBg = Color(0xFF221E45);
const _headerColor = Color(0xFFD0C8FF);
const _dayColor = Color(0xFFB0AACE);
const _mutedColor = Color(0xFF3D3860);

const _weekdayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

const _monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
  'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

class MonthView extends StatefulWidget {
  const MonthView({super.key, required this.onDayTapped});

  final ValueChanged<DateTime> onDayTapped;

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> {
  late DateTime _month;
  final DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _month = DateTime(_today.year, _today.month);
  }

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));

  void _nextMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month + 1));

  List<List<DateTime?>> _buildGrid() {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;
    final startPad = firstDay.weekday - 1; // Mon=1 → 0 empty cells

    final cells = <DateTime?>[
      ...List.filled(startPad, null),
      for (int d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];
    while (cells.length % 7 != 0) { cells.add(null); }

    return [
      for (int i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)
    ];
  }

  bool _isToday(DateTime? d) =>
      d != null &&
      d.year == _today.year &&
      d.month == _today.month &&
      d.day == _today.day;

  @override
  Widget build(BuildContext context) {
    final grid = _buildGrid();

    return Container(
      color: _bg,
      child: Column(
        children: [
          // ── Month header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                _ArrowBtn(
                  icon: Icons.chevron_left_rounded,
                  onTap: _prevMonth,
                ),
                Expanded(
                  child: Text(
                    '${_monthNames[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _headerColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                _ArrowBtn(
                  icon: Icons.chevron_right_rounded,
                  onTap: _nextMonth,
                ),
              ],
            ),
          ),

          // ── Weekday labels ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: _weekdayLabels
                  .map(
                    (l) => Expanded(
                      child: Text(
                        l,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _mutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),

          const SizedBox(height: 6),

          // ── Calendar grid ─────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: grid.map((week) {
                  return Expanded(
                    child: Row(
                      children: week.map((day) {
                        return Expanded(
                          child: _DayCell(
                            day: day,
                            isToday: _isToday(day),
                            onTap: day != null
                                ? () => widget.onDayTapped(day)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  const _ArrowBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: _mutedColor, size: 22),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({this.day, required this.isToday, this.onTap});
  final DateTime? day;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (day == null) return const SizedBox.expand();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isToday ? _activeBg : _cardBg.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: isToday
                ? Border.all(color: _active.withValues(alpha: 0.6), width: 1.5)
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.04), width: 1),
          ),
          child: Center(
            child: Text(
              '${day!.day}',
              style: TextStyle(
                color: isToday ? _active : _dayColor,
                fontSize: 14,
                fontWeight:
                    isToday ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
