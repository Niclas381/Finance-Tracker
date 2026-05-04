import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../data/receipt_dao.dart';
import '../models/receipt_models.dart';
import 'receipt_pdf_text_service.dart';

/// Service zum Verarbeiten von Dateien, die über die Android "Teilen"-Funktion
/// in die App geteilt werden (z.B. von Lidl, REWE, etc. Apps).
class ShareIntentService {
  static final ShareIntentService instance = ShareIntentService._();
  ShareIntentService._();

  final _receiptDao = ReceiptDao();
  final _pdfService = const ReceiptPdfTextService();

  StreamSubscription<List<SharedMediaFile>>? _mediaStreamSub;
  StreamSubscription<String?>? _textStreamSub;

  /// Callback wenn neue Dateien geteilt wurden
  void Function(List<SharedFile> files)? onFilesShared;

  /// Initialisiert den Service und beginnt auf geteilte Inhalte zu hören
  void initialize() {
    // Beim App-Start: Prüfe ob App durch Share geöffnet wurde
    _checkInitialShare();

    // Während App läuft: Höre auf neue Shares
    _mediaStreamSub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleSharedMedia, onError: (e) {
      debugPrint('[ShareIntent] Media stream error: $e');
    });

    debugPrint('[ShareIntent] Service initialized');
  }

  /// Prüft ob die App durch einen Share-Intent gestartet wurde
  Future<void> _checkInitialShare() async {
    try {
      final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialMedia.isNotEmpty) {
        debugPrint('[ShareIntent] Initial media found: ${initialMedia.length} files');
        await _handleSharedMedia(initialMedia);
      }
    } catch (e) {
      debugPrint('[ShareIntent] Error checking initial share: $e');
    }
  }

  /// Verarbeitet geteilte Medien-Dateien
  Future<void> _handleSharedMedia(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    debugPrint('[ShareIntent] Received ${files.length} shared file(s)');

    final sharedFiles = <SharedFile>[];

    for (final file in files) {
      debugPrint('[ShareIntent] File: ${file.path}, type: ${file.type}, mimeType: ${file.mimeType}');

      final path = file.path;
      if (path == null || path.isEmpty) continue;

      // Prüfe ob Datei existiert
      final fileObj = File(path);
      if (!await fileObj.exists()) {
        debugPrint('[ShareIntent] File does not exist: $path');
        continue;
      }

      // Bestimme den Dateityp
      final isPdf = path.toLowerCase().endsWith('.pdf') ||
          file.mimeType?.contains('pdf') == true;
      final isImage = path.toLowerCase().endsWith('.jpg') ||
          path.toLowerCase().endsWith('.jpeg') ||
          path.toLowerCase().endsWith('.png') ||
          file.mimeType?.startsWith('image/') == true;

      if (isPdf || isImage) {
        // Kopiere in App-Verzeichnis für permanenten Zugriff
        final permanentPath = await _copyToAppDirectory(fileObj, isPdf ? 'pdf' : 'image');
        
        sharedFiles.add(SharedFile(
          originalPath: path,
          permanentPath: permanentPath,
          isPdf: isPdf,
          isImage: isImage,
          fileName: path.split('/').last,
        ));
      }
    }

    if (sharedFiles.isNotEmpty) {
      debugPrint('[ShareIntent] Processed ${sharedFiles.length} valid file(s)');
      onFilesShared?.call(sharedFiles);
    }

    // Intent als verarbeitet markieren
    ReceiveSharingIntent.instance.reset();
  }

  /// Kopiert eine Datei ins App-Verzeichnis für permanenten Zugriff
  Future<String> _copyToAppDirectory(File source, String subDir) async {
    final appDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${appDir.path}/shared_receipts/$subDir');
    
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = source.path.split('/').last;
    final targetPath = '${targetDir.path}/${timestamp}_$fileName';

    await source.copy(targetPath);
    debugPrint('[ShareIntent] Copied to: $targetPath');

    return targetPath;
  }

  /// Erstellt einen Receipt aus einer geteilten Datei
  Future<Receipt?> createReceiptFromSharedFile(SharedFile sharedFile) async {
    try {
      String? storeName;
      double total = 0.0;
      List<ParsedPdfItem> items = [];

      if (sharedFile.isPdf) {
        // PDF parsen
        final parsed = await _pdfService.parsePdfPath(
          sharedFile.permanentPath,
          knownStoreName: _guessStoreFromFileName(sharedFile.fileName),
        );
        
        storeName = parsed.storeName ?? _guessStoreFromFileName(sharedFile.fileName);
        total = parsed.total;
        items = parsed.items;
      } else {
        // Bild - Store aus Dateiname raten
        storeName = _guessStoreFromFileName(sharedFile.fileName);
      }

      // Receipt erstellen
      final receipt = Receipt()
        ..dateTime = DateTime.now()
        ..storeName = storeName ?? 'Geteilter Bon'
        ..total = total
        ..source = 'shared'
        ..pdfLocalPath = sharedFile.permanentPath
        ..isLoaded = false
        ..isBanned = false
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now();

      final savedReceipt = await _receiptDao.insertReceipt(receipt);

      // LineItems hinzufügen falls vorhanden
      if (items.isNotEmpty) {
        final lineItems = items.map((p) {
          return LineItem()
            ..name = p.name
            ..quantity = p.quantity
            ..unitPrice = p.unitPrice
            ..totalPrice = p.totalPrice
            ..category = 'food';
        }).toList();

        final freshReceipt = await _receiptDao.getReceiptById(savedReceipt.id);
        if (freshReceipt != null) {
          await _receiptDao.updateLineItemsForReceipt(freshReceipt, lineItems);
          freshReceipt.isLoaded = items.isNotEmpty;
          freshReceipt.total = total;
          await _receiptDao.insertReceipt(freshReceipt);
          return freshReceipt;
        }
      }

      return savedReceipt;
    } catch (e) {
      debugPrint('[ShareIntent] Error creating receipt: $e');
      return null;
    }
  }

  /// Versucht den Store-Namen aus dem Dateinamen zu erraten
  String? _guessStoreFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    
    if (lower.contains('lidl')) return 'LIDL';
    if (lower.contains('rewe')) return 'REWE';
    if (lower.contains('aldi')) return 'ALDI';
    if (lower.contains('edeka')) return 'EDEKA';
    if (lower.contains('kaufland')) return 'Kaufland';
    if (lower.contains('netto')) return 'Netto';
    if (lower.contains('penny')) return 'PENNY';
    if (lower.contains('rossmann')) return 'Rossmann';
    if (lower.contains('dm')) return 'dm';
    if (lower.contains('mueller') || lower.contains('müller')) return 'Müller';
    
    return null;
  }

  /// Bereinigt den Service
  void dispose() {
    _mediaStreamSub?.cancel();
    _textStreamSub?.cancel();
    debugPrint('[ShareIntent] Service disposed');
  }
}

/// Repräsentiert eine geteilte Datei
class SharedFile {
  final String originalPath;
  final String permanentPath;
  final bool isPdf;
  final bool isImage;
  final String fileName;

  SharedFile({
    required this.originalPath,
    required this.permanentPath,
    required this.isPdf,
    required this.isImage,
    required this.fileName,
  });

  @override
  String toString() => 'SharedFile($fileName, pdf: $isPdf, image: $isImage)';
}