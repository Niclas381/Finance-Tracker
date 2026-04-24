import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/receipt_dao.dart';
import '../../models/receipt_models.dart';
import '../receipts/receipt_edit_page.dart';
import '../receipts/pdf_preview_page.dart';
import '../../services/receipt_sync_service.dart';

class CategoryDetailsPage extends StatefulWidget {
  final String categoryKey;
  final String categoryLabel;

  const CategoryDetailsPage({
    super.key,
    required this.categoryKey,
    required this.categoryLabel,
  });

  @override
  State<CategoryDetailsPage> createState() => _CategoryDetailsPageState();
}

class _CategoryItem {
  final Receipt receipt;
  final LineItem item;

  _CategoryItem({
    required this.receipt,
    required this.item,
  });
}

class _CategoryDetailsPageState extends State<CategoryDetailsPage> {
  final _receiptDao = ReceiptDao();
  late final ReceiptSyncService _syncService;

  bool _isLoading = true;
  DateTimeRange? _range;

  List<_CategoryItem> _items = [];
  double _total = 0.0;

  @override
  void initState() {
    super.initState();
    _syncService = ReceiptSyncService(_receiptDao);
    _initRangeAndLoad();
  }

  Future<void> _initRangeAndLoad() async {
    final now = DateTime.now();
    final defaultRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day),
    );

    setState(() {
      _range = defaultRange;
    });

    await _loadData();
  }

  Future<void> _loadData() async {
    if (_range == null) return;

    setState(() {
      _isLoading = true;
    });

    final start = DateUtils.dateOnly(_range!.start);
    final end = DateUtils.dateOnly(_range!.end);

    final receipts = await _receiptDao.getAllReceipts();

    final items = <_CategoryItem>[];

    for (final r in receipts) {
      final d = DateUtils.dateOnly(r.dateTime);
      if (d.isBefore(start) || d.isAfter(end)) continue;

      await r.lineItems.load();

      for (final li in r.lineItems) {
        if (li.category == widget.categoryKey) {
          items.add(_CategoryItem(receipt: r, item: li));
        }
      }
    }

    items.sort((a, b) => b.receipt.dateTime.compareTo(a.receipt.dateTime));

    final total = items.fold<double>(
      0.0,
      (sum, e) => sum + e.item.totalPrice,
    );

    if (!mounted) return;

    setState(() {
      _items = items;
      _total = total;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    await _loadData();
  }

  String _formatRangeShort() {
    if (_range == null) return '';
    final df = DateFormat('dd.MM.yyyy', 'de_DE');
    return '${df.format(_range!.start)} – ${df.format(_range!.end)}';
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
    });

    await _loadData();
  }

  Future<void> _setRangeThisMonth() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month, now.day);

    setState(() {
      _range = DateTimeRange(start: start, end: end);
    });
    await _loadData();
  }

  Future<void> _setRangeLastMonth() async {
    final now = DateTime.now();
    final prevMonth = DateTime(now.year, now.month - 1, 1);
    final start = DateTime(prevMonth.year, prevMonth.month, 1);
    final end = DateTime(prevMonth.year, prevMonth.month + 1, 0);

    setState(() {
      _range = DateTimeRange(start: start, end: end);
    });
    await _loadData();
  }

  Future<void> _setRangeLastYear() async {
    final now = DateTime.now();
    final year = now.year - 1;
    final start = DateTime(year, 1, 1);
    final end = DateTime(year, 12, 31);

    setState(() {
      _range = DateTimeRange(start: start, end: end);
    });
    await _loadData();
  }

  Future<void> _setRangeAllTime() async {
    final receipts = await _receiptDao.getAllReceipts();
    DateTime? minDate;
    DateTime? maxDate;

    for (final r in receipts) {
      await r.lineItems.load();
      final hasCat = r.lineItems.any((li) => li.category == widget.categoryKey);
      if (!hasCat) continue;

      final d = DateUtils.dateOnly(r.dateTime);
      minDate ??= d;
      maxDate ??= d;
      if (d.isBefore(minDate)) minDate = d;
      if (d.isAfter(maxDate)) maxDate = d;
    }

    if (minDate == null || maxDate == null) {
      final today = DateUtils.dateOnly(DateTime.now());
      minDate = today;
      maxDate = today;
    }

    setState(() {
      _range = DateTimeRange(start: minDate!, end: maxDate!);
    });
    await _loadData();
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
                      'Zeitraum',
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
                      label: 'Dieser Monat',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setRangeThisMonth();
                      },
                    ),
                    _QuickChip(
                      label: 'Letzter Monat',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setRangeLastMonth();
                      },
                    ),
                    _QuickChip(
                      label: 'Letztes Jahr',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setRangeLastYear();
                      },
                    ),
                    _QuickChip(
                      label: 'Gesamt',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setRangeAllTime();
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

  Future<void> _openEdit(Receipt receipt) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiptEditPage(receipt: receipt),
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  Future<void> _openPdf(Receipt receipt) async {
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
      final pdfPath =
          await _syncService.downloadReceiptPdf(messageId: messageId);

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
        SnackBar(
          content: Text('Fehler beim Laden des PDFs: $e'),
        ),
      );
    }
  }

  Widget _buildTotalCard(ThemeData theme) {
    return Card(
      elevation: 3,
      color: theme.colorScheme.secondaryContainer.withOpacity(0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.secondary.withOpacity(0.7),
          width: 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.categoryLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white70,
                letterSpacing: 0.2,
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
            Text(
              _formatRangeShort(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(_CategoryItem ci, ThemeData theme) {
    final r = ci.receipt;
    final li = ci.item;

    final dateStr = DateFormat.yMMMd('de_DE').add_Hm().format(r.dateTime);
    final store = r.storeName ?? 'Unbekannter Händler';
    final isEmail = r.source == 'email';

    final hasUsefulName =
        li.name.trim().isNotEmpty && li.name.trim().toLowerCase() != 'gesamt';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openEdit(r),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shopping_basket_outlined,
                size: 22,
                color: theme.colorScheme.primary.withOpacity(0.9),
              ),
              const SizedBox(width: 10),
              // Textblock
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1) Ladenname (immer, statt "Gesamt")
                    Text(
                      store,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // 2) Datum
                    Text(
                      dateStr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 3) Optional Produktname (wenn nicht "Gesamt")
                    if (hasUsefulName) ...[
                      const SizedBox(height: 2),
                      Text(
                        li.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[300],
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      'Quelle: ${r.source}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[400],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Betrag + kleine Actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${li.totalPrice.toStringAsFixed(2)} €',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEmail && r.emailMessageId != null)
                        IconButton(
                          tooltip: 'PDF anzeigen',
                          icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 18,
                          ),
                          onPressed: () => _openPdf(r),
                        ),
                      IconButton(
                        tooltip: 'Bearbeiten',
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                        ),
                        onPressed: () => _openEdit(r),
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
        title: Text(widget.categoryLabel),
        actions: [
          IconButton(
            tooltip: 'Zeitraum wählen',
            icon: const Icon(Icons.date_range),
            onPressed: _openRangeSheet,
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
                  _buildTotalCard(theme),
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Center(
                        child: Text(
                          'Keine Ausgaben in diesem Zeitraum\nfür diese Kategorie.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'Ausgaben',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ..._items.map((ci) => _buildItemCard(ci, theme)),
                  ],
                ],
              ),
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
