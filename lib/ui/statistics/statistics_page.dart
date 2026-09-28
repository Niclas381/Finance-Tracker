import 'dart:math';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/receipt_dao.dart';
import '../../data/settings_dao.dart';
import '../../models/receipt_models.dart';
import '../home/widgets/category_wheel.dart';
import 'category_details_page.dart';
import 'product_ranking_page.dart';
import 'prospekt_search_page.dart';

import '../../prospekt/prospekt.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _DynamicCategoryStat {
  final String name;
  final double budget;
  final double spent;

  const _DynamicCategoryStat({
    required this.name,
    required this.budget,
    required this.spent,
  });
}

class _StatisticsPageState extends State<StatisticsPage> {
  final _receiptDao = ReceiptDao();
  final _settingsDao = SettingsDao();

  bool _isLoading = true;

  static DateTimeRange? _savedRange;

  DateTimeRange? _range;
  double _totalSpent = 0.0;
  double _finalSaved = 0.0;
  List<_SavingsPoint> _points = [];

  UserSettings? _settings;
  double _foodThisMonth = 0.0;
  double _leisureThisMonth = 0.0;
  double _fixedThisMonth = 0.0;
  List<_DynamicCategoryStat> _dynamicCategories = [];

  // --- Prospekt wiring ---
  ProspektOffersRepository? _prospektRepo; // ✅ NEU: Repo als Feld speichern
  ProspektSearchDataSource? _prospektSource;
  OffersSyncService? _prospektSync;

  // TODO: später über Settings konfigurierbar machen
  static const String _prospektBaseUrl = 'http://10.171.219.157:8000';

  @override
  void initState() {
    super.initState();
    _initDefaultRange();
    _initProspekt();
  }

  void _initProspekt() {
    final repo = ProspektOffersRepository(db: OffersDb.instance);
    _prospektRepo = repo;
    _prospektSource = LocalProspektSearchDataSource(repo);

    // _prospektSync wird nicht mehr benötigt, weil ProspektSearchPage das selbst baut.
    _prospektSync = null;
  }


  void _openProspektSearch() {
    final ds = _prospektSource;
    final repo = _prospektRepo;

    if (ds == null || repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prospekt-Datenquelle fehlt (noch nicht verdrahtet).')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProspektSearchPage(
          dataSource: ds,
          repo: repo,
        ),
      ),
    );
  }


  void _initDefaultRange() {
    if (_savedRange != null) {
      _range = _savedRange;
      _loadStats();
      return;
    }

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(start: start, end: end);
    _savedRange = _range;
    _loadStats();
  }

  Future<Map<String, double>> _calculateCategoryTotals(
    List<Receipt> allReceipts,
    DateTime now,
  ) async {
    final result = <String, double>{};

    for (final r in allReceipts) {
      if (r.isBanned) continue;

      final d = r.dateTime;
      final sameMonth = (d.year == now.year && d.month == now.month);

      if (sameMonth) {
        for (final li in r.lineItems) {
          final category = li.category ?? 'food';
          final amount = li.totalPrice;
          result[category] = (result[category] ?? 0.0) + amount;
        }
      }
    }

    return result;
  }

  Future<List<_DynamicCategoryStat>> _loadDynamicCategoriesFromSettings(
    UserSettings settings,
    DateTime now,
    Map<String, double> categoryTotals,
  ) async {
    final result = <_DynamicCategoryStat>[];
    final entries = <Map<String, dynamic>>[];

    final raw = settings.extraCategory1Name;
    if (raw != null && raw.trim().isNotEmpty && raw.trim().startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) {
              final name = (e['name'] ?? '').toString().trim();
              if (name.isEmpty) continue;
              final budgetNum = e['budget'];
              final budget = budgetNum is num ? budgetNum.toDouble() : 0.0;
              entries.add({'name': name, 'budget': budget});
            }
          }
        }
      } catch (_) {}
    }

    if (entries.isEmpty) {
      if (settings.extraCategory1Name != null && settings.extraCategory1Name!.isNotEmpty) {
        entries.add({'name': settings.extraCategory1Name!, 'budget': settings.extraCategory1Budget});
      }
      if (settings.extraCategory2Name != null && settings.extraCategory2Name!.isNotEmpty) {
        entries.add({'name': settings.extraCategory2Name!, 'budget': settings.extraCategory2Budget});
      }
      if (settings.extraCategory3Name != null && settings.extraCategory3Name!.isNotEmpty) {
        entries.add({'name': settings.extraCategory3Name!, 'budget': settings.extraCategory3Budget});
      }
    }

    for (final e in entries) {
      final name = e['name'] as String;
      final budget = (e['budget'] as num?)?.toDouble() ?? 0.0;
      final spent = categoryTotals[name] ?? 0.0;
      result.add(_DynamicCategoryStat(name: name, budget: budget, spent: spent));
    }

    return result;
  }

  Future<void> _loadStats() async {
    if (_range == null) return;

    setState(() {
      _isLoading = true;
    });

    final settings = await _settingsDao.getSettings();
    final now = DateTime.now();

    final receipts = await _receiptDao.getAllReceipts();

    for (final r in receipts) {
      await r.lineItems.load();
    }

    final start = DateUtils.dateOnly(_range!.start);
    final end = DateUtils.dateOnly(_range!.end);

    final spentByDay = <DateTime, double>{};

    for (final r in receipts) {
      if (r.isBanned) continue;

      final d = DateUtils.dateOnly(r.dateTime);
      if (!d.isBefore(start) && !d.isAfter(end)) {
        double effectiveTotal = r.total;
        if (effectiveTotal <= 0.0) {
          effectiveTotal = r.lineItems.fold<double>(0.0, (s, li) => s + li.totalPrice);
        }
        spentByDay[d] = (spentByDay[d] ?? 0.0) + effectiveTotal;
      }
    }

    double totalSpent = 0.0;
    for (final v in spentByDay.values) {
      totalSpent += v;
    }

    final points = <_SavingsPoint>[];
    double cumulativeSaved = 0.0;
    final days = end.difference(start).inDays + 1;

    for (int i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      final spent = spentByDay[day] ?? 0.0;

      final daysInMonth = DateUtils.getDaysInMonth(day.year, day.month);
      final perDayBudget = daysInMonth > 0 ? settings.monthlyBudget / daysInMonth : 0.0;

      final delta = perDayBudget - spent;
      cumulativeSaved += delta;

      points.add(
        _SavingsPoint(
          date: day,
          cumulative: cumulativeSaved,
          spent: spent,
          perDayBudget: perDayBudget,
        ),
      );
    }

    final categoryTotals = await _calculateCategoryTotals(receipts, now);

    final food = categoryTotals['food'] ?? 0.0;
    final leisure = categoryTotals['leisure'] ?? 0.0;
    final fixed = categoryTotals['fixed'] ?? 0.0;

    final dynamicCats = await _loadDynamicCategoriesFromSettings(settings, now, categoryTotals);

    if (!mounted) return;

    setState(() {
      _settings = settings;
      _totalSpent = totalSpent;
      _finalSaved = cumulativeSaved;
      _points = points;
      _foodThisMonth = food;
      _leisureThisMonth = leisure;
      _fixedThisMonth = fixed;
      _dynamicCategories = dynamicCats;
      _isLoading = false;
    });
  }

  void _setQuickRangeDays(int daysBack) {
    final now = DateUtils.dateOnly(DateTime.now());
    final start = now.subtract(Duration(days: daysBack - 1));
    final end = now;
    setState(() {
      _range = DateTimeRange(start: start, end: end);
      _savedRange = _range;
    });
    _loadStats();
  }

  void _setThisMonthRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month, now.day);
    setState(() {
      _range = DateTimeRange(start: start, end: end);
      _savedRange = _range;
    });
    _loadStats();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialRange = _range ??
        DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month, now.day),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: initialRange,
      helpText: 'Zeitraum auswählen',
    );

    if (picked == null) return;

    setState(() {
      _range = DateTimeRange(
        start: DateUtils.dateOnly(picked.start),
        end: DateUtils.dateOnly(picked.end),
      );
      _savedRange = _range;
    });

    _loadStats();
  }

  void _openProductRanking() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProductRankingPage(),
      ),
    );
  }

  void _openRangeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).padding.bottom;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Schnellauswahl',
                      style: Theme.of(sheetContext).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _pickCustomRange();
                      },
                      icon: const Icon(Icons.date_range),
                      label: const Text('Custom'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickChip(
                      label: 'Letzter Tag',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setQuickRangeDays(1);
                      },
                    ),
                    _QuickChip(
                      label: 'Letzte Woche',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setQuickRangeDays(7);
                      },
                    ),
                    _QuickChip(
                      label: 'Letzte 30 Tage',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setQuickRangeDays(30);
                      },
                    ),
                    _QuickChip(
                      label: 'Dieser Monat',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setThisMonthRange();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCategoryDetails(String key, String label) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryDetailsPage(
          categoryKey: key,
          categoryLabel: label,
        ),
      ),
    );
    await _loadStats();
  }

  Widget _buildDynamicCategoryGrid(BuildContext context) {
    if (_dynamicCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final maxWidth = constraints.maxWidth;
        final itemWidth = (maxWidth - 2 * spacing) / 3;

        final tiles = <Widget>[];

        for (final cat in _dynamicCategories) {
          tiles.add(
            SizedBox(
              width: itemWidth,
              height: 170,
              child: GestureDetector(
                onTap: () => _openCategoryDetails(cat.name, cat.name),
                child: CategoryWheel(
                  label: cat.name,
                  categoryKey: cat.name,
                  spent: cat.spent,
                  budget: cat.budget,
                  isEditing: false,
                ),
              ),
            ),
          );
        }

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final df = DateFormat('dd.MM.yyyy', 'de_DE');
    final rangeText = _range == null ? '' : '${df.format(_range!.start)} – ${df.format(_range!.end)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik'),
        actions: [
          IconButton(
            tooltip: 'Prospekt',
            onPressed: _openProspektSearch,
            icon: const Text(
              '🧾',
              style: TextStyle(fontSize: 18),
            ),
          ),
          IconButton(
            tooltip: 'Produktranking',
            onPressed: _openProductRanking,
            icon: const Text(
              '🏆',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      body: _isLoading || _settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rangeText,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _openRangeSheet,
                      icon: const Icon(Icons.date_range),
                      label: const Text('Zeitraum'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Gesamtausgaben',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_totalSpent.toStringAsFixed(2)} €',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Gespart (kumuliert)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Gesamt gespart: ${_finalSaved.toStringAsFixed(2)} €',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 240,
                  child: _SavingsChart(points: _points),
                ),
                const SizedBox(height: 20),
                Text(
                  'Nach Kategorien (aktueller Monat)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openCategoryDetails('food', 'Essen & Trinken'),
                        child: CategoryWheel(
                          label: 'Essen & Trinken',
                          categoryKey: 'food',
                          spent: _foodThisMonth,
                          budget: _settings!.foodAndDrinksBudget,
                          isEditing: false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openCategoryDetails('leisure', 'Freizeit & Hobbies'),
                        child: CategoryWheel(
                          label: 'Freizeit & Hobbies',
                          categoryKey: 'leisure',
                          spent: _leisureThisMonth,
                          budget: _settings!.leisureBudget,
                          isEditing: false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openCategoryDetails('fixed', 'Monatliche Kosten'),
                        child: CategoryWheel(
                          label: 'Monatliche Kosten',
                          categoryKey: 'fixed',
                          spent: _fixedThisMonth,
                          budget: _settings!.fixedCostsBudget,
                          isEditing: false,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildDynamicCategoryGrid(context),
              ],
            ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.secondary.withOpacity(0.15);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.secondary.withOpacity(0.6),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _SavingsPoint {
  final DateTime date;
  final double cumulative;
  final double spent;
  final double perDayBudget;

  const _SavingsPoint({
    required this.date,
    required this.cumulative,
    required this.spent,
    required this.perDayBudget,
  });
}

class _SavingsChart extends StatelessWidget {
  final List<_SavingsPoint> points;

  const _SavingsChart({
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (points.length < 2) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: Text('Zu wenig Daten für einen Graphen.'),
        ),
      );
    }

    final minY = points.map((p) => p.cumulative).reduce(min);
    final maxY = points.map((p) => p.cumulative).reduce(max);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: CustomPaint(
        painter: _SavingsChartPainter(
          points: points,
          minY: minY,
          maxY: maxY,
          lineColor: theme.colorScheme.secondary,
          axisColor: Colors.white30,
          textColor: Colors.white70,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SavingsChartPainter extends CustomPainter {
  final List<_SavingsPoint> points;
  final double minY;
  final double maxY;
  final Color lineColor;
  final Color axisColor;
  final Color textColor;

  _SavingsChartPainter({
    required this.points,
    required this.minY,
    required this.maxY,
    required this.lineColor,
    required this.axisColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintAxis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    final paintPoint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    final paintGrid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;

    final leftAxisWidth = 56.0;
    final rightPad = 6.0;
    final topPad = 12.0;
    final bottomPad = 16.0;

    final plotLeft = leftAxisWidth;
    final plotTop = topPad;
    final plotW = size.width - plotLeft - rightPad;
    final plotH = size.height - plotTop - bottomPad;

    final ySpan = (maxY - minY).abs() < 0.0001 ? 1.0 : (maxY - minY);

    final ticks = _buildNiceTicks(minY, maxY, count: 4);

    for (final t in ticks) {
      final norm = (t - minY) / ySpan;
      final yRaw = plotTop + plotH * (1 - norm);

      final tp = TextPainter(
        text: TextSpan(
          text: '${t.toStringAsFixed(0)} €',
          style: TextStyle(color: textColor, fontSize: 10),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout(maxWidth: leftAxisWidth - 8);

      final y = yRaw.clamp(
        plotTop + tp.height / 2,
        plotTop + plotH - tp.height / 2,
      );

      canvas.drawLine(
        Offset(plotLeft, yRaw),
        Offset(plotLeft + plotW, yRaw),
        paintGrid,
      );

      tp.paint(canvas, Offset(plotLeft - tp.width - 8, y - tp.height / 2));
    }

    canvas.drawLine(
      Offset(plotLeft, plotTop),
      Offset(plotLeft, plotTop + plotH),
      paintAxis,
    );

    canvas.drawLine(
      Offset(plotLeft, plotTop + plotH),
      Offset(plotLeft + plotW, plotTop + plotH),
      paintAxis,
    );

    final path = Path();
    final offsets = <Offset>[];

    for (int i = 0; i < points.length; i++) {
      final x = plotLeft + plotW * (i / (points.length - 1));
      final norm = (points[i].cumulative - minY) / ySpan;
      final y = plotTop + plotH * (1 - norm);
      final o = Offset(x, y);
      offsets.add(o);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paintLine);

    for (final o in offsets) {
      canvas.drawCircle(o, 3.2, paintPoint);
      canvas.drawCircle(
        o,
        3.2,
        Paint()
          ..color = Colors.black.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  List<double> _buildNiceTicks(double minV, double maxV, {int count = 4}) {
    if (count <= 1) return [minV, maxV];
    final span = (maxV - minV).abs();
    if (span < 0.0001) {
      final base = minV;
      return List.generate(count + 1, (i) => base + i);
    }

    final rawStep = span / count;
    final step = _niceStep(rawStep);

    final niceMin = (minV / step).floor() * step;
    final niceMax = (maxV / step).ceil() * step;

    final ticks = <double>[];
    double v = niceMin;
    while (v <= niceMax + 0.001) {
      ticks.add(v);
      v += step;
    }
    return ticks;
  }

  double _niceStep(double raw) {
    final exp = pow(10, (log(raw) / ln10).floor()).toDouble();
    final f = raw / exp;

    double niceF;
    if (f < 1.5) {
      niceF = 1;
    } else if (f < 3) {
      niceF = 2;
    } else if (f < 7) {
      niceF = 5;
    } else {
      niceF = 10;
    }
    return niceF * exp;
  }

  @override
  bool shouldRepaint(covariant _SavingsChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.minY != minY || oldDelegate.maxY != maxY;
  }
}
