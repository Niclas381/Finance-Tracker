import 'package:flutter/material.dart';

const _bg = Color(0xFF07070F);
const _cardBg = Color(0xFF110F22);
const _active = Color(0xFF9D7FFF);
const _headerColor = Color(0xFFD0C8FF);
const _timeColor = Color(0xFF5A5580);
const _dividerColor = Color(0xFF1E1B38);
const _mutedColor = Color(0xFF3D3860);

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _monthNamesShort = [
  'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
  'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
];

class DayView extends StatefulWidget {
  const DayView({super.key, required this.date});

  final DateTime date;

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  int _startHour = 6;
  int _endHour = 22;
  int _intervalMinutes = 60;

  static const double _slotHeight = 64;

  List<DateTime> _buildSlots() {
    final d = widget.date;
    final slots = <DateTime>[];
    var t = DateTime(d.year, d.month, d.day, _startHour);
    final end = DateTime(d.year, d.month, d.day, _endHour);
    while (!t.isAfter(end)) {
      slots.add(t);
      t = t.add(Duration(minutes: _intervalMinutes));
    }
    return slots;
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _dateLabel() {
    final d = widget.date;
    final wd = _weekdays[d.weekday - 1];
    final mo = _monthNamesShort[d.month - 1];
    return '$wd, ${d.day}. $mo ${d.year}';
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
        onChanged: (s, e, iv) =>
            setState(() {
              _startHour = s;
              _endHour = e;
              _intervalMinutes = iv;
            }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = _buildSlots();

    return Container(
      color: _bg,
      child: Column(
        children: [
          // ── Date header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dateLabel(),
                    style: const TextStyle(
                      color: _headerColor,
                      fontSize: 16,
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

          // ── Time grid ─────────────────────────────────────────────────────
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
                          width: 56,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2, right: 8),
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
                        // Divider + empty event area
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                height: 1,
                                color: _dividerColor,
                                margin: const EdgeInsets.only(right: 16),
                              ),
                            ],
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

  String _hourLabel(int h) =>
      '${h.toString().padLeft(2, '0')}:00';

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
          // Handle
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

          // Start hour
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

          // End hour
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

          // Interval chips
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
                          ? const Color(0xFF221E45)
                          : const Color(0xFF0F0D1E),
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

          // Apply button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                widget.onChanged(_start, _end, _interval);
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF221E45),
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
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
