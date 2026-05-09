import 'package:flutter/material.dart';

const _bg = Color(0xFF0A0A0A);
const _cardBg = Color(0xFF141414);
const _active = Color(0xFFFFFFFF);
const _headerColor = Color(0xFFFFFFFF);
const _timeColor = Color(0xFF606060);
const _dividerColor = Color(0xFF222222);
const _mutedColor = Color(0xFF505050);

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _monthNamesShort = [
  'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
  'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
];

class WeekView extends StatefulWidget {
  const WeekView({super.key, required this.date});

  final DateTime date;

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _startHour = 6;
  int _endHour = 22;
  int _intervalMinutes = 60;

  static const double _slotHeight = 64;
  static const double _timeColWidth = 56;
  static const double _dayHeaderHeight = 52;

  DateTime get _monday {
    final d = widget.date;
    return DateTime(d.year, d.month, d.day)
        .subtract(Duration(days: d.weekday - 1));
  }

  List<DateTime> get _weekDays =>
      List.generate(7, (i) => _monday.add(Duration(days: i)));

  List<DateTime> _buildSlots() {
    final slots = <DateTime>[];
    var t = DateTime(2000, 1, 1, _startHour);
    final end = DateTime(2000, 1, 1, _endHour);
    while (!t.isAfter(end)) {
      slots.add(t);
      t = t.add(Duration(minutes: _intervalMinutes));
    }
    return slots;
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _isoWeek(DateTime d) {
    final thursday = d.add(Duration(days: 4 - d.weekday));
    final yearStart = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(yearStart).inDays) / 7).floor() + 1;
  }

  String _weekLabel() {
    final days = _weekDays;
    final mon = days.first;
    final sun = days.last;
    final kw = _isoWeek(mon);
    if (mon.month == sun.month) {
      return 'KW $kw  ${mon.day}. – ${sun.day}. ${_monthNamesShort[mon.month - 1]} ${mon.year}';
    }
    return 'KW $kw  ${mon.day}. ${_monthNamesShort[mon.month - 1]} – ${sun.day}. ${_monthNamesShort[sun.month - 1]} ${sun.year}';
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _isSelected(DateTime d) {
    final s = widget.date;
    return d.year == s.year && d.month == s.month && d.day == s.day;
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(
        startHour: _startHour,
        endHour: _endHour,
        intervalMinutes: _intervalMinutes,
        onChanged: (s, e, iv) => setState(() {
          _startHour = s;
          _endHour = e;
          _intervalMinutes = iv;
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final slots = _buildSlots();
    final days = _weekDays;

    return Container(
      color: _bg,
      child: Column(
        children: [
          // ── Week label + settings ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _weekLabel(),
                    style: const TextStyle(
                      color: _headerColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _openSettings,
                  tooltip: 'Anzeigeoptionen',
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: _mutedColor,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // ── Fixed day-of-week header ───────────────────────────────────────
          Container(
            height: _dayHeaderHeight,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _dividerColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: _timeColWidth),
                ...List.generate(7, (i) {
                  final day = days[i];
                  final today = _isToday(day);
                  final selected = _isSelected(day);
                  final highlight = today || selected;
                  return Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(
                              color: _dividerColor, width: 0.5),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekdays[i],
                            style: TextStyle(
                              color: highlight ? _active : _timeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: today
                                ? const BoxDecoration(
                                    color: _active,
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Center(
                              child: Text(
                                '${day.day}',
                                style: TextStyle(
                                  color: today
                                      ? _bg
                                      : (selected ? _active : _mutedColor),
                                  fontSize: 13,
                                  fontWeight: highlight
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // ── Scrollable time grid ───────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: slots.map((slot) {
                  return SizedBox(
                    height: _slotHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Time label
                        SizedBox(
                          width: _timeColWidth,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(top: 2, right: 8),
                            child: Text(
                              _fmt(slot),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: _timeColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                        // 7 day cells
                        ...List.generate(
                          7,
                          (i) => Expanded(
                            child: Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                      color: _dividerColor, width: 1),
                                  left: BorderSide(
                                      color: _dividerColor, width: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings bottom sheet ────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.startHour,
    required this.endHour,
    required this.intervalMinutes,
    required this.onChanged,
  });

  final int startHour;
  final int endHour;
  final int intervalMinutes;
  final void Function(int start, int end, int interval) onChanged;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late int _start;
  late int _end;
  late int _interval;

  @override
  void initState() {
    super.initState();
    _start = widget.startHour;
    _end = widget.endHour;
    _interval = widget.intervalMinutes;
  }

  String _hourLabel(int h) => '${h.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _mutedColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Anzeigeoptionen',
            style: TextStyle(
              color: _headerColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),

          const _Label('Von'),
          const SizedBox(height: 8),
          _HourSlider(
            value: _start,
            min: 0,
            max: _end - 1,
            onChanged: (v) => setState(() => _start = v),
            label: _hourLabel(_start),
          ),
          const SizedBox(height: 20),

          const _Label('Bis'),
          const SizedBox(height: 8),
          _HourSlider(
            value: _end,
            min: _start + 1,
            max: 24,
            onChanged: (v) => setState(() => _end = v),
            label: _hourLabel(_end),
          ),
          const SizedBox(height: 24),

          const _Label('Zeitabstand'),
          const SizedBox(height: 10),
          Row(
            children: [15, 30, 60].map((iv) {
              final selected = _interval == iv;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => setState(() => _interval = iv),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? _active.withValues(alpha: 0.5)
                            : _dividerColor,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      iv == 60 ? '1 h' : '$iv min',
                      style: TextStyle(
                        color: selected ? _active : _timeColor,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                widget.onChanged(_start, _end, _interval);
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: _active,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                      color: _active.withValues(alpha: 0.4), width: 1),
                ),
              ),
              child: const Text(
                'Übernehmen',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _timeColor,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _HourSlider extends StatelessWidget {
  const _HourSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.label,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              color: _active,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _active.withValues(alpha: 0.7),
              inactiveTrackColor: _dividerColor,
              thumbColor: _active,
              overlayColor: _active.withValues(alpha: 0.15),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
      ],
    );
  }
}
