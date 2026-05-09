import 'package:flutter/material.dart';
import '../../finance_tracker/data/receipt_dao.dart';

const _bg = Color(0xFF0A0A0A);
const _cardBg = Color(0xFF141414);
const _active = Color(0xFFFFFFFF);
const _activeBg = Color(0xFF242424);
const _dayColor = Color(0xFFCCCCCC);
const _mutedColor = Color(0xFF505050);

const _weekdayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

const _monthsShort = [
  'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
  'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez',
];

// File-level spending cache. Persists for the lifetime of the isolate so the
// data survives navigating away from and back to the calendar.
// Pages read from this synchronously in initState and only setState themselves
// (not the parent) when an async load completes — avoids any parent rebuild.
final Map<int, Map<int, double>> _dailyTotalsCache = {};
final Map<int, Future<Map<int, double>>> _dailyTotalsInFlight = {};

Future<Map<int, double>> _loadDailyTotals(int pageIndex, DateTime month) {
  final cached = _dailyTotalsCache[pageIndex];
  if (cached != null) return Future.value(cached);
  return _dailyTotalsInFlight.putIfAbsent(pageIndex, () async {
    final totals = await ReceiptDao().getDailyTotalsInMonth(month);
    _dailyTotalsCache[pageIndex] = totals;
    _dailyTotalsInFlight.remove(pageIndex);
    return totals;
  });
}

class MonthView extends StatefulWidget {
  const MonthView({super.key, required this.onDayTapped});

  final ValueChanged<DateTime> onDayTapped;

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final DateTime _today = DateTime.now();
  late final PageController _pageController;
  late final ScrollController _barController;

  bool _userScrollingBar = false;
  // ValueNotifier instead of plain int + setState — only widgets that
  // explicitly listen (the bar chips) rebuild on page change. The PageView
  // and parent widget tree stay untouched, eliminating the mid-swipe rebuild.
  late final ValueNotifier<int> _currentPage;

  static const int _kInitialPage = 1200; // ±100 years from today
  static const int _kItemCount = 2400;
  static const double _kItemWidth = 64.0;

  @override
  void initState() {
    super.initState();
    _currentPage = ValueNotifier<int>(_kInitialPage);
    _pageController = PageController(initialPage: _kInitialPage);
    _barController = ScrollController();
    _pageController.addListener(_onPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncBarToPage();
      _preloadSpending(_kInitialPage);
    });
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    _barController.dispose();
    _currentPage.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) {
    final diff = page - _kInitialPage;
    return DateTime(_today.year, _today.month + diff);
  }

  void _preloadSpending(int center) {
    for (final p in [center - 1, center, center + 1]) {
      if (p < 0 || p >= _kItemCount) continue;
      _loadDailyTotals(p, _monthForPage(p)); // fire and forget — fills cache
    }
  }

  void _onPageChanged() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page?.round() ?? _kInitialPage;
    if (page != _currentPage.value) {
      _currentPage.value = page; // notifier — no parent rebuild
      _preloadSpending(page);
    }
    // Don't reposition the bar while the user is browsing it.
    if (!_userScrollingBar) {
      _syncBarToPage();
    }
  }

  void _syncBarToPage() {
    if (!_barController.hasClients || !_pageController.hasClients) return;
    final page = _pageController.page ?? _kInitialPage.toDouble();
    final vw = _barController.position.viewportDimension;
    final target = (_kItemWidth * page - vw / 2 + _kItemWidth / 2).clamp(
      _barController.position.minScrollExtent,
      _barController.position.maxScrollExtent,
    );
    _barController.jumpTo(target);
  }

  void _goToPage(int page) {
    final clamped = page.clamp(0, _kItemCount - 1);
    // For large jumps use jumpToPage so the PageView doesn't animate through
    // all intermediate months, which would build a widget + fire a DB query
    // for every month in between.
    if ((clamped - _currentPage.value).abs() > 1) {
      _pageController.jumpToPage(clamped);
    } else {
      _pageController.animateToPage(
        clamped,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  /// Returns (year, x) pairs for the sticky year labels rendered over the bar.
  ///
  /// Logic per year Y (January chip at rawX = janPage * itemWidth - offset):
  ///   stickyX = max(0, rawX)              ← pin to left edge once January passes
  ///   stickyX = min(stickyX, nextStickyX - itemWidth)  ← pushed off by next year
  List<({int year, double x})> _computeYearLabels() {
    if (!_barController.hasClients) return [];
    final offset = _barController.offset;
    final vw = _barController.position.viewportDimension;

    // One extra year on each side so the push transition starts before the
    // label is visible and so the stuck label is always found.
    final leftPage = (offset / _kItemWidth).floor();
    final rightPage = ((offset + vw) / _kItemWidth).ceil();
    final startYear = _monthForPage(leftPage - 1).year;
    final endYear = _monthForPage(rightPage + 13).year; // +13: buffer for next Jan

    // Raw X of each year's January chip left edge relative to the viewport.
    final rawX = <int, double>{};
    for (int y = startYear; y <= endYear; y++) {
      final diff = (y - _today.year) * 12 + (1 - _today.month);
      final janPage = (_kInitialPage + diff).clamp(0, _kItemCount - 1);
      rawX[y] = janPage * _kItemWidth - offset;
    }

    final years = rawX.keys.toList()..sort();
    final result = <({int year, double x})>[];

    for (int i = 0; i < years.length; i++) {
      final y = years[i];
      double x = rawX[y]! < 0 ? 0.0 : rawX[y]!; // sticky

      // Push: prevent overlapping the label of the following year.
      if (i + 1 < years.length) {
        final nextRaw = rawX[years[i + 1]]!;
        final nextSticky = nextRaw < 0 ? 0.0 : nextRaw;
        x = x < nextSticky - _kItemWidth ? x : nextSticky - _kItemWidth;
      }

      // Skip labels that are fully off-screen in either direction.
      if (rawX[y]! > vw + _kItemWidth) continue;
      if (x < -_kItemWidth) continue;

      result.add((year: y, x: x));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      color: _bg,
      child: Column(
        children: [
          // ── Month scroll bar ──────────────────────────────────────────────
          SizedBox(
            height: 58,
            child: Stack(
              children: [
                // Scrollable month chips (no year labels — handled by overlay).
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollStartNotification && n.dragDetails != null) {
                      _userScrollingBar = true;
                    } else if (n is ScrollEndNotification) {
                      _userScrollingBar = false;
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _barController,
                    scrollDirection: Axis.horizontal,
                    itemCount: _kItemCount,
                    itemExtent: _kItemWidth,
                    itemBuilder: (context, index) {
                      final month = _monthForPage(index);
                      final isCurrentMonth =
                          month.year == _today.year && month.month == _today.month;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _goToPage(index),
                        child: ValueListenableBuilder<int>(
                          valueListenable: _currentPage,
                          builder: (context, current, _) => _BarChip(
                            month: month,
                            isSelected: index == current,
                            isCurrentMonth: isCurrentMonth,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Sticky year labels — positioned per frame above the chips.
                AnimatedBuilder(
                  animation: _barController,
                  builder: (context, _) {
                    final labels = _computeYearLabels();
                    return Stack(
                      children: labels.map((e) {
                        return Positioned(
                          left: e.x,
                          top: 2,
                          width: _kItemWidth,
                          height: 16,
                          child: Center(
                            child: Text(
                              '${e.year}',
                              style: const TextStyle(
                                color: _mutedColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          // ── Weekday labels ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: _weekdayLabels
                  .map((l) => Expanded(
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
                      ))
                  .toList(),
            ),
          ),

          const SizedBox(height: 6),

          // ── Swipeable month grid ──────────────────────────────────────────
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const _SnappyPagePhysics(),
              itemCount: _kItemCount,
              itemBuilder: (context, index) => _MonthGridPage(
                pageIndex: index,
                month: _monthForPage(index),
                today: _today,
                onDayTapped: widget.onDayTapped,
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Month grid page ───────────────────────────────────────────────────────────

class _MonthGridPage extends StatefulWidget {
  const _MonthGridPage({
    required this.pageIndex,
    required this.month,
    required this.today,
    required this.onDayTapped,
  });

  final int pageIndex;
  final DateTime month;
  final DateTime today;
  final ValueChanged<DateTime> onDayTapped;

  @override
  State<_MonthGridPage> createState() => _MonthGridPageState();
}

class _MonthGridPageState extends State<_MonthGridPage> {
  // Grid structure never changes for a given month — compute once in initState.
  late final List<List<DateTime?>> _grid;
  // Synchronously taken from the cache when possible; only set via setState
  // (on this page only, not the parent) when an async load completes.
  Map<int, double>? _totals;

  @override
  void initState() {
    super.initState();
    _grid = _buildGrid();

    final cached = _dailyTotalsCache[widget.pageIndex];
    if (cached != null) {
      _totals = cached; // synchronous fast path — most common case after preload
    } else {
      _loadDailyTotals(widget.pageIndex, widget.month).then((totals) {
        if (mounted) setState(() => _totals = totals);
      });
    }
  }

  List<List<DateTime?>> _buildGrid() {
    final m = widget.month;
    final firstDay = DateTime(m.year, m.month, 1);
    final daysInMonth = DateTime(m.year, m.month + 1, 0).day;
    final startPad = firstDay.weekday - 1;

    final cells = <DateTime?>[
      ...List.filled(startPad, null),
      for (int d = 1; d <= daysInMonth; d++) DateTime(m.year, m.month, d),
    ];
    while (cells.length % 7 != 0) { cells.add(null); }

    return [for (int i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)];
  }

  bool _isToday(DateTime? d) {
    final t = widget.today;
    return d != null && d.year == t.year && d.month == t.month && d.day == t.day;
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals ?? {};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: _grid.map((week) {
          return Expanded(
            child: Row(
              children: week.map((day) {
                return Expanded(
                  child: _DayCell(
                    day: day,
                    isToday: _isToday(day),
                    spending: day != null ? totals[day.day] : null,
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
    );
  }
}

// ── Bar chip ─────────────────────────────────────────────────────────────────

class _BarChip extends StatelessWidget {
  const _BarChip({
    required this.month,
    required this.isSelected,
    required this.isCurrentMonth,
  });

  final DateTime month;
  final bool isSelected;
  final bool isCurrentMonth;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 16 px reserved at top so chips stay vertically aligned with the
        // sticky year-label overlay rendered by the parent Stack.
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          height: 32,
          decoration: BoxDecoration(
            color: isSelected ? _activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? _active.withValues(alpha: 0.4)
                  : isCurrentMonth
                      ? _active.withValues(alpha: 0.18)
                      : Colors.transparent,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            _monthsShort[month.month - 1],
            style: TextStyle(
              color: isSelected
                  ? _active
                  : isCurrentMonth
                      ? _active.withValues(alpha: 0.6)
                      : _mutedColor,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Day cell ──────────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  const _DayCell({this.day, required this.isToday, this.onTap, this.spending});
  final DateTime? day;
  final bool isToday;
  final VoidCallback? onTap;
  final double? spending;

  String? get _spendingLabel {
    if (spending == null || spending! < 0.5) return null;
    final v = spending!;
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1).replaceAll('.', ',')}k€';
    final rounded = v.round();
    return '$rounded€';
  }

  @override
  Widget build(BuildContext context) {
    if (day == null) return const SizedBox.expand();

    final label = _spendingLabel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isToday ? _activeBg : _cardBg.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: isToday
                ? Border.all(color: _active.withValues(alpha: 0.6), width: 1.5)
                : Border.all(color: Colors.white.withValues(alpha: 0.04), width: 1),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${day!.day}',
                    style: TextStyle(
                      color: isToday ? _active : _dayColor,
                      fontSize: 14,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
              if (label != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: _mutedColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Snappy page physics ──────────────────────────────────────────────────────
// Default PageScrollPhysics commits to the next page only after dragging past
// 50% of the viewport (or with a hard flick). This variant lowers the drag
// threshold to 15%, so a small swipe is enough — velocity-based commits still
// behave the same.
class _SnappyPagePhysics extends PageScrollPhysics {
  const _SnappyPagePhysics({super.parent});

  // 3% base drag distance commits. With even a touch of velocity in the drag
  // direction, this drops further — see thresholdFor below.
  static const double _threshold = 0.03;

  // Snappier spring than the Flutter default — pages slide into place with
  // less overshoot and feel more responsive after a flick.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 0.3,
    stiffness: 150,
    ratio: 1.1,
  );

  @override
  SpringDescription get spring => _spring;

  @override
  _SnappyPagePhysics applyTo(ScrollPhysics? ancestor) {
    return _SnappyPagePhysics(parent: buildParent(ancestor));
  }

  double _page(ScrollMetrics position) =>
      position.pixels / position.viewportDimension;

  double _pixels(ScrollMetrics position, double page) =>
      page * position.viewportDimension;

  double _target(ScrollMetrics position, Tolerance tolerance, double velocity) {
    final page = _page(position);
    final base = page.floorToDouble();
    final delta = page - base;

    // Velocity in the drag direction collapses the threshold toward zero so
    // even the tiniest flick commits. Moves like water.
    double thresholdFor(double dirVelocity) {
      if (dirVelocity <= 0) return _threshold;
      return (_threshold - dirVelocity / 1000.0).clamp(0.002, _threshold);
    }

    double snap;
    if (delta < 0.5) {
      final t = thresholdFor(velocity);
      snap = (delta < t) ? base : base + 1;
    } else {
      final backDelta = 1.0 - delta;
      final t = thresholdFor(-velocity);
      snap = (backDelta < t) ? base + 1 : base;
    }
    return _pixels(position, snap);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = _target(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
