import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/receipt_dao.dart';
import '../../models/receipt_models.dart';

class ReceiptEditPage extends StatefulWidget {
  final Receipt receipt;

  const ReceiptEditPage({
    super.key,
    required this.receipt,
  });

  @override
  State<ReceiptEditPage> createState() => _ReceiptEditPageState();
}

class _ReceiptEditPageState extends State<ReceiptEditPage> {
  final _receiptDao = ReceiptDao();

  Receipt? _receipt;
  bool _isLoading = true;

  final List<_EditableItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadReceipt();
  }

  Future<void> _loadReceipt() async {
    setState(() => _isLoading = true);

    final r = await _receiptDao.getReceiptById(widget.receipt.id);
    if (r == null) {
      if (!mounted) return;
      Navigator.of(context).pop(false);
      return;
    }

    await r.lineItems.load();

    _items
      ..clear()
      ..addAll(r.lineItems.map(_EditableItem.fromLineItem));

    if (!mounted) return;
    setState(() {
      _receipt = r;
      _isLoading = false;
    });
  }

  void _addEmptyItem() {
    HapticFeedback.lightImpact();
    setState(() {
      _items.add(_EditableItem.empty());
    });
  }

  void _removeItem(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _items.removeAt(index);
    });
  }

  double _calcTotal() {
    return _items.fold<double>(0.0, (sum, it) => sum + it.totalPrice);
  }

  Future<void> _save() async {
    if (_receipt == null) return;

    final newItems = <LineItem>[];
    for (final e in _items) {
      final name = e.nameController.text.trim();
      if (name.isEmpty) continue;

      final qTxt = e.qtyController.text.replaceAll(',', '.').trim();
      final pTxt = e.priceController.text.replaceAll(',', '.').trim();

      final qty = double.tryParse(qTxt) ?? 1.0;
      final price = double.tryParse(pTxt) ?? 0.0;

      final li = LineItem()
        ..name = name
        ..quantity = qty <= 0 ? 1.0 : qty
        ..unitPrice = price < 0 ? 0.0 : price
        ..totalPrice = (qty <= 0 ? 1.0 : qty) * (price < 0 ? 0.0 : price)
        ..category = e.category;

      newItems.add(li);
    }

    final total = newItems.fold<double>(0.0, (s, it) => s + it.totalPrice);

    _receipt!
      ..total = total
      ..isLoaded = newItems.isNotEmpty
      ..updatedAt = DateTime.now();

    await _receiptDao.updateLineItemsForReceipt(_receipt!, newItems);
    await _receiptDao.insertReceipt(_receipt!);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Soft-Delete:
  /// Bon bleibt als Kachel sichtbar, zählt aber nicht mehr.
  Future<void> _softDeleteReceipt() async {
    if (_receipt == null) return;

    _receipt!
      ..total = 0.0
      ..isLoaded = false
      ..updatedAt = DateTime.now();

    await _receiptDao.updateLineItemsForReceipt(_receipt!, []);
    await _receiptDao.insertReceipt(_receipt!);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final r = _receipt!;
    final dateStr = DateFormat.yMMMd('de_DE').add_Hm().format(r.dateTime);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kassenzettel bearbeiten'),
        actions: [
          IconButton(
            tooltip: 'Bon entladen (nicht löschen)',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Bon entfernen?'),
                  content: const Text(
                    'Der Bon bleibt sichtbar, wird aber nicht mehr gezählt.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Abbrechen'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Entfernen'),
                    ),
                  ],
                ),
              );

              if (ok == true) {
                await _softDeleteReceipt();
              }
            },
          ),
          IconButton(
            tooltip: 'Speichern',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: theme.colorScheme.surfaceVariant.withOpacity(0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${r.storeName ?? 'Händler'} • $dateStr',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '${_calcTotal().toStringAsFixed(2)} €',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Artikel', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addEmptyItem,
                icon: const Icon(Icons.add),
                label: const Text('Hinzufügen'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Keine Artikel gespeichert.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          else
            ...List.generate(_items.length, (i) => _buildItemCard(i, theme)),
        ],
      ),
    );
  }

  Widget _buildItemCard(int index, ThemeData theme) {
    final item = _items[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: item.nameController,
                    decoration: const InputDecoration(
                      labelText: 'Produkt',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(60),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: item.qtyController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Menge',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: item.priceController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Preis',
                            suffixText: '€',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: item.category,
                    decoration: const InputDecoration(
                      labelText: 'Kategorie',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'food', child: Text('Food')),
                      DropdownMenuItem(value: 'leisure', child: Text('Leisure')),
                      DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => item.category = v);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeItem(index),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableItem {
  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  String category;

  _EditableItem({
    required this.nameController,
    required this.qtyController,
    required this.priceController,
    required this.category,
  });

  factory _EditableItem.fromLineItem(LineItem li) {
    return _EditableItem(
      nameController: TextEditingController(text: li.name),
      qtyController: TextEditingController(text: li.quantity.toStringAsFixed(2)),
      priceController:
          TextEditingController(text: li.unitPrice.toStringAsFixed(2)),
      category: li.category ?? 'food',
    );
  }

  factory _EditableItem.empty() {
    return _EditableItem(
      nameController: TextEditingController(),
      qtyController: TextEditingController(text: '1'),
      priceController: TextEditingController(text: '0'),
      category: 'food',
    );
  }

  double get quantity {
    final txt = qtyController.text.replaceAll(',', '.').trim();
    final v = double.tryParse(txt) ?? 1.0;
    return v <= 0 ? 1.0 : v;
  }

  double get unitPrice {
    final txt = priceController.text.replaceAll(',', '.').trim();
    final v = double.tryParse(txt) ?? 0.0;
    return v < 0 ? 0.0 : v;
  }

  double get totalPrice => quantity * unitPrice;
}
