import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/receipt_dao.dart';
import '../../models/receipt_models.dart';
import '../../services/receipt_sync_service.dart';
import '../../services/receipt_pdf_text_service.dart';
import '../../services/receipt_ocr_service.dart';
import '../../services/ocr_banlist.dart';
import 'pdf_preview_page.dart';

class ScanPreviewPage extends StatefulWidget {
  final int receiptId;

  /// false = als Gesamtposten speichern
  /// true  = Artikel einzeln speichern
  final bool addItemsIndividually;

  /// Draft-Daten aus dem PDF-Parser.
  final List<LineItem>? draftItems;
  final double? draftTotal;

  const ScanPreviewPage({
    super.key,
    required this.receiptId,
    required this.addItemsIndividually,
    this.draftItems,
    this.draftTotal,
  });

  @override
  State<ScanPreviewPage> createState() => _ScanPreviewPageState();
}

class _ScanPreviewPageState extends State<ScanPreviewPage> {
  final _receiptDao = ReceiptDao();
  final _syncService = ReceiptSyncService(ReceiptDao());

  Receipt? _receipt;
  bool _isLoading = true;
  bool _loadingPdf = false;

  final List<_EditableItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadReceipt();
  }

  Future<void> _loadReceipt() async {
    setState(() => _isLoading = true);

    final r = await _receiptDao.getReceiptById(widget.receiptId);
    if (r == null) {
      if (!mounted) return;
      setState(() {
        _receipt = null;
        _items.clear();
        _isLoading = false;
      });
      return;
    }

    // 1) PDF lokal sicherstellen (nur einmal je Bon)
    await _ensureLocalPdf(r);

    // 2) Items laden (Draft bevorzugt)
    _items.clear();

    if (widget.draftItems != null) {
      _items.addAll(widget.draftItems!.map(_EditableItem.fromLineItem));
    } else {
      await r.lineItems.load();
      _items.addAll(r.lineItems.map(_EditableItem.fromLineItem));
    }

    if (!mounted) return;
    setState(() {
      _receipt = r;
      _isLoading = false;
    });
  }

  /// Lädt das PDF über Gmail, speichert es einmalig unter:
  ///   <documents>/receipts/<receiptId>.pdf
  /// und schreibt den Pfad in receipt.pdfLocalPath.
  Future<void> _ensureLocalPdf(Receipt r) async {
    // Wenn bereits gesetzt und Datei existiert → fertig
    if (r.pdfLocalPath != null &&
        r.pdfLocalPath!.isNotEmpty &&
        File(r.pdfLocalPath!).existsSync()) {
      return;
    }

    // Nur für eMail-Bons sinnvoll
    if (r.emailMessageId == null || r.emailMessageId!.isEmpty) {
      return;
    }

    setState(() => _loadingPdf = true);

    try {
      // Temp-Datei von Gmail holen
      final tempPath = await _syncService.downloadReceiptPdf(
        messageId: r.emailMessageId!,
      );

      final docsDir = await getApplicationDocumentsDirectory();
      final receiptsDir = Directory('${docsDir.path}/receipts');
      if (!receiptsDir.existsSync()) {
        receiptsDir.createSync(recursive: true);
      }

      final target = File('${receiptsDir.path}/${r.id}.pdf');
      await File(tempPath).copy(target.path);

      r.pdfLocalPath = target.path;
      r.updatedAt = DateTime.now();
      await _receiptDao.insertReceipt(r);
    } catch (_) {
      // du kannst hier optional eine SnackBar zeigen
    }

    if (mounted) {
      setState(() => _loadingPdf = false);
    }
  }

  double _calcTotal() {
    if (_items.isEmpty) return widget.draftTotal ?? 0.0;
    return _items.fold<double>(0.0, (sum, it) => sum + it.totalPrice);
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

  void _openPdfPreview() {
    final r = _receipt;
    if (r == null) return;

    if (r.pdfLocalPath == null || r.pdfLocalPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kein Beleg verfügbar.',
          ),
        ),
      );
      return;
    }

    // Prüfen ob es ein Bild oder PDF ist
    if (_isImageFile(r.pdfLocalPath!)) {
      // Bild in Fullscreen anzeigen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              title: Text(r.storeName ?? 'Kassenzettel'),
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
                  File(r.pdfLocalPath!),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      // PDF anzeigen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfPreviewPage(
            pdfPath: r.pdfLocalPath!,
            title: r.storeName ?? 'Kassenzettel',
          ),
        ),
      );
    }
  }

  /// Scannt das PDF/Bild erneut und aktualisiert die Items
  Future<void> _rescanReceipt() async {
    final r = _receipt;
    if (r == null) return;
    
    if (r.pdfLocalPath == null || r.pdfLocalPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Beleg zum Scannen verfügbar.')),
      );
      return;
    }
    
    final file = File(r.pdfLocalPath!);
    if (!await file.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beleg-Datei nicht gefunden.')),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      // Bannliste-Cache leeren für aktuelle Daten
      OcrBanlist.clearCache();
      await OcrBanlist.initialize();
      
      List<LineItem> newItems = [];
      double newTotal = 0.0;
      
      if (_isImageFile(r.pdfLocalPath!)) {
        // OCR für Bilder
        const ocrService = ReceiptOcrService();
        final ocrResult = await ocrService.scanImage(r.pdfLocalPath!);
        
        newItems = ocrResult.items.map((item) {
          return LineItem()
            ..name = item.name
            ..quantity = item.quantity
            ..unitPrice = item.unitPrice
            ..totalPrice = item.totalPrice
            ..category = 'food';
        }).toList();
        
        newTotal = ocrResult.total;
        
        debugPrint('[Rescan] OCR found ${newItems.length} items, total: $newTotal');
      } else {
        // PDF Parser
        const pdfService = ReceiptPdfTextService();
        final pdfResult = await pdfService.parsePdfPath(
          r.pdfLocalPath!,
          knownStoreName: r.storeName,
        );
        
        newItems = pdfResult.items.map((item) {
          return LineItem()
            ..name = item.name
            ..quantity = item.quantity
            ..unitPrice = item.unitPrice
            ..totalPrice = item.totalPrice
            ..category = 'food';
        }).toList();
        
        newTotal = pdfResult.total;
        
        debugPrint('[Rescan] PDF found ${newItems.length} items, total: $newTotal');
      }
      
      // Items aktualisieren
      _items.clear();
      _items.addAll(newItems.map(_EditableItem.fromLineItem));
      
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${newItems.length} Artikel gefunden'),
          duration: const Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      debugPrint('[Rescan] Error: $e');
      
      if (!mounted) return;
      
      setState(() => _isLoading = false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Scannen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Prüfen ob es ein Bild oder PDF ist für das Icon
    final hasFile = _receipt?.pdfLocalPath != null && _receipt!.pdfLocalPath!.isNotEmpty;
    final isImage = hasFile && _isImageFile(_receipt!.pdfLocalPath!);

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(false); // zurück → NICHT gespeichert
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Produkte überprüfen'),
          actions: [
            // Rescan Button
            if (hasFile)
              IconButton(
                tooltip: 'Neu scannen',
                icon: const Icon(Icons.refresh),
                onPressed: _rescanReceipt,
              ),
            // PDF/Bild anzeigen
            if (hasFile)
              IconButton(
                tooltip: isImage ? 'Bild anzeigen' : 'PDF anzeigen',
                icon: Icon(isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined),
                onPressed: _openPdfPreview,
              ),
            IconButton(
              tooltip: 'Speichern',
              icon: const Icon(Icons.check),
              onPressed: _saveAndMarkLoaded,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(theme),
        floatingActionButton: FloatingActionButton(
          onPressed: _addEmptyItem,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_receipt == null) {
      return const Center(child: Text('Kassenzettel nicht gefunden.'));
    }

    final dateStr =
        DateFormat.yMMMd('de_DE').add_Hm().format(_receipt!.dateTime);
    final storeName = _receipt!.storeName ?? 'Unbekannter Händler';

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        if (_loadingPdf) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        Card(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storeName,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70),
                ),
                if (_receipt!.pdfLocalPath != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'PDF gespeichert',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Zwischensumme',
              style:
                  theme.textTheme.titleSmall?.copyWith(color: Colors.white70),
            ),
            const Spacer(),
            Text(
              '${_calcTotal().toStringAsFixed(2)} €',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                widget.addItemsIndividually
                    ? 'Keine Artikel erkannt.\nFüge manuell Artikel hinzu oder gehe zurück.'
                    : 'Keine Artikel erkannt.\nDu kannst trotzdem als "Gesamt" speichern.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else
          ...List.generate(_items.length, (i) => _buildItemCard(i, theme)),
      ],
    );
  }

  Widget _buildItemCard(int index, ThemeData theme) {
    final item = _items[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.18),
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
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
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
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
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
                      DropdownMenuItem(value: 'food', child: Text('Essen & Trinken')),
                      DropdownMenuItem(value: 'leisure', child: Text('Freizeit & Hobbies')),
                      DropdownMenuItem(value: 'fixed', child: Text('Monatliche Kosten')),
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

  Future<void> _saveAndMarkLoaded() async {
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

    // Einzeln-Modus: ohne Items nicht speichern
    if (widget.addItemsIndividually && newItems.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keine Artikel vorhanden. Bitte füge mindestens einen Artikel hinzu oder gehe zurück.',
          ),
        ),
      );
      return;
    }

    final totalFromItems =
        newItems.fold<double>(0.0, (s, it) => s + it.totalPrice);

    final total = widget.addItemsIndividually
        ? totalFromItems
        : (newItems.isEmpty ? (widget.draftTotal ?? 0.0) : totalFromItems);

    if (!widget.addItemsIndividually && total <= 0.0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gesamtsumme konnte nicht bestimmt werden. '
            'Bitte gib einen Betrag oder mindestens einen Artikel ein.',
          ),
        ),
      );
      return;
    }

    List<LineItem> finalItems;
    if (widget.addItemsIndividually) {
      finalItems = newItems;
    } else {
      final totalItem = LineItem()
        ..name = 'Gesamt'
        ..quantity = 1.0
        ..unitPrice = total
        ..totalPrice = total
        ..category = 'food';

      finalItems = [totalItem];
    }

    _receipt!
      ..total = total
      ..isLoaded = true
      ..updatedAt = DateTime.now();

    await _receiptDao.updateLineItemsForReceipt(_receipt!, finalItems);
    await _receiptDao.insertReceipt(_receipt!);
    await _receiptDao.markReceiptAsLoaded(_receipt!.id);

    if (!mounted) return;
    Navigator.of(context).pop(true);
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

  factory _EditableItem.empty() {
    return _EditableItem(
      nameController: TextEditingController(text: ''),
      qtyController: TextEditingController(text: '1'),
      priceController: TextEditingController(text: '0'),
      category: 'food',
    );
  }

  factory _EditableItem.fromLineItem(LineItem li) {
    return _EditableItem(
      nameController: TextEditingController(text: li.name),
      qtyController: TextEditingController(
        text: li.quantity.toStringAsFixed(2),
      ),
      priceController: TextEditingController(
        text: li.unitPrice.toStringAsFixed(2),
      ),
      category: li.category ?? 'food',
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