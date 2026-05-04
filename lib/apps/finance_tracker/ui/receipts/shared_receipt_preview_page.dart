import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/receipt_dao.dart';
import '../../models/receipt_models.dart';
import '../../services/receipt_ocr_service.dart';
import '../../services/receipt_pdf_text_service.dart';
import '../../services/share_intent_service.dart';
import 'scan_preview_page.dart';

/// Seite zur Verarbeitung von geteilten Kassenzetteln
/// Geht direkt zur Artikel-Bearbeitung (wie beim Email-Scanner)
class SharedReceiptPreviewPage extends StatefulWidget {
  final List<SharedFile> sharedFiles;

  const SharedReceiptPreviewPage({
    super.key,
    required this.sharedFiles,
  });

  @override
  State<SharedReceiptPreviewPage> createState() => _SharedReceiptPreviewPageState();
}

class _SharedReceiptPreviewPageState extends State<SharedReceiptPreviewPage> {
  final _receiptDao = ReceiptDao();
  final _pdfService = const ReceiptPdfTextService();
  final _ocrService = const ReceiptOcrService();

  int _currentIndex = 0;
  bool _isProcessing = true;

  @override
  void initState() {
    super.initState();
    // Direkt mit der Verarbeitung der ersten Datei starten
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processCurrentFile();
    });
  }

  SharedFile get _currentFile => widget.sharedFiles[_currentIndex];

  Future<void> _processCurrentFile() async {
    setState(() => _isProcessing = true);

    try {
      // Datei parsen
      String? storeName;
      double total = 0.0;
      DateTime? receiptDateTime;
      List<LineItem> draftItems = [];

      if (_currentFile.isPdf) {
        // PDF parsen
        final parsed = await _pdfService.parsePdfPath(
          _currentFile.permanentPath,
          knownStoreName: _guessStoreFromFileName(_currentFile.fileName),
        );

        storeName = parsed.storeName ?? _guessStoreFromFileName(_currentFile.fileName);
        total = parsed.total;
        draftItems = parsed.items.map((p) {
          return LineItem()
            ..name = p.name
            ..quantity = p.quantity
            ..unitPrice = p.unitPrice
            ..totalPrice = p.totalPrice
            ..category = 'food';
        }).toList();

        debugPrint('[SharedPreview] PDF parsed: $storeName, total: $total, items: ${draftItems.length}');
      } else if (_currentFile.isImage) {
        // Bild mit OCR scannen
        debugPrint('[SharedPreview] Starting OCR scan for image...');
        final ocrResult = await _ocrService.scanImage(_currentFile.permanentPath);

        storeName = ocrResult.storeName ?? _guessStoreFromFileName(_currentFile.fileName);
        total = ocrResult.total;
        receiptDateTime = ocrResult.dateTime;
        draftItems = ocrResult.items.map((item) {
          return LineItem()
            ..name = item.name
            ..quantity = item.quantity
            ..unitPrice = item.unitPrice
            ..totalPrice = item.totalPrice
            ..category = 'food';
        }).toList();

        debugPrint('[SharedPreview] OCR parsed: $storeName, total: $total, items: ${draftItems.length}, date: $receiptDateTime');
      } else {
        storeName = _guessStoreFromFileName(_currentFile.fileName) ?? 'Geteilter Bon';
      }

      // Verwende erkanntes Datum oder aktuelles Datum als Fallback
      final receiptDate = receiptDateTime ?? DateTime.now();

      // Receipt erstellen (temporär - wird gelöscht wenn User abbricht)
      final receipt = Receipt()
        ..dateTime = receiptDate
        ..storeName = storeName ?? 'Geteilter Bon'
        ..total = total
        ..source = 'shared'
        ..pdfLocalPath = _currentFile.permanentPath
        ..isLoaded = false  // Noch nicht final geladen
        ..isBanned = false
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now();

      final savedReceipt = await _receiptDao.insertReceipt(receipt);

      if (!mounted) return;

      // Direkt zur Artikel-Bearbeitungsseite (wie beim Email-Scanner)
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ScanPreviewPage(
            receiptId: savedReceipt.id,
            addItemsIndividually: true,
            draftItems: draftItems,
            draftTotal: total,
          ),
        ),
      );

      // Wenn User NICHT bestätigt hat, Receipt wieder löschen
      if (changed != true) {
        await _receiptDao.deleteReceipt(savedReceipt.id);
        debugPrint('[SharedPreview] Receipt ${savedReceipt.id} deleted (user cancelled)');
        
        // Wenn es noch mehr Dateien gibt, zur nächsten
        if (_currentIndex < widget.sharedFiles.length - 1) {
          setState(() => _currentIndex++);
          _processCurrentFile();
          return;
        } else {
          // Letzte Datei - zurück
          if (mounted) Navigator.of(context).pop(false);
          return;
        }
      }

      // User hat bestätigt - nächste Datei oder fertig
      if (_currentIndex < widget.sharedFiles.length - 1) {
        setState(() => _currentIndex++);
        _processCurrentFile();
      } else {
        // Alle Dateien verarbeitet
        if (mounted) Navigator.of(context).pop(true);
      }

    } catch (e) {
      debugPrint('[SharedPreview] Error: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Verarbeiten: $e'),
          backgroundColor: Colors.red,
        ),
      );

      // Bei Fehler zur nächsten Datei oder zurück
      if (_currentIndex < widget.sharedFiles.length - 1) {
        setState(() => _currentIndex++);
        _processCurrentFile();
      } else {
        Navigator.of(context).pop(false);
      }
    }
  }

  String? _guessStoreFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    final stores = {
      'lidl': 'LIDL',
      'rewe': 'REWE',
      'aldi': 'ALDI',
      'edeka': 'EDEKA',
      'kaufland': 'Kaufland',
      'netto': 'Netto',
      'penny': 'PENNY',
      'rossmann': 'Rossmann',
      'dm': 'dm',
    };

    for (final entry in stores.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileCount = widget.sharedFiles.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'Kassenzettel wird verarbeitet...',
                  style: theme.textTheme.titleMedium,
                ),
                if (fileCount > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Datei ${_currentIndex + 1} von $fileCount',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[400],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _currentFile.fileName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}