import 'package:flutter/material.dart';

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

  // Tracks whether the user is actively scrolling the bar, so we don't
  // create a feedback loop when we programmatically scroll it from the PageView.
  bool _userScrollingBar = false;
  int _currentPage = _kInitialPage;

  static const int _kInitialPage = 1200; // ±100 years from today
  static const int _kItemCount = 2400;
  static const double _kItemWidth = 64.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _kInitialPage);
    _barController = ScrollController();
    _pageController.addListener(_onPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBarToPage());
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    _barController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) {
    final diff = page - _kInitialPage;
    return DateTime(_today.year, _today.month + diff);
  }

  void _onPageChanged() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page?.round() ?? _kInitialPage;
    if (page != _currentPage) {
      setState(() => _currentPage = page);
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
    _pageController.animateToPage(
      page.clamp(0, _kItemCount - 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  bool _isToday(DateTime? d) =>
      d != null &&
      d.year == _today.year &&
      d.month == _today.month &&
      d.day == _today.day;

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

  List<List<DateTime?>> _computeGrid(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startPad = firstDay.weekday - 1;

    final cells = <DateTime?>[
      ...List.filled(startPad, null),
      for (int d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) { cells.add(null); }

    return [for (int i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)];
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
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _goToPage(index),
                        child: _BarChip(
                          month: month,
                          isSelected: index == _currentPage,
                          isCurrentMonth:
                              month.year == _today.year && month.month == _today.month,
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
              itemCount: _kItemCount,
              itemBuilder: (context, index) {
                final month = _monthForPage(index);
                final grid = _computeGrid(month);
                return Padding(
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
                );
              },
            ),
          ),

          const SizedBox(height: 8),
        ],
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
                : Border.all(color: Colors.white.withValues(alpha: 0.04), width: 1),
          ),
          child: Center(
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
      ),
    );
  }
}
