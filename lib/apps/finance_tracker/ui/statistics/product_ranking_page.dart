import 'package:flutter/material.dart';

import '../../data/receipt_dao.dart';
import '../../models/receipt_models.dart';

enum ProductSortMode {
  byCount,        // Nach Häufigkeit (wie oft gekauft)
  byCapital,      // Nach Kapitalisierung (Anzahl × Preis)
}

/// Aggregiertes Produkt für das Ranking
class _RankedProduct {
  final String name;
  int count;              // Wie oft insgesamt gekauft
  double totalSpent;      // Gesamtausgaben für dieses Produkt
  double avgPrice;        // Durchschnittspreis

  _RankedProduct({
    required this.name,
    this.count = 0,
    this.totalSpent = 0.0,
    this.avgPrice = 0.0,
  });

  /// Kapitalisierung = Anzahl × Durchschnittspreis
  double get capitalization => totalSpent;
}

class ProductRankingPage extends StatefulWidget {
  const ProductRankingPage({super.key});

  @override
  State<ProductRankingPage> createState() => _ProductRankingPageState();
}

class _ProductRankingPageState extends State<ProductRankingPage> {
  final _receiptDao = ReceiptDao();

  bool _isLoading = true;
  List<_RankedProduct> _products = [];
  ProductSortMode _sortMode = ProductSortMode.byCount;

  // Filter: Zeitraum
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      final allReceipts = await _receiptDao.getAllReceipts();

      // Produkte aggregieren
      final productMap = <String, _RankedProduct>{};

      for (final receipt in allReceipts) {
        // Gebannte Receipts ignorieren
        if (receipt.isBanned) continue;

        // Zeitraum-Filter anwenden
        if (_fromDate != null && receipt.dateTime.isBefore(_fromDate!)) continue;
        if (_toDate != null && receipt.dateTime.isAfter(_toDate!.add(const Duration(days: 1)))) continue;

        // LineItems laden falls noch nicht geladen
        await receipt.lineItems.load();

        for (final item in receipt.lineItems) {
          // "Gesamt" Einträge überspringen - das sind keine echten Produkte
          if (item.name.toLowerCase() == 'gesamt') continue;

          // Normalisierter Name für Gruppierung
          final normalizedName = _normalizeProductName(item.name);

          if (!productMap.containsKey(normalizedName)) {
            productMap[normalizedName] = _RankedProduct(name: item.name);
          }

          final product = productMap[normalizedName]!;
          product.count += item.quantity.round();
          product.totalSpent += item.totalPrice;
        }
      }

      // Durchschnittspreis berechnen
      for (final product in productMap.values) {
        if (product.count > 0) {
          product.avgPrice = product.totalSpent / product.count;
        }
      }

      // Liste erstellen und sortieren
      _products = productMap.values.toList();
      _sortProducts();

    } catch (e) {
      debugPrint('Fehler beim Laden der Produkte: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Normalisiert Produktnamen für bessere Gruppierung
  String _normalizeProductName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _sortProducts() {
    switch (_sortMode) {
      case ProductSortMode.byCount:
        _products.sort((a, b) => b.count.compareTo(a.count));
        break;
      case ProductSortMode.byCapital:
        _products.sort((a, b) => b.capitalization.compareTo(a.capitalization));
        break;
    }
  }

  void _changeSortMode(ProductSortMode mode) {
    if (_sortMode == mode) return;
    setState(() {
      _sortMode = mode;
      _sortProducts();
    });
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(
      start: _fromDate ?? DateTime(now.year, now.month, 1),
      end: _toDate ?? now,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initialRange,
      helpText: 'Zeitraum für Produktranking',
      cancelText: 'Abbrechen',
      confirmText: 'Übernehmen',
      saveText: 'Speichern',
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      await _loadProducts();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produktranking'),
        actions: [
          // Zeitraum-Filter
          IconButton(
            tooltip: 'Zeitraum filtern',
            icon: Icon(
              Icons.date_range,
              color: (_fromDate != null || _toDate != null)
                  ? theme.colorScheme.primary
                  : null,
            ),
            onPressed: _selectDateRange,
          ),
          if (_fromDate != null || _toDate != null)
            IconButton(
              tooltip: 'Filter zurücksetzen',
              icon: const Icon(Icons.clear),
              onPressed: _clearDateFilter,
            ),
        ],
      ),
      body: Column(
        children: [
          // Sortier-Auswahl
          _buildSortSelector(theme),

          // Zeitraum-Anzeige wenn gefiltert
          if (_fromDate != null || _toDate != null)
            _buildDateRangeInfo(theme),

          // Produktliste
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildProductList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSortSelector(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            'Sortieren nach:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SegmentedButton<ProductSortMode>(
              segments: const [
                ButtonSegment(
                  value: ProductSortMode.byCount,
                  label: Text('Häufigkeit'),
                  icon: Icon(Icons.numbers),
                ),
                ButtonSegment(
                  value: ProductSortMode.byCapital,
                  label: Text('Ausgaben'),
                  icon: Icon(Icons.euro),
                ),
              ],
              selected: {_sortMode},
              onSelectionChanged: (selected) {
                if (selected.isNotEmpty) {
                  _changeSortMode(selected.first);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeInfo(ThemeData theme) {
    final dateFormat = MaterialLocalizations.of(context);
    String rangeText = '';

    if (_fromDate != null && _toDate != null) {
      rangeText = '${dateFormat.formatShortDate(_fromDate!)} – ${dateFormat.formatShortDate(_toDate!)}';
    } else if (_fromDate != null) {
      rangeText = 'Ab ${dateFormat.formatShortDate(_fromDate!)}';
    } else if (_toDate != null) {
      rangeText = 'Bis ${dateFormat.formatShortDate(_toDate!)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
      child: Row(
        children: [
          Icon(
            Icons.filter_list,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Zeitraum: $rangeText',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Keine Produkte gefunden',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lade Kassenzettel mit einzelnen Produkten,\num das Ranking zu sehen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList(ThemeData theme) {
    // Bottom-Padding für Android-Navigationsleiste
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return ListView.builder(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + bottomPadding + 16, // Extra Platz unten
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        final rank = index + 1;

        // Farbe für Top 3
        Color? rankColor;
        IconData? rankIcon;
        if (rank == 1) {
          rankColor = Colors.amber;
          rankIcon = Icons.emoji_events;
        } else if (rank == 2) {
          rankColor = Colors.grey[400];
          rankIcon = Icons.emoji_events;
        } else if (rank == 3) {
          rankColor = Colors.orange[300];
          rankIcon = Icons.emoji_events;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: theme.colorScheme.surfaceVariant.withOpacity(0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: rankColor?.withOpacity(0.5) ?? Colors.white12,
              width: rank <= 3 ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Rang
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: rankColor?.withOpacity(0.2) ??
                        theme.colorScheme.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: rankIcon != null
                        ? Icon(rankIcon, color: rankColor, size: 24)
                        : Text(
                            '#$rank',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // Produktinfo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildStatChip(
                            theme,
                            Icons.shopping_bag_outlined,
                            '${product.count}×',
                            _sortMode == ProductSortMode.byCount,
                          ),
                          const SizedBox(width: 8),
                          _buildStatChip(
                            theme,
                            Icons.euro,
                            '${product.totalSpent.toStringAsFixed(2)} €',
                            _sortMode == ProductSortMode.byCapital,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '⌀ ${product.avgPrice.toStringAsFixed(2)} €',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatChip(ThemeData theme, IconData icon, String text, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primary.withOpacity(0.2)
            : theme.colorScheme.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
        border: isActive
            ? Border.all(color: theme.colorScheme.primary.withOpacity(0.5))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.6),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}