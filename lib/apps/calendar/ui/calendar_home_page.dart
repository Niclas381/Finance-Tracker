import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'day_view.dart';
import 'month_view.dart';
import 'week_view.dart';

// ── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF07070F);
const _barBg = Color(0xFF110F22);
const _active = Color(0xFF9D7FFF);
const _inactive = Color(0xFF3D3860);
const _backIcon = Color(0xFF5C5880);
// ─────────────────────────────────────────────────────────────────────────────

enum _CalView { day, week, month }

class CalendarHomePage extends StatefulWidget {
  const CalendarHomePage({super.key});

  @override
  State<CalendarHomePage> createState() => _CalendarHomePageState();
}

class _CalendarHomePageState extends State<CalendarHomePage> {
  _CalView _view = _CalView.month;
  DateTime _selectedDate = DateTime.now();

  void _openDay(DateTime date) {
    setState(() {
      _selectedDate = date;
      _view = _CalView.day;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: _barBg,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Kalender',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        body: IndexedStack(
          index: _view.index,
          children: [
            DayView(date: _selectedDate),
            const WeekView(),
            MonthView(onDayTapped: _openDay),
          ],
        ),
        bottomNavigationBar: _BottomBar(
          view: _view,
          onBack: () => Navigator.of(context).pop(),
          onViewChanged: (v) => setState(() => _view = v),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.view,
    required this.onBack,
    required this.onViewChanged,
  });

  final _CalView view;
  final VoidCallback onBack;
  final ValueChanged<_CalView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: _barBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 10 + bottomPad),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1A35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: _backIcon, size: 22),
              ),
            ),
          ),
          const Spacer(),
          _NavButton(
            icon: Icons.view_day_rounded,
            label: 'Tag',
            selected: view == _CalView.day,
            onTap: () => onViewChanged(_CalView.day),
          ),
          const SizedBox(width: 20),
          _NavButton(
            icon: Icons.view_week_rounded,
            label: 'Woche',
            selected: view == _CalView.week,
            onTap: () => onViewChanged(_CalView.week),
          ),
          const SizedBox(width: 20),
          _NavButton(
            icon: Icons.calendar_month_rounded,
            label: 'Monat',
            selected: view == _CalView.month,
            onTap: () => onViewChanged(_CalView.month),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF221E45) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: _active.withValues(alpha: 0.35), width: 1)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? _active : _inactive, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? _active : _inactive,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
