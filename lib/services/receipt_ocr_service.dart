import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_banlist.dart';

/// Ergebnis der OCR-Texterkennung auf einem Kassenzettel-Bild
class OcrReceiptResult {
  final String rawText;
  final List<OcrReceiptItem> items;
  final double total;
  final String? storeName;
  final DateTime? dateTime;

  const OcrReceiptResult({
    required this.rawText,
    required this.items,
    required this.total,
    this.storeName,
    this.dateTime,
  });
}

/// Ein erkannter Artikel aus dem OCR-Scan
class OcrReceiptItem {
  final String name;
  final double quantity;
  final double unitPrice;
  final double totalPrice;

  const OcrReceiptItem({
    required this.name,
    this.quantity = 1.0,
    this.unitPrice = 0.0,
    required this.totalPrice,
  });

  @override
  String toString() => 'OcrReceiptItem($name, ${quantity}x, $totalPrice €)';
}

/// Service für OCR-Texterkennung auf Kassenzettel-Bildern
class ReceiptOcrService {
  const ReceiptOcrService();

  /// Führt OCR auf einem Bild aus und extrahiert Kassenzettel-Daten
  Future<OcrReceiptResult> scanImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);

      debugPrint('[OCR] ===== RAW TEXT =====');
      debugPrint(recognizedText.text);
      debugPrint('[OCR] ===== END RAW TEXT =====');

      // Methode 1: Block-basiertes Parsing (besser für Spalten-Layout)
      final blockResult = await _parseFromBlocks(recognizedText);

      // Methode 2: Zeilen-basiertes Parsing (Fallback)
      final lineResult = _parseFromLines(recognizedText.text);

      // Wähle das bessere Ergebnis
      final result = blockResult.items.length >= lineResult.items.length
          ? blockResult
          : lineResult;

      debugPrint(
          '[OCR] Block method: ${blockResult.items.length} items, Line method: ${lineResult.items.length} items');
      debugPrint('[OCR] Using: ${result == blockResult ? "Block" : "Line"} method');

      return result;
    } finally {
      await textRecognizer.close();
    }
  }

  /// Parst Text aus den erkannten Blöcken (besser für Spalten-Layout wie Lidl)
  Future<OcrReceiptResult> _parseFromBlocks(RecognizedText recognizedText) async {
    final items = <OcrReceiptItem>[];
    double total = 0.0;
    String? storeName;
    DateTime? dateTime;

    // Sammle alle Textzeilen mit Position
    final textLines = <_PositionedLine>[];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;

        final boundingBox = line.boundingBox;
        textLines.add(_PositionedLine(
          text: text,
          left: boundingBox?.left ?? 0,
          top: boundingBox?.top ?? 0,
          right: boundingBox?.right ?? 0,
        ));
      }
    }

    // Sortiere nach Y-Position (von oben nach unten)
    textLines.sort((a, b) => a.top.compareTo(b.top));

    // Store-Name erkennen
    storeName = _detectStoreName(recognizedText.text);

    // Datum erkennen
    dateTime = _extractDateTime(recognizedText.text);

    // Gruppiere Zeilen die auf gleicher Höhe sind (innerhalb 20px Toleranz)
    final groupedLines = <List<_PositionedLine>>[];
    List<_PositionedLine> currentGroup = [];
    double lastTop = -100;

    for (final line in textLines) {
      if ((line.top - lastTop).abs() < 20) {
        currentGroup.add(line);
      } else {
        if (currentGroup.isNotEmpty) {
          groupedLines.add(List.from(currentGroup));
        }
        currentGroup = [line];
      }
      lastTop = line.top;
    }
    if (currentGroup.isNotEmpty) {
      groupedLines.add(currentGroup);
    }

    // Verarbeite gruppierte Zeilen
    for (final group in groupedLines) {
      // Sortiere innerhalb der Gruppe nach X-Position (links nach rechts)
      group.sort((a, b) => a.left.compareTo(b.left));

      final combinedText = group.map((l) => l.text).join(' ');

      // Prüfe auf Summe
      final totalValue = _extractTotal(combinedText);
      if (totalValue != null && totalValue > total) {
        total = totalValue;
        continue;
      }

      // Überspringe Bannlisten-Zeilen
      if (await OcrBanlist.shouldIgnoreAsync(combinedText)) {
        debugPrint('[OCR] Skipped (banlist): $combinedText');
        continue;
      }

      // Versuche Produkt zu extrahieren
      // Bei Lidl: Links ist der Name, Rechts ist der Preis
      if (group.length >= 2) {
        // Mehrere Elemente auf gleicher Zeile = wahrscheinlich Name + Preis
        final leftPart = group.first.text;
        final rightPart = group.last.text;

        // Prüfe ob der linke Teil (Name) gebannt ist
        if (await OcrBanlist.shouldIgnoreAsync(leftPart)) {
          debugPrint('[OCR] Skipped (banlist left): $leftPart');
          continue;
        }

        // Versuche zuerst kombinierte Zeile zu parsen (für "0,39 x 3" Format)
        final item = _parseProductLine(combinedText);
        if (item != null) {
          items.add(item);
          debugPrint(
              '[OCR] Found item (combined): ${item.name} = ${item.quantity}x ${item.totalPrice} €');
          continue;
        }

        // Fallback: Einfaches Name + Preis Format
        final price = _extractPrice(rightPart);
        if (price != null && price > 0 && price < 500) {
          final name = _cleanProductName(leftPart);
          if (name.isNotEmpty &&
              name.length > 1 &&
              !OcrBanlist.shouldIgnore(name)) {
            items.add(OcrReceiptItem(
              name: name,
              quantity: 1.0,
              unitPrice: price,
              totalPrice: price,
            ));
            debugPrint('[OCR] Found item (multi-column): $name = $price €');
            continue;
          }
        }
      }

      // Einzelne Zeile - versuche Standard-Parsing
      final item = _parseProductLine(combinedText);
      if (item != null) {
        items.add(item);
        debugPrint(
            '[OCR] Found item (single line): ${item.name} = ${item.quantity}x ${item.totalPrice} €');
      }
    }

    // Falls keine Summe gefunden, berechne aus Items
    if (total == 0.0 && items.isNotEmpty) {
      total = items.fold(0.0, (sum, item) => sum + item.totalPrice);
    }

    // Entferne Items die gleich der Gesamtsumme sind (das sind Summenzeilen)
    if (total > 0) {
      items.removeWhere((item) {
        final isTotal = (item.totalPrice - total).abs() < 0.01;
        if (isTotal) {
          debugPrint('[OCR] Removed item (equals total): ${item.name}');
        }
        return isTotal;
      });
    }

    return OcrReceiptResult(
      rawText: recognizedText.text,
      items: items,
      total: total,
      storeName: storeName,
      dateTime: dateTime,
    );
  }

  /// Parst Text zeilenweise (Fallback-Methode)
  OcrReceiptResult _parseFromLines(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String? storeName;
    double total = 0.0;
    DateTime? dateTime;
    final items = <OcrReceiptItem>[];

    storeName = _detectStoreName(rawText);
    dateTime = _extractDateTime(rawText);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      final totalMatch = _extractTotal(line);
      if (totalMatch != null && totalMatch > total) {
        total = totalMatch;
        continue;
      }

      final item = _parseProductLine(line);
      if (item != null) {
        items.add(item);
      }
    }

    if (total == 0.0 && items.isNotEmpty) {
      total = items.fold(0.0, (sum, item) => sum + item.totalPrice);
    }

    return OcrReceiptResult(
      rawText: rawText,
      items: items,
      total: total,
      storeName: storeName,
      dateTime: dateTime,
    );
  }

  /// Extrahiert einen Preis aus einem Text-Fragment
  double? _extractPrice(String text) {
    // Verschiedene Preis-Formate
    final patterns = [
      // "1,99 A" oder "1,99" oder "1.99"
      RegExp(r'(\d+)[,.](\d{2})\s*[AB€]?\s*$'),
      // "EUR 1,99"
      RegExp(r'EUR\s*(\d+)[,.](\d{2})'),
      // Nur Zahl am Ende
      RegExp(r'(\d+)[,.](\d{2})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final euros = int.parse(match.group(1)!);
        final cents = int.parse(match.group(2)!);
        return euros + cents / 100.0;
      }
    }
    return null;
  }

  /// Erkennt den Store-Namen aus dem Text
  String? _detectStoreName(String text) {
    final lower = text.toLowerCase();

    final stores = {
      'lidl': 'LIDL',
      'rewe': 'REWE',
      'aldi': 'ALDI',
      'edeka': 'EDEKA',
      'kaufland': 'Kaufland',
      'netto': 'Netto',
      'penny': 'PENNY',
      'rossmann': 'Rossmann',
      'dm-drogerie': 'dm',
      'dm drogerie': 'dm',
      'müller': 'Müller',
      'mueller': 'Müller',
      'real': 'Real',
      'norma': 'Norma',
      'tegut': 'Tegut',
      'globus': 'Globus',
      'hit': 'HIT',
      'famila': 'Famila',
      'combi': 'Combi',
      'marktkauf': 'Marktkauf',
      'nahkauf': 'Nahkauf',
    };

    for (final entry in stores.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Extrahiert das Datum aus dem Text
  DateTime? _extractDateTime(String text) {
    final datePatterns = [
      RegExp(r'(\d{2})\.(\d{2})\.(\d{4})\s+(\d{2}):(\d{2})'),
      RegExp(r'(\d{2})\.(\d{2})\.(\d{2})\s+(\d{2}):(\d{2})'),
      RegExp(r'(\d{2})\.(\d{2})\.(\d{4})'),
      RegExp(r'(\d{2})\.(\d{2})\.(\d{2})'),
    ];

    for (final pattern in datePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        try {
          final day = int.parse(match.group(1)!);
          final month = int.parse(match.group(2)!);
          var year = int.parse(match.group(3)!);
          if (year < 100) year += 2000;

          int hour = 0, minute = 0;
          if (match.groupCount >= 5) {
            hour = int.parse(match.group(4)!);
            minute = int.parse(match.group(5)!);
          }
          return DateTime(year, month, day, hour, minute);
        } catch (e) {
          debugPrint('[OCR] Date parse error: $e');
        }
      }
    }
    return null;
  }

  /// Extrahiert die Gesamtsumme aus einer Zeile
  double? _extractTotal(String line) {
    final lower = line.toLowerCase();

    final totalKeywords = [
      'summe',
      'total',
      'gesamt',
      'zu zahlen',
      'betrag',
      'bar',
      'ec-cash',
      'kreditkarte',
      'kartenzahlung',
      'mastercard',
      'visa',
      'girocard',
    ];

    bool isTotalLine = false;
    for (final keyword in totalKeywords) {
      if (lower.contains(keyword)) {
        isTotalLine = true;
        break;
      }
    }

    if (!isTotalLine) return null;
    return _extractPrice(line);
  }

  /// Parst eine Produktzeile und extrahiert Name, Menge und Preis
  OcrReceiptItem? _parseProductLine(String line) {
    if (OcrBanlist.shouldIgnore(line)) return null;

    // ===== MUSTER MIT STÜCKZAHL =====

    // Muster 1: "Laugenbrezel 0,39 x 3 1,17 A" (Lidl-Format)
    // Name, Einzelpreis, x, Menge, Gesamtpreis
    final lidlPattern = RegExp(
      r'^(.+?)\s+(\d+)[,.](\d{2})\s*[xX×]\s*(\d+)\s+(\d+)[,.](\d{2})\s*[AB€]?\s*$',
    );
    var match = lidlPattern.firstMatch(line);
    if (match != null) {
      final name = _cleanProductName(match.group(1)!);
      final unitEuros = int.parse(match.group(2)!);
      final unitCents = int.parse(match.group(3)!);
      final quantity = double.parse(match.group(4)!);
      final totalEuros = int.parse(match.group(5)!);
      final totalCents = int.parse(match.group(6)!);

      final unitPrice = unitEuros + unitCents / 100.0;
      final totalPrice = totalEuros + totalCents / 100.0;

      if (name.isNotEmpty && totalPrice > 0 && totalPrice < 500) {
        debugPrint(
            '[OCR] Lidl pattern: $name, ${quantity}x $unitPrice = $totalPrice');
        return OcrReceiptItem(
          name: name,
          quantity: quantity,
          unitPrice: unitPrice,
          totalPrice: totalPrice,
        );
      }
    }

    // Muster 2: "3x Laugenbrezel 1,17 A" (Menge vorne)
    final quantityFirstPattern = RegExp(
      r'^(\d+)\s*[xX×]\s*(.+?)\s+(\d+)[,.](\d{2})\s*[AB€]?\s*$',
    );
    match = quantityFirstPattern.firstMatch(line);
    if (match != null) {
      final quantity = double.parse(match.group(1)!);
      final name = _cleanProductName(match.group(2)!);
      final euros = int.parse(match.group(3)!);
      final cents = int.parse(match.group(4)!);
      final totalPrice = euros + cents / 100.0;

      if (name.isNotEmpty && totalPrice > 0 && totalPrice < 500) {
        return OcrReceiptItem(
          name: name,
          quantity: quantity,
          unitPrice: totalPrice / quantity,
          totalPrice: totalPrice,
        );
      }
    }

    // Muster 3: "Laugenbrezel 3x 1,17 A" (Menge in der Mitte)
    final quantityMiddlePattern = RegExp(
      r'^(.+?)\s+(\d+)\s*[xX×]\s+(\d+)[,.](\d{2})\s*[AB€]?\s*$',
    );
    match = quantityMiddlePattern.firstMatch(line);
    if (match != null) {
      final name = _cleanProductName(match.group(1)!);
      final quantity = double.parse(match.group(2)!);
      final euros = int.parse(match.group(3)!);
      final cents = int.parse(match.group(4)!);
      final totalPrice = euros + cents / 100.0;

      if (name.isNotEmpty && totalPrice > 0 && totalPrice < 500) {
        return OcrReceiptItem(
          name: name,
          quantity: quantity,
          unitPrice: totalPrice / quantity,
          totalPrice: totalPrice,
        );
      }
    }

    // ===== STANDARD-MUSTER (ohne Stückzahl) =====

    // Muster 4: "Produktname    1,99 A" (mit viel Whitespace)
    final spacedPattern = RegExp(
      r'^(.+?)\s{2,}(\d+)[,.](\d{2})\s*[AB€]?\s*$',
    );
    match = spacedPattern.firstMatch(line);
    if (match != null) {
      final name = _cleanProductName(match.group(1)!);
      final euros = int.parse(match.group(2)!);
      final cents = int.parse(match.group(3)!);
      final price = euros + cents / 100.0;

      if (name.isNotEmpty &&
          name.length > 1 &&
          price > 0 &&
          price < 500 &&
          !OcrBanlist.shouldIgnore(name)) {
        return OcrReceiptItem(
          name: name,
          quantity: 1.0,
          unitPrice: price,
          totalPrice: price,
        );
      }
    }

    // Muster 5: "Produktname 1,99" (einfaches Format)
    final simplePattern = RegExp(
      r'^(.+?)\s+(\d+)[,.](\d{2})\s*[AB€]?\s*$',
    );
    match = simplePattern.firstMatch(line);
    if (match != null) {
      final name = _cleanProductName(match.group(1)!);
      final euros = int.parse(match.group(2)!);
      final cents = int.parse(match.group(3)!);
      final price = euros + cents / 100.0;

      if (name.isNotEmpty &&
          name.length > 1 &&
          price > 0 &&
          price < 500 &&
          !OcrBanlist.shouldIgnore(name)) {
        return OcrReceiptItem(
          name: name,
          quantity: 1.0,
          unitPrice: price,
          totalPrice: price,
        );
      }
    }

    // Muster 6: "1,99 Produktname" (Preis vorne)
    final priceFirstPattern = RegExp(
      r'^(\d+)[,.](\d{2})\s+(.+)$',
    );
    match = priceFirstPattern.firstMatch(line);
    if (match != null) {
      final euros = int.parse(match.group(1)!);
      final cents = int.parse(match.group(2)!);
      final price = euros + cents / 100.0;
      final name = _cleanProductName(match.group(3)!);

      if (name.isNotEmpty &&
          price > 0 &&
          price < 500 &&
          !OcrBanlist.shouldIgnore(name)) {
        return OcrReceiptItem(
          name: name,
          quantity: 1.0,
          unitPrice: price,
          totalPrice: price,
        );
      }
    }

    return null;
  }

  /// Bereinigt den Produktnamen
  String _cleanProductName(String name) {
    return name
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[*#]+'), '')
        .replaceAll(RegExp(r'\s*[AB]\s*$'), '')
        .replaceAll(RegExp(r'^EUR\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*EUR\s*$', caseSensitive: false), '')
        .trim();
  }
}

/// Hilfsklasse für positionierte Textzeilen
class _PositionedLine {
  final String text;
  final double left;
  final double top;
  final double right;

  _PositionedLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
  });
}
