import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'day_view.dart';
import 'month_view.dart';
import 'week_view.dart';

// ── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF0A0A0A);
const _barBg = Color(0xFF141414);
const _active = Color(0xFFFFFFFF);
const _inactive = Color(0xFF505050);
const _backIcon = Color(0xFF606060);
// ─────────────────────────────────────────────────────────────────────────────

enum _CalView { day, week, month }

class CalendarHomePage extends StatefulWidget {
  const CalendarHomePage({super.key});

  @override
  State<CalendarHomePage> createState() => _CalendarHomePageState();
}

class _CalendarHomePageState extends State<CalendarHomePage>
    with SingleTickerProviderStateMixin {
  _CalView _current = _CalView.month;
  _CalView? _previous;
  DateTime _selectedDate = DateTime.now();
  late final AnimationController _ctrl;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _previous = null);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _switchView(_CalView view) {
    if (_current == view) return;
    setState(() {
      _previous = _current;
      _current = view;
    });
    _ctrl.forward(from: 0);
  }

  void _openDay(DateTime date) {
    final needsTransition = _current != _CalView.day;
    setState(() {
      _selectedDate = date;
      if (needsTransition) {
        _previous = _current;
        _current = _CalView.day;
      }
    });
    if (needsTransition) _ctrl.forward(from: 0);
  }

  Future<void> _openAddSheet() async {
    setState(() => _sheetOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _AddSheet(),
    );
    if (mounted) setState(() => _sheetOpen = false);
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
        body: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Layer(
                view: _CalView.day,
                current: _current,
                previous: _previous,
                controller: _ctrl,
                child: DayView(date: _selectedDate),
              ),
              _Layer(
                view: _CalView.week,
                current: _current,
                previous: _previous,
                controller: _ctrl,
                child: WeekView(date: _selectedDate),
              ),
              _Layer(
                view: _CalView.month,
                current: _current,
                previous: _previous,
                controller: _ctrl,
                child: MonthView(onDayTapped: _openDay),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _BottomBar(
          view: _current,
          sheetOpen: _sheetOpen,
          onBack: () => Navigator.of(context).pop(),
          onViewChanged: _switchView,
          onAdd: _openAddSheet,
        ),
      ),
    );
  }
}

// ── One layer in the calendar stack ─────────────────────────────────────────
class _Layer extends StatelessWidget {
  const _Layer({
    required this.view,
    required this.current,
    required this.previous,
    required this.controller,
    required this.child,
  });

  final _CalView view;
  final _CalView current;
  final _CalView? previous;
  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: RepaintBoundary(child: child),
      builder: (_, hoisted) {
        final c = hoisted ?? RepaintBoundary(child: child);
        final p = previous;
        final involved = view == current || view == p;

        bool offstage;
        Offset translation = Offset.zero;
        double scale = 1.0;
        double opacity = 1.0;

        if (!involved) {
          offstage = true;
        } else if (p == null) {
          offstage = view != current;
        } else {
          offstage = false;
          final isIncoming = view == current;
          final t = Curves.easeInOutCubic.transform(controller.value);
          final params = _transitionParams(
            from: p,
            to: current,
            isIncoming: isIncoming,
            t: t,
          );
          translation = params.translation;
          scale = params.scale;
          opacity = params.opacity;
        }

        return Offstage(
          offstage: offstage,
          child: FractionalTranslation(
            translation: translation,
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: c,
              ),
            ),
          ),
        );
      },
    );
  }

  static ({Offset translation, double scale, double opacity}) _transitionParams({
    required _CalView from,
    required _CalView to,
    required bool isIncoming,
    required double t,
  }) {
    final fromI = from.index;
    final toI = to.index;
    final involves = {fromI, toI};

    if (involves.containsAll(const {0, 1})) {
      final drillIn = toI < fromI;
      final outDir = drillIn ? -1.0 : 1.0;
      if (isIncoming) {
        return (
          translation: Offset(-outDir * (1 - t) * 0.18, 0),
          scale: 1.0,
          opacity: t,
        );
      }
      return (
        translation: Offset(outDir * t * 0.18, 0),
        scale: 1.0,
        opacity: 1 - t,
      );
    }

    if (involves.containsAll(const {1, 2})) {
      final drillIn = toI < fromI;
      final outDir = drillIn ? 1.0 : -1.0;
      if (isIncoming) {
        return (
          translation: Offset(0, -outDir * (1 - t) * 0.18),
          scale: 1.0,
          opacity: t,
        );
      }
      return (
        translation: Offset(0, outDir * t * 0.18),
        scale: 1.0,
        opacity: 1 - t,
      );
    }

    final drillIn = toI < fromI;
    if (isIncoming) {
      final start = drillIn ? 0.7 : 1.3;
      return (
        translation: Offset.zero,
        scale: start + (1.0 - start) * t,
        opacity: t,
      );
    }
    final end = drillIn ? 1.3 : 0.7;
    return (
      translation: Offset.zero,
      scale: 1.0 + (end - 1.0) * t,
      opacity: 1 - t,
    );
  }
}

// ── Bottom bar ───────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.view,
    required this.sheetOpen,
    required this.onBack,
    required this.onViewChanged,
    required this.onAdd,
  });

  final _CalView view;
  final bool sheetOpen;
  final VoidCallback onBack;
  final ValueChanged<_CalView> onViewChanged;
  final VoidCallback onAdd;

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
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomPad),
      child: Row(
        children: [
          _IconChip(
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
            color: _backIcon,
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NavButton(
                    icon: Icons.view_day_rounded,
                    label: 'Tag',
                    selected: view == _CalView.day,
                    onTap: () => onViewChanged(_CalView.day),
                  ),
                  const SizedBox(width: 6),
                  _NavButton(
                    icon: Icons.view_week_rounded,
                    label: 'Woche',
                    selected: view == _CalView.week,
                    onTap: () => onViewChanged(_CalView.week),
                  ),
                  const SizedBox(width: 6),
                  _NavButton(
                    icon: Icons.calendar_month_rounded,
                    label: 'Monat',
                    selected: view == _CalView.month,
                    onTap: () => onViewChanged(_CalView.month),
                  ),
                ],
              ),
            ),
          ),
          AnimatedScale(
            duration: const Duration(milliseconds: 200),
            scale: sheetOpen ? 0.0 : 1.0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: sheetOpen ? 0.0 : 1.0,
              child: _IconChip(
                icon: Icons.add_rounded,
                onTap: onAdd,
                color: _active,
                borderColor: _active.withValues(alpha: 0.25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.onTap,
    required this.color,
    this.borderColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(14),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 1)
                : null,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF242424) : Colors.transparent,
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

// ── Add sheet ────────────────────────────────────────────────────────────────

class _AddSheet extends StatelessWidget {
  const _AddSheet();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: _barBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _inactive,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.close_rounded,
                      color: _backIcon, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
