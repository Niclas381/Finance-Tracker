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
// Selected tab + panel share this colour so they look like one shape.
const _panelBg = Color(0xFF242424);
const _tabInactiveBg = Color(0xFF1A1A1A);

// Intrinsic height of the bar row (nav button + outer vertical padding),
// excluding the device's bottom safe-area inset. The body reserves this much
// space so the views' size never changes when the bar expands.
const double _kBarRowHeight = 70.0;
const double _kTabHeight = 42.0;
// ─────────────────────────────────────────────────────────────────────────────

enum _CalView { day, week, month }

enum _AddTab { termin, todo }

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
  bool _addExpanded = false;

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

  void _toggleAdd() {
    setState(() => _addExpanded = !_addExpanded);
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
            children: [
              // Calendar views always occupy the same region — from the top
              // of the safe area down to the top edge of the collapsed bar.
              // The bar grows upward over this region when expanded, instead
              // of pushing the views.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: _kBarRowHeight +
                    MediaQuery.of(context).padding.bottom,
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
              // Tap-outside-to-close barrier. Sits above the views and
              // below the bar in z-order — the bar still receives its own
              // taps because it's the last child in the Stack.
              if (_addExpanded)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleAdd,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomBar(
                  view: _current,
                  expanded: _addExpanded,
                  onBack: () => Navigator.of(context).pop(),
                  onViewChanged: _switchView,
                  onAdd: _toggleAdd,
                  onDismiss: _addExpanded ? _toggleAdd : null,
                ),
              ),
            ],
          ),
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
class _BottomBar extends StatefulWidget {
  const _BottomBar({
    required this.view,
    required this.expanded,
    required this.onBack,
    required this.onViewChanged,
    required this.onAdd,
    required this.onDismiss,
  });

  final _CalView view;
  final bool expanded;
  final VoidCallback onBack;
  final ValueChanged<_CalView> onViewChanged;
  final VoidCallback onAdd;
  // Called when the user pulls the expanded panel down past the threshold.
  // Null when the bar is collapsed.
  final VoidCallback? onDismiss;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  // Cumulative downward drag distance during an active drag.
  // setState'd on update so the panel follows the finger.
  double _dragDy = 0;
  _AddTab _activeTab = _AddTab.termin;

  void _onDragStart(DragStartDetails _) {
    setState(() => _dragDy = 0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragDy = (_dragDy + d.delta.dy).clamp(0.0, double.infinity);
    });
  }

  void _onDragEnd(DragEndDetails d, double panelFullHeight) {
    final v = d.primaryVelocity ?? 0;
    final shouldClose = _dragDy > panelFullHeight * 0.25 || v > 250;
    _dragDy = 0;
    if (shouldClose) {
      widget.onDismiss?.call();
    } else {
      setState(() {}); // snap back to full height
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final panelFullHeight = MediaQuery.sizeOf(context).height * 0.5;
    final panelHeight =
        (panelFullHeight - _dragDy).clamp(0.0, panelFullHeight);
    final isDragging = _dragDy > 0;

    return AnimatedSize(
      // No animation while dragging — the panel needs to track the finger 1:1.
      duration: isDragging
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.bottomCenter,
      child: Container(
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
        padding: EdgeInsets.fromLTRB(16, 16, 16, 10 + bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.expanded)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: (d) => _onDragEnd(d, panelFullHeight),
                child: SizedBox(
                  height: panelHeight,
                  width: double.infinity,
                  // Inner content stays at full size; ClipRect handles the
                  // shrinking SizedBox while the user drags down. Aligning
                  // the content to the BOTTOM keeps the tabs (which sit just
                  // above the bar row) visible the longest as the user drags.
                  child: ClipRect(
                    child: OverflowBox(
                      minHeight: 0,
                      maxHeight: panelFullHeight,
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        children: [
                          // Light grey panel takes the upper portion.
                          const Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _panelBg,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                ),
                              ),
                              child: SizedBox.expand(),
                            ),
                          ),
                          // Tabs sit at the bottom of the expanded area so
                          // they're within thumb reach.
                          SizedBox(
                            height: _kTabHeight,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _PanelTab(
                                    label: 'Termin',
                                    selected: _activeTab == _AddTab.termin,
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(16),
                                    ),
                                    onTap: () => setState(
                                        () => _activeTab = _AddTab.termin),
                                  ),
                                ),
                                Expanded(
                                  child: _PanelTab(
                                    label: 'ToDo',
                                    selected: _activeTab == _AddTab.todo,
                                    borderRadius: const BorderRadius.only(
                                      bottomRight: Radius.circular(16),
                                    ),
                                    onTap: () => setState(
                                        () => _activeTab = _AddTab.todo),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Gap between the expanded area and the bar row icons.
            if (widget.expanded) const SizedBox(height: 10),
            Row(
              children: [
                _IconChip(
                  icon: Icons.arrow_back_rounded,
                  onTap: widget.onBack,
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
                          selected: widget.view == _CalView.day,
                          onTap: () => widget.onViewChanged(_CalView.day),
                        ),
                        const SizedBox(width: 6),
                        _NavButton(
                          icon: Icons.view_week_rounded,
                          label: 'Woche',
                          selected: widget.view == _CalView.week,
                          onTap: () => widget.onViewChanged(_CalView.week),
                        ),
                        const SizedBox(width: 6),
                        _NavButton(
                          icon: Icons.calendar_month_rounded,
                          label: 'Monat',
                          selected: widget.view == _CalView.month,
                          onTap: () => widget.onViewChanged(_CalView.month),
                        ),
                      ],
                    ),
                  ),
                ),
                _IconChip(
                  icon: widget.expanded
                      ? Icons.close_rounded
                      : Icons.add_rounded,
                  onTap: widget.onAdd,
                  color: _active,
                  borderColor: _active.withValues(alpha: 0.25),
                ),
              ],
            ),
          ],
        ),
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

// ── Panel tab (Termin / ToDo) ────────────────────────────────────────────────
//
// The selected tab shares its fill colour with the panel above it and has a
// flat top, so the two read as a single continuous shape. The inactive tab
// uses a darker fill so it reads as a separate button. Only the outer-bottom
// corner of each tab is rounded — the edge where the two tabs meet stays
// square.
class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.borderRadius,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? _panelBg : _tabInactiveBg,
          borderRadius: borderRadius,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _active : _inactive,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

