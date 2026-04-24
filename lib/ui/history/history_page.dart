import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/receipt_dao.dart';
import '../../data/settings_dao.dart';
import '../../models/receipt_models.dart';
import 'day_details_page.dart';
import 'widgets/month_spending_calendar.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _receiptDao = ReceiptDao();
  final _settingsDao = SettingsDao();

  bool _isLoading = true;
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  double _perDayBudget = 0.0;
  Map<int, double> _spendingPerDay = {}; // Tag -> Summe

  @override
  void initState() {
    super.initState();
    _loadMonth(_focusedMonth);
  }

  Future<void> _loadMonth(DateTime month) async {
    setState(() {
      _isLoading = true;
    });

    final year = month.year;
    final m = month.month;
    final settings = await _settingsDao.getSettings();
    final allReceipts = await _receiptDao.getAllReceipts();

    final daysInMonth = DateUtils.getDaysInMonth(year, m);
    final perDayBudget =
        daysInMonth > 0 ? settings.monthlyBudget / daysInMonth : 0.0;

    final map = <int, double>{};

    for (final r in allReceipts) {
      final d = r.dateTime;
      if (d.year == year && d.month == m) {
        // Nur echte Ausgaben zählen (isLoaded und nicht gebannt)
        if (!r.isLoaded || r.isBanned || r.total <= 0.0) continue;
        map[d.day] = (map[d.day] ?? 0.0) + r.total;
      }
    }

    if (!mounted) return;

    setState(() {
      _focusedMonth = DateTime(year, m);
      _perDayBudget = perDayBudget;
      _spendingPerDay = map;
      _isLoading = false;
    });
  }

  /// Löscht einen kompletten Receipt
  Future<bool> _deleteReceipt(Receipt receipt) async {
    await _receiptDao.deleteReceipt(receipt.id);
    return true;
  }

  /// Öffnet das Bottom Sheet mit den Receipts des Tages (GRUPPIERT!)
  Future<void> _openDayDetailsBottomSheet(int day) async {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;

    final allReceipts = await _receiptDao.getAllReceipts();
    
    // Filtere Receipts für diesen Tag
    final receiptsForDay = allReceipts.where((r) {
      final d = r.dateTime;
      return d.year == year &&
          d.month == month &&
          d.day == day &&
          r.isLoaded &&
          !r.isBanned &&
          r.total > 0.0;
    }).toList();

    // Lade LineItems für jeden Receipt (für die Vorschau)
    for (final r in receiptsForDay) {
      await r.lineItems.load();
    }

    // Nach Zeit sortieren (neueste zuerst)
    receiptsForDay.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final date = DateTime(year, month, day);
        final title = DateFormat('EEEE, dd.MM.yyyy', 'de_DE').format(date);

        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget content;

            if (receiptsForDay.isEmpty) {
              content = const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Keine Einkäufe an diesem Tag.')),
              );
            } else {
              content = ListView.separated(
                shrinkWrap: true,
                itemCount: receiptsForDay.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final receipt = receiptsForDay[index];
                  final storeName = receipt.storeName ?? 'Unbekannt';
                  final timeStr = DateFormat.Hm('de_DE').format(receipt.dateTime);

                  // Produkt-Preview erstellen (ohne "Gesamt"-Einträge)
                  final products = receipt.lineItems
                      .where((li) => 
                          li.name.toLowerCase() != 'gesamt' && 
                          li.name.isNotEmpty)
                      .toList();

                  String subtitleText;
                  if (products.isEmpty) {
                    // Kein einzelnes Produkt, zeige "Gesamt"
                    subtitleText = 'Gesamt • ${receipt.total.toStringAsFixed(2)} €';
                  } else if (products.length == 1) {
                    // Nur ein Produkt
                    subtitleText = products.first.name;
                  } else {
                    // Mehrere Produkte: zeige erste 2 + Anzahl
                    final previewNames = products.take(2).map((p) => p.name).join(', ');
                    if (products.length > 2) {
                      subtitleText = '$previewNames (+${products.length - 2})';
                    } else {
                      subtitleText = previewNames;
                    }
                  }

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.shopping_basket_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Row(
                      children: [
                        Text(
                          storeName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[300],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${receipt.total.toStringAsFixed(2)} €',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Beleg löschen',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            // Bestätigungsdialog
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Beleg löschen?'),
                                content: Text(
                                  'Möchtest du "$storeName" '
                                  '(${receipt.total.toStringAsFixed(2)} €) '
                                  'wirklich löschen?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Abbrechen'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Löschen'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await _deleteReceipt(receipt);

                              setModalState(() {
                                receiptsForDay.removeAt(index);
                              });

                              await _loadMonth(_focusedMonth);
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      // Schließe Bottom Sheet und öffne Details
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DayDetailsPage(
                            day: DateTime(year, month, day),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            }

            // Tagessumme berechnen
            final dayTotal = receiptsForDay.fold<double>(
              0.0,
              (sum, r) => sum + r.total,
            );

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (receiptsForDay.isNotEmpty)
                                Text(
                                  'Gesamt: ${dayTotal.toStringAsFixed(2)} €',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[400],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DayDetailsPage(
                                  day: DateTime(year, month, day),
                                ),
                              ),
                            );
                          },
                          child: const Text('Details'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(child: content),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _changeMonth(int delta) {
    final newMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    _loadMonth(newMonth);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final monthLabel =
        DateFormat('MMMM yyyy', 'de_DE').format(_focusedMonth).toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verlauf'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _changeMonth(-1),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            monthLabel,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _changeMonth(1),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        _perDayBudget > 0
                            ? 'Tagesbudget: ${_perDayBudget.toStringAsFixed(2)} €'
                            : 'Kein Monatsbudget gesetzt',
                        style: theme.textTheme.bodySmall,
                      ),
                      const Spacer(),
                      const Icon(Icons.circle,
                          size: 10, color: Color(0xFF4CAF50)),
                      const SizedBox(width: 4),
                      const Text('unter Budget',
                          style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 8),
                      const Icon(Icons.circle,
                          size: 10, color: Color(0xFFF44336)),
                      const SizedBox(width: 4),
                      const Text('über Budget',
                          style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: MonthSpendingCalendar(
                      month: _focusedMonth,
                      spendingPerDay: _spendingPerDay,
                      perDayBudget: _perDayBudget,
                      selectedDay: null,
                      onDayTap: _openDayDetailsBottomSheet,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}