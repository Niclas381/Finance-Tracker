import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/receipt_dao.dart';
import '../../data/settings_dao.dart';
import '../../models/receipt_models.dart';
import '../../services/receipt_sync_service.dart';
import '../receipts/pdf_preview_page.dart';
import '../receipts/receipt_edit_page.dart';
import '../receipts/scan_preview_page.dart';
import 'widgets/month_spending_calendar.dart';

class DayDetailsPage extends StatefulWidget {
  final DateTime day;

  const DayDetailsPage({
    super.key,
    required this.day,
  });

  @override
  State<DayDetailsPage> createState() => _DayDetailsPageState();
}

class _DayReceipt {
  final Receipt receipt;
  final double value;

  _DayReceipt({
    required this.receipt,
    required this.value,
  });
}

class _DayDetailsPageState extends State<DayDetailsPage> {
  final _receiptDao = ReceiptDao();
  final _settingsDao = SettingsDao();
  late final ReceiptSyncService _syncService;

  bool _isLoading = true;

  /// aktuell ausgewählter Tag (nur Datum)
  late DateTime _day;

  /// Monat, für den der Kalender unten die Werte anzeigt
  late DateTime _currentMonth;

  /// Summe aller Ausgaben an _day
  double _total = 0.0;

  /// Tagesbudget für den aktuellen Monat
  double _perDayBudget = 0.0;

  /// Receipts für _day (als ganze Kachel)
  List<_DayReceipt> _receipts = [];

  /// Map für den Kalender unten: Tag -> Summe im Monat
  Map<int, double> _spendingPerDay = {};

  @override
  void initState() {
    super.initState();
    _syncService = ReceiptSyncService(_receiptDao);
    _day = DateUtils.dateOnly(widget.day);
    _currentMonth = DateTime(_day.year, _day.month);
    _loadDataForDayAndMonth();
  }

  double _effectiveReceiptValue(Receipt r) {
    if (r.total > 0) return r.total;

    // Fallback: Summe der LineItems (z.B. wenn total nicht gesetzt ist)
    return r.lineItems.fold<double>(
      0.0,
      (s, li) => s + li.totalPrice,
    );
  }

  Future<void> _loadDataForDayAndMonth() async {
    setState(() => _isLoading = true);

    final settings = await _settingsDao.getSettings();
    final receipts = await _receiptDao.getAllReceipts();

    // --- Monatsaggregat für Kalender (gleiche Logik wie ReceiptDao.getTotalSpentInMonth) ---
    final monthYear = _currentMonth.year;
    final monthMonth = _currentMonth.month;

    final spendingPerDay = <int, double>{};

    for (final r in receipts) {
      if (r.isBanned == true) continue;

      final value = _effectiveReceiptValue(r);
      if (value <= 0) continue;

      final d = r.dateTime;
      if (d.year == monthYear && d.month == monthMonth) {
        spendingPerDay[d.day] = (spendingPerDay[d.day] ?? 0.0) + value;
      }
    }

    final daysInMonth = DateUtils.getDaysInMonth(monthYear, monthMonth);
    final perDayBudget =
        daysInMonth > 0 ? settings.monthlyBudget / daysInMonth : 0.0;

    // --- Tagesdetails als Receipts (nicht mehr nur LineItems) ---
    final dayReceipts = <_DayReceipt>[];
    for (final r in receipts) {
      if (r.isBanned == true) continue;

      final d = DateUtils.dateOnly(r.dateTime);
      if (!DateUtils.isSameDay(d, _day)) continue;

      final value = _effectiveReceiptValue(r);
      if (value <= 0) continue;

      dayReceipts.add(_DayReceipt(receipt: r, value: value));
    }

    dayReceipts.sort((a, b) => b.receipt.dateTime.compareTo(a.receipt.dateTime));

    final total = dayReceipts.fold<double>(
      0.0,
      (sum, e) => sum + e.value,
    );

    if (!mounted) return;

    setState(() {
      _spendingPerDay = spendingPerDay;
      _perDayBudget = perDayBudget;
      _receipts = dayReceipts;
      _total = total;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    await _loadDataForDayAndMonth();
  }

  Color _colorForRatio(double spent, double budget, ThemeData theme) {
    if (budget <= 0 || spent <= 0) {
      return theme.colorScheme.surfaceVariant;
    }

    final ratio = (spent / budget).clamp(0.0, 1.5);

    const green = Color(0xFF4CAF50);
    const red = Color(0xFFF44336);

    if (ratio <= 0.6) {
      return green;
    } else if (ratio <= 1.0) {
      final linearT = (ratio - 0.6) / 0.4;
      final easedT = linearT * linearT;
      return Color.lerp(green, red, easedT)!;
    } else {
      return red;
    }
  }

  /// Kalender unten aufpoppen lassen, basierend auf [MonthSpendingCalendar]
  void _openCalendarSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).padding.bottom;

        final theme = Theme.of(sheetContext);
        final monthLabel = DateFormat('MMMM yyyy', 'de_DE').format(_currentMonth);

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      monthLabel,
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Kalender schließen',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MonthSpendingCalendar(
                  month: _currentMonth,
                  spendingPerDay: _spendingPerDay,
                  perDayBudget: _perDayBudget,
                  selectedDay: (_currentMonth.year == _day.year &&
                          _currentMonth.month == _day.month)
                      ? _day.day
                      : null,
                  onDayTap: (day) {
                    setState(() {
                      _day = DateTime(_currentMonth.year, _currentMonth.month, day);
                    });
                    _loadDataForDayAndMonth();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEdit(Receipt receipt) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiptEditPage(receipt: receipt),
      ),
    );

    if (changed == true) {
      await _loadDataForDayAndMonth();
    }
  }

  /// Prüft ob eine Datei ein Bild ist
  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  Future<void> _openPdf(Receipt receipt) async {
    // Für shared/scan Quellen: lokales PDF/Bild öffnen
    if ((receipt.source == 'shared' || receipt.source == 'scan') &&
        receipt.pdfLocalPath != null &&
        receipt.pdfLocalPath!.isNotEmpty) {
      final file = File(receipt.pdfLocalPath!);
      if (await file.exists()) {
        if (_isImageFile(receipt.pdfLocalPath!)) {
          await _showImagePreview(receipt);
        } else if (receipt.pdfLocalPath!.toLowerCase().endsWith('.pdf')) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PdfPreviewPage(
                pdfPath: receipt.pdfLocalPath!,
                title: receipt.storeName ?? 'Kassenzettel',
              ),
            ),
          );
        } else {
          await _showImagePreview(receipt);
        }
        return;
      }
    }

    // Für Email-Quellen: PDF von Gmail laden
    final messageId = receipt.emailMessageId;
    if (messageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein PDF für diesen Beleg verfügbar.')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdfPath = await _syncService.downloadReceiptPdf(messageId: messageId);

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfPreviewPage(
            pdfPath: pdfPath,
            title: receipt.storeName ?? 'Kassenzettel',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden des PDFs: $e')),
      );
    }
  }

  Future<void> _showImagePreview(Receipt receipt) async {
    if (receipt.pdfLocalPath == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(receipt.storeName ?? 'Kassenzettel'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Image.file(
                File(receipt.pdfLocalPath!),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openScanPreview(Receipt receipt) async {
    await receipt.lineItems.load();
    final draftItems = receipt.lineItems.toList();

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScanPreviewPage(
          receiptId: receipt.id,
          addItemsIndividually: true,
          draftItems: draftItems,
          draftTotal: _effectiveReceiptValue(receipt),
        ),
      ),
    );

    if (changed == true) {
      await _loadDataForDayAndMonth();
    }
  }

  Future<void> _deleteReceipt(Receipt receipt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ausgabe löschen?'),
        content: Text(
          'Soll "${receipt.storeName ?? 'Ausgabe'}" wirklich gelöscht werden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _receiptDao.deleteReceipt(receipt.id);
    await _loadDataForDayAndMonth();
  }

  Future<void> _openReceiptDetailsSheet(Receipt receipt, double value) async {
    await receipt.lineItems.load();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottom = MediaQuery.of(ctx).padding.bottom;
        final timeStr = DateFormat.Hm('de_DE').format(receipt.dateTime);

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        receipt.storeName ?? 'Ausgabe',
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${value.toStringAsFixed(2)} €',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$timeStr • ${_sourceLabel(receipt.source)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                if (receipt.lineItems.isEmpty)
                  Text(
                    'Keine Einzelpositionen vorhanden.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: receipt.lineItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (ctx, i) {
                        final items = receipt.lineItems.toList();
                        final li = items[i];
                        final name = li.name.trim().isEmpty ? 'Artikel' : li.name.trim();
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: theme.textTheme.bodyMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('${li.totalPrice.toStringAsFixed(2)} €'),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (_canOpenPdf(receipt))
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _openPdf(receipt);
                        },
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('Beleg öffnen'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        if (receipt.source == 'scan' || receipt.source == 'shared') {
                          _openScanPreview(receipt);
                        } else {
                          _openEdit(receipt);
                        }
                      },
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Bearbeiten'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _deleteReceipt(receipt);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Löschen'),
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

  bool _canOpenPdf(Receipt r) {
    final hasLocal = r.pdfLocalPath != null && r.pdfLocalPath!.isNotEmpty;
    final hasEmail = r.emailMessageId != null;
    final isScanOrShared = r.source == 'scan' || r.source == 'shared';
    final isEmail = r.source == 'email';
    return (isScanOrShared && hasLocal) || (isEmail && hasEmail);
  }

  static String _sourceLabel(String? source) {
    switch (source) {
      case 'email':
        return 'E-Mail Import';
      case 'shared':
        return 'Geteilt';
      case 'scan':
        return 'Gescannt';
      case 'manual':
        return 'Manuell';
      case 'message':
        return 'Nachrichtenerkennung';
      default:
        return source ?? 'Unbekannt';
    }
  }

  static IconData _sourceIcon(String? source) {
    switch (source) {
      case 'email':
        return Icons.email_outlined;
      case 'shared':
        return Icons.ios_share_outlined;
      case 'scan':
        return Icons.document_scanner_outlined;
      case 'manual':
        return Icons.edit_outlined;
      case 'message':
        return Icons.notifications_active_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Widget _buildHeaderCard(ThemeData theme) {
    final df = DateFormat('EEEE, dd.MM.yyyy', 'de_DE');
    final dateStr = df.format(_day);

    final color = _colorForRatio(_total, _perDayBudget, theme);
    final diff = _perDayBudget - _total;

    String infoText;
    if (_perDayBudget <= 0) {
      infoText = 'Kein Monatsbudget gesetzt';
    } else if (diff >= 0) {
      infoText = 'Unter Tagesbudget: +${diff.toStringAsFixed(2)} €';
    } else {
      infoText = 'Über Tagesbudget: ${diff.toStringAsFixed(2)} €';
    }

    return Card(
      elevation: 3,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: color,
          width: 1.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateStr,
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_total.toStringAsFixed(2)} €',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_perDayBudget > 0)
                  Flexible(
                    flex: 3,
                    child: Text(
                      'Tagesbudget: ${_perDayBudget.toStringAsFixed(2)} €',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: Text(
                    infoText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: diff >= 0 ? Colors.greenAccent : Colors.redAccent,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(_DayReceipt dr, ThemeData theme) {
    final r = dr.receipt;
    final value = dr.value;

    final timeStr = DateFormat.Hm('de_DE').format(r.dateTime);
    final store = r.storeName ?? 'Unbekannter Händler';

    return Card(
      elevation: 2,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openReceiptDetailsSheet(r, value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Row(
            children: [
              Icon(
                _sourceIcon(r.source),
                size: 22,
                color: Colors.white70,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$timeStr • ${_sourceLabel(r.source)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${value.toStringAsFixed(2)} €',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_canOpenPdf(r))
                        IconButton(
                          tooltip: 'Beleg öffnen',
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          onPressed: () => _openPdf(r),
                        ),
                      IconButton(
                        tooltip: 'Bearbeiten',
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () {
                          if (r.source == 'scan' || r.source == 'shared') {
                            _openScanPreview(r);
                          } else {
                            _openEdit(r);
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Löschen',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _deleteReceipt(r),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tagesdetails'),
        actions: [
          IconButton(
            tooltip: 'Kalender',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _openCalendarSheet,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  _buildHeaderCard(theme),
                  const SizedBox(height: 16),
                  Text(
                    'Ausgaben',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_receipts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Center(
                        child: Text(
                          'Keine Ausgaben an diesem Tag.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._receipts.map((r) => _buildReceiptCard(r, theme)),
                ],
              ),
            ),
    );
  }
}
