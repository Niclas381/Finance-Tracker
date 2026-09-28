import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'ocr_banlist.dart';

/// Ein einzelner erkannter Artikel aus dem PDF.
class ParsedPdfItem {
  final String name;
  final double quantity;
  final double unitPrice;
  final double totalPrice;

  const ParsedPdfItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  @override
  String toString() =>
      'ParsedPdfItem(name=$name, qty=$quantity, unit=$unitPrice, total=$totalPrice)';
}

/// Ergebnis des PDF-Parsers.
class ParsedPdfResult {
  final List<ParsedPdfItem> items;
  final double total;
  final String? storeName;

  const ParsedPdfResult({
    required this.items,
    required this.total,
    this.storeName,
  });
}

/// Verschiedene Kassenzettel-Vorlagen (Templates).
enum ReceiptTemplateType {
  rewe,
  lidl,
  generic,
}

/// Abstrakte Basis für alle Template-Parser.
abstract class ReceiptTemplateParser {
  ParsedPdfResult parse(
    String fullText, {
    String? knownStoreName,
  });
}

/// Service:
/// 1. liest Text aus PDF
/// 2. erkennt Template (REWE, LIDL, generic)
/// 3. wendet passenden Parser an
class ReceiptPdfTextService {
  const ReceiptPdfTextService();

  Future<ParsedPdfResult> parsePdfPath(
    String pdfPath, {
    String? knownStoreName,
  }) async {
    final fullText = await _extractFullTextFromPdf(pdfPath);

    // Rohtext fürs Debugging loggen
    _debugDumpPdfText(
      '=== PDF TEXT START (${knownStoreName ?? 'unknown store'}) ===\n'
      '$fullText\n'
      '=== PDF TEXT END ===',
    );

    return parseFromText(
      fullText,
      knownStoreName: knownStoreName,
    );
  }

  ParsedPdfResult parseFromText(
    String fullText, {
    String? knownStoreName,
  }) {
    final templateType = _detectTemplate(
      fullText: fullText,
      knownStoreName: knownStoreName,
    );

    final parser = _getParser(templateType);

    return parser.parse(
      fullText,
      knownStoreName: knownStoreName,
    );
  }

  /// PDF → Volltext mit Syncfusion
  Future<String> _extractFullTextFromPdf(String pdfPath) async {
    try {
      final file = File(pdfPath);
      if (!await file.exists()) return '';

      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);

      final buffer = StringBuffer();
      final extractor = PdfTextExtractor(document);

      for (int i = 0; i < document.pages.count; i++) {
        final pageText =
            extractor.extractText(startPageIndex: i, endPageIndex: i);
        buffer.writeln(pageText);
      }

      document.dispose();
      return buffer.toString();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Fehler beim PDF-Text-Extract: $e\n$st');
      }
      return '';
    }
  }

  void _debugDumpPdfText(String text) {
    if (!kDebugMode) return;
    const chunkSize = 800;
    for (var i = 0; i < text.length; i += chunkSize) {
      final end = min(i + chunkSize, text.length);
      debugPrint(text.substring(i, end));
    }
  }

  ReceiptTemplateParser _getParser(ReceiptTemplateType type) {
    switch (type) {
      case ReceiptTemplateType.rewe:
        return ReweReceiptParser();
      case ReceiptTemplateType.lidl:
        return LidlReceiptParser();
      case ReceiptTemplateType.generic:
      default:
        return GenericReceiptParser();
    }
  }

  ReceiptTemplateType _detectTemplate({
    required String fullText,
    String? knownStoreName,
  }) {
    final upperText = fullText.toUpperCase();
    final upperStore = (knownStoreName ?? '').toUpperCase();

    if (upperStore.contains('REWE') ||
        upperText.contains('REWE E-BON') ||
        upperText.contains('REWE E BON') ||
        upperText.contains('REWE MARKT') ||
        upperText.contains('REWE')) {
      return ReceiptTemplateType.rewe;
    }

    if (upperStore.contains('LIDL') ||
        upperText.contains('LIDL') ||
        upperText.contains('LIDL-KASSENBON')) {
      return ReceiptTemplateType.lidl;
    }

    return ReceiptTemplateType.generic;
  }
}

/// Parser speziell für REWE-eBon / Kassenzettel.
/// 
/// WICHTIG: Syncfusion extrahiert den Text oft OHNE Zeilenumbrüche!
/// Das bedeutet, dass Zeilen zusammengeklebt sind:
/// "AMERIKANER                       1,19 BFLEISCHK-BROETCH                 1,90 B"
/// 
/// Daher verwenden wir ein Pattern, das nach "Preis + Steuerkennzeichen" sucht
/// und dann den Text davor als Produktnamen extrahiert.
class ReweReceiptParser implements ReceiptTemplateParser {
  @override
  ParsedPdfResult parse(
    String fullText, {
    String? knownStoreName,
  }) {
    final items = <ParsedPdfItem>[];

    // 1) Summe finden
    final total = _findTotal(fullText);

    // 2) Artikel extrahieren mit dem speziellen Pattern für zusammengeklebte Zeilen
    items.addAll(_extractItems(fullText));

    // 3) Debug-Ausgabe
    if (kDebugMode) {
      debugPrint('=== REWE PARSER RESULTS ===');
      debugPrint('Total: $total');
      debugPrint('Items found: ${items.length}');
      for (final item in items) {
        debugPrint('  - ${item.name}: ${item.totalPrice} €');
      }
      debugPrint('=== END PARSER RESULTS ===');
    }

    // 4) Fallback: keine Artikel → "Gesamt"-Artikel
    if (items.isEmpty && total > 0) {
      items.add(
        ParsedPdfItem(
          name: 'Gesamt',
          quantity: 1,
          unitPrice: total,
          totalPrice: total,
        ),
      );
    }

    final effectiveTotal =
        total > 0 ? total : items.fold<double>(0.0, (s, i) => s + i.totalPrice);

    return ParsedPdfResult(
      items: items,
      total: effectiveTotal,
      storeName: knownStoreName ?? 'REWE',
    );
  }

  /// Findet die Gesamtsumme im Text
  double _findTotal(String fullText) {
    // Pattern 1: "SUMME EUR 4,33" oder "SUMME                   EUR      4,33"
    final summeRegex = RegExp(
      r'SUMME\s+EUR\s+([\d]+[,.][\d]{2})',
      caseSensitive: false,
    );
    final summeMatch = summeRegex.firstMatch(fullText);
    if (summeMatch != null) {
      final value = _parseEuro(summeMatch.group(1)!);
      if (value > 0) return value;
    }

    // Pattern 2: "SUMME" gefolgt von Betrag irgendwo
    final summeRegex2 = RegExp(
      r'SUMME[^0-9]*([\d]+[,.][\d]{2})',
      caseSensitive: false,
    );
    final summeMatch2 = summeRegex2.firstMatch(fullText);
    if (summeMatch2 != null) {
      final value = _parseEuro(summeMatch2.group(1)!);
      if (value > 0) return value;
    }

    return 0.0;
  }

  /// Extrahiert Artikel aus dem (möglicherweise zusammengeklebten) Text
  /// 
  /// REWE-Format: "PRODUKTNAME                       PREIS STEUERKENNZEICHEN"
  /// Beispiel: "AMERIKANER                       1,19 B"
  /// 
  /// Mit Mengenangabe:
  /// "LAUGENBREZE                       0,98 B             2 Stk x     0,49"
  /// 
  /// Bei zusammengeklebten Zeilen (Syncfusion-Problem):
  /// "0,98 B             2 Stk x    0,49MONSTER PARADISE                 1,49 APFAND 0,25"
  List<ParsedPdfItem> _extractItems(String fullText) {
    final items = <ParsedPdfItem>[];
    final seenNames = <String>{};

    // ============================================================
    // SCHRITT 1: Finde den Produktbereich
    // (zwischen "EUR" Header und "---" oder "SUMME")
    // ============================================================
    String productSection = fullText;
    
    // Suche nach dem EUR-Header (Ende der Kopfzeile)
    final eurHeaderRegex = RegExp(r'EUR\s*(?=\n|[A-ZÄÖÜ])', caseSensitive: false);
    final eurMatch = eurHeaderRegex.firstMatch(fullText);
    
    // Suche nach dem Ende des Produktbereichs (Trennlinie oder SUMME)
    final endRegex = RegExp(r'(-{5,}|SUMME)', caseSensitive: false);
    final endMatch = endRegex.firstMatch(fullText);
    
    if (eurMatch != null && endMatch != null && endMatch.start > eurMatch.end) {
      productSection = fullText.substring(eurMatch.end, endMatch.start);
      
      if (kDebugMode) {
        debugPrint('=== PRODUCT SECTION ===');
        debugPrint(productSection);
        debugPrint('=== END PRODUCT SECTION ===');
      }
    }

    // ============================================================
    // SCHRITT 2: Finde alle Produkte mit globalem Pattern
    // Pattern: NAME (2+ Leerzeichen) PREIS STEUERKENNZEICHEN
    // Wichtig: Auch zusammengeklebte Zeilen parsen!
    // ============================================================
    
    // Dieses Pattern findet: "PRODUKTNAME     PREIS A/B"
    // wobei PRODUKTNAME mit Großbuchstabe beginnt und
    // mindestens 2 Leerzeichen vor dem Preis stehen
    final productPattern = RegExp(
      r'([A-ZÄÖÜ][A-ZÄÖÜ0-9\s\.\-\,\/]+?)\s{2,}(\d{1,3}[,\.]\d{2})\s*([AB])(?:\s*\*)?',
    );
    
    // Finde alle Produkt-Matches im productSection
    final matches = productPattern.allMatches(productSection).toList();
    
    if (kDebugMode) {
      debugPrint('[PDF] Found ${matches.length} product matches');
    }
    
    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      var name = match.group(1)!.trim();
      final priceStr = match.group(2)!;
      final taxCode = match.group(3)!;
      
      // Bereinige den Namen
      name = _cleanProductName(name);
      
      if (kDebugMode) {
        debugPrint('[PDF] Checking: "$name" -> $priceStr $taxCode');
      }

      // Blacklist-Check (extern + intern)
      if (_isBlacklisted(name)) {
        if (kDebugMode) {
          debugPrint('[PDF] Skipped (blacklist): $name');
        }
        continue;
      }

      // Name muss mindestens 3 Zeichen haben
      if (name.length < 3) continue;

      // Preis parsen
      final price = _parseEuro(priceStr);
      if (price <= 0 || price > 500) continue;

      // Duplikate vermeiden
      final key = '${name.toUpperCase()}_$priceStr';
      if (seenNames.contains(key)) continue;
      seenNames.add(key);
      
      // Standardwerte
      double quantity = 1.0;
      double unitPrice = price;
      double totalPrice = price;
      
      // ============================================================
      // SCHRITT 3: Suche nach Mengenangabe zwischen diesem und nächstem Produkt
      // Format: "2 Stk x 0,49" oder "2 x 0,49"
      // ============================================================
      if (i < matches.length - 1) {
        // Text zwischen diesem Match-Ende und nächstem Match-Start
        final betweenStart = match.end;
        final betweenEnd = matches[i + 1].start;
        
        if (betweenEnd > betweenStart) {
          final betweenText = productSection.substring(betweenStart, betweenEnd);
          
          // Suche nach Mengenangabe
          final qtyPattern = RegExp(
            r'(\d+)\s*(?:Stk|stk|STK|St|st|ST)?\s*[xX×]\s*(\d+[,\.]\d{2})',
          );
          final qtyMatch = qtyPattern.firstMatch(betweenText);
          
          if (qtyMatch != null) {
            quantity = double.parse(qtyMatch.group(1)!);
            unitPrice = _parseEuro(qtyMatch.group(2)!);
            // totalPrice bleibt der ursprüngliche Preis (0,98 für 2x0,49)
            
            if (kDebugMode) {
              debugPrint('[PDF] Found quantity for $name: ${quantity.toInt()}x $unitPrice');
            }
          }
        }
      } else {
        // Letztes Produkt - suche nach dem Match
        final afterText = productSection.substring(match.end);
        final qtyPattern = RegExp(
          r'(\d+)\s*(?:Stk|stk|STK|St|st|ST)?\s*[xX×]\s*(\d+[,\.]\d{2})',
        );
        final qtyMatch = qtyPattern.firstMatch(afterText);
        
        if (qtyMatch != null) {
          quantity = double.parse(qtyMatch.group(1)!);
          unitPrice = _parseEuro(qtyMatch.group(2)!);
          
          if (kDebugMode) {
            debugPrint('[PDF] Found quantity for last item $name: ${quantity.toInt()}x $unitPrice');
          }
        }
      }

      items.add(
        ParsedPdfItem(
          name: name,
          quantity: quantity,
          unitPrice: unitPrice,
          totalPrice: totalPrice,
        ),
      );
      
      if (kDebugMode) {
        debugPrint('[PDF] Added: $name (${quantity}x $unitPrice = $totalPrice)');
      }
    }

    // ============================================================
    // SCHRITT 4: Fallback - wenn keine Items gefunden, ganzen Text durchsuchen
    // ============================================================
    if (items.isEmpty) {
      if (kDebugMode) {
        debugPrint('[PDF] No items in product section, trying full text...');
      }
      
      for (final match in productPattern.allMatches(fullText)) {
        var name = match.group(1)!.trim();
        final priceStr = match.group(2)!;

        name = _cleanProductName(name);
        if (_isBlacklisted(name)) continue;
        if (name.length < 3) continue;

        final price = _parseEuro(priceStr);
        if (price <= 0 || price > 500) continue;

        final key = '${name.toUpperCase()}_$priceStr';
        if (seenNames.contains(key)) continue;
        seenNames.add(key);

        items.add(
          ParsedPdfItem(
            name: name,
            quantity: 1,
            unitPrice: price,
            totalPrice: price,
          ),
        );
      }
    }

    if (kDebugMode) {
      debugPrint('[PDF] Final items count: ${items.length}');
    }

    return items;
  }

  /// Bereinigt den Produktnamen
  String _cleanProductName(String name) {
    // Entferne führende/trailing Leerzeichen
    var cleaned = name.trim();
    
    // Entferne mehrfache Leerzeichen
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    
    // Entferne Sternchen
    cleaned = cleaned.replaceAll('*', '').trim();
    
    // Wenn komplett Großbuchstaben, mache es lesbar (erster groß, Rest klein)
    if (cleaned == cleaned.toUpperCase() && cleaned.length > 2) {
      // Aber behalte Abkürzungen wie "RED BULL" lesbar
      final words = cleaned.split(' ');
      cleaned = words.map((word) {
        if (word.length <= 2) return word; // Kurze Wörter behalten
        return word[0] + word.substring(1).toLowerCase();
      }).join(' ');
    }
    
    return cleaned;
  }

  /// Prüft ob der Name auf der Blacklist steht
  bool _isBlacklisted(String name) {
    final upper = name.toUpperCase();
    final lower = name.toLowerCase();
    
    // Erst externe Bannliste prüfen
    if (OcrBanlist.shouldIgnore(name)) {
      return true;
    }
    
    final blacklist = [
      'SUMME',
      'EUR',
      'BETRAG',
      'STEUER',
      'NETTO',
      'BRUTTO',
      'DATUM',
      'UHRZEIT',
      'KASSE',
      'MARKT',
      'BELEG',
      'TRACE',
      'TERMINAL',
      'APPROVED',
      'ZAHLUNG',
      'MASTERCARD',
      'VISA',
      'GIROCARD',
      'EC-KARTE',
      'BONUS',
      'RABATT',
      'COUPON',
      'GESAMTBETRAG',
      'VU-NR',
      'POS-INFO',
      'TSE',
      'SERIENNUMMER',
      'BON-NR',
      'BED',
      'MWST',
      'UST',
      'STEUERNUMMER',
      'ZWISCHENSUMME',
      'BAR',
      'GEGEBEN',
      'RÜCKGELD',
      'ZURÜCK',
      'PAYBACK',
      'PUNKTE',
      'TRANSAKTION',
      'GENEHMIGT',
      'AUTORISIERUNG',
      'KARTENZAHLUNG',
      'KONTAKTLOS',
      'CONTACTLESS',
      'REWE',
      'FILIALE',
      'VIELEN DANK',
      'DANKE',
      'KUNDENBELEG',
      'GEG',
      'UID',
      'FRANKFURT',
      // Spezifische Ausschlüsse
      'DEBIT',
      'HVB',
      'NR',
      // Pfand
      'PFAND',
      'EINWEGPFAND',
      'MEHRWEGPFAND',
      'LEERGUT',
    ];

    for (final word in blacklist) {
      // Exakter Match oder beginnt/endet mit dem Wort
      if (upper == word || upper.startsWith('$word ') || upper.startsWith('$word-') || 
          upper.endsWith(' $word') || upper.endsWith('-$word')) {
        return true;
      }
    }
    
    // Spezielle Wörter die irgendwo vorkommen können
    final containsBlacklist = [
      'PFAND', 'RABATT', 'COUPON', 'BONUS', 'STEUER', 'MWST', 'SUMME', 
      'BETRAG', 'ZAHLUNG', 'GEGEBEN', 'RÜCKGELD',
    ];
    for (final word in containsBlacklist) {
      if (upper.contains(word)) return true;
    }

    // Zu kurze Namen (nach Bereinigung)
    final cleanedUpper = upper.replaceAll(RegExp(r'\s+'), '');
    if (cleanedUpper.length < 3) return true;

    // Namen die nur aus Zahlen und Sonderzeichen bestehen
    if (RegExp(r'^[\d\s\.\-\,\:\/]+$').hasMatch(upper)) return true;

    return false;
  }
}

/// Parser für LIDL Kassenzettel
class LidlReceiptParser implements ReceiptTemplateParser {
  @override
  ParsedPdfResult parse(
    String fullText, {
    String? knownStoreName,
  }) {
    final items = <ParsedPdfItem>[];
    final seenNames = <String>{};

    final total = _findTotal(fullText);

    // Ähnliches Pattern wie REWE
    final itemPattern = RegExp(
      r'([A-ZÄÖÜ][A-ZÄÖÜa-zäöüß0-9\s\.\-\,]+?)\s+(\d{1,2}[,\.]\d{2})\s*([AB])?',
    );

    for (final match in itemPattern.allMatches(fullText)) {
      var name = match.group(1)!.trim();
      final priceStr = match.group(2)!;

      name = _cleanName(name);
      if (_isBlacklisted(name)) continue;
      if (name.length < 2) continue;

      final price = _parseEuro(priceStr);
      if (price <= 0 || price > 500) continue;

      final key = '${name.toUpperCase()}_$priceStr';
      if (seenNames.contains(key)) continue;
      seenNames.add(key);

      items.add(
        ParsedPdfItem(
          name: name,
          quantity: 1,
          unitPrice: price,
          totalPrice: price,
        ),
      );
    }

    if (items.isEmpty && total > 0) {
      items.add(
        ParsedPdfItem(
          name: 'Gesamt',
          quantity: 1,
          unitPrice: total,
          totalPrice: total,
        ),
      );
    }

    final effectiveTotal =
        total > 0 ? total : items.fold<double>(0.0, (s, i) => s + i.totalPrice);

    return ParsedPdfResult(
      items: items,
      total: effectiveTotal,
      storeName: knownStoreName ?? 'LIDL',
    );
  }

  String _cleanName(String name) {
    var cleaned = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned == cleaned.toUpperCase() && cleaned.length > 2) {
      cleaned = cleaned[0] + cleaned.substring(1).toLowerCase();
    }
    return cleaned;
  }

  bool _isBlacklisted(String name) {
    // Erst externe Bannliste prüfen
    if (OcrBanlist.shouldIgnore(name)) {
      return true;
    }
    
    final upper = name.toUpperCase();
    final blacklist = [
      'SUMME', 'BETRAG', 'STEUER', 'NETTO', 'BRUTTO', 'DATUM', 'UHRZEIT',
      'KASSE', 'MARKT', 'BELEG', 'TERMINAL', 'ZAHLUNG', 'MASTERCARD', 'VISA',
      'GIROCARD', 'BONUS', 'RABATT', 'COUPON', 'GESAMTBETRAG', 'MWST', 'UST',
      'BAR', 'GEGEBEN', 'RÜCKGELD', 'LIDL', 'FILIALE', 'DANKE', 'EUR',
      'PFAND', 'EINWEGPFAND', 'MEHRWEGPFAND', 'LEERGUT', 'LIDL PLUS',
    ];
    for (final word in blacklist) {
      if (upper.contains(word)) return true;
    }
    return false;
  }

  double _findTotal(String fullText) {
    final summeRegex = RegExp(
      r'SUMME[^0-9]*([\d]+[,.][\d]{2})',
      caseSensitive: false,
    );
    final match = summeRegex.firstMatch(fullText);
    if (match != null) {
      return _parseEuro(match.group(1)!);
    }
    return 0.0;
  }
}

/// Generischer Fallback-Parser
class GenericReceiptParser implements ReceiptTemplateParser {
  @override
  ParsedPdfResult parse(
    String fullText, {
    String? knownStoreName,
  }) {
    final items = <ParsedPdfItem>[];
    final seenNames = <String>{};

    final total = _findTotal(fullText);

    // Versuche Produkte zu finden
    final itemPattern = RegExp(
      r'([A-ZÄÖÜ][A-ZÄÖÜa-zäöüß0-9\s\.\-\,]+?)\s+(\d{1,2}[,\.]\d{2})',
    );

    for (final match in itemPattern.allMatches(fullText)) {
      var name = match.group(1)!.trim();
      final priceStr = match.group(2)!;

      name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (_isBlacklisted(name)) continue;
      if (name.length < 2) continue;

      final price = _parseEuro(priceStr);
      if (price <= 0 || price > 1000) continue;

      final key = '${name.toUpperCase()}_$priceStr';
      if (seenNames.contains(key)) continue;
      seenNames.add(key);

      items.add(
        ParsedPdfItem(
          name: name,
          quantity: 1,
          unitPrice: price,
          totalPrice: price,
        ),
      );
    }

    if (items.isEmpty && total > 0) {
      items.add(
        ParsedPdfItem(
          name: 'Gesamt',
          quantity: 1,
          unitPrice: total,
          totalPrice: total,
        ),
      );
    }

    final effectiveTotal =
        total > 0 ? total : items.fold<double>(0.0, (s, i) => s + i.totalPrice);

    return ParsedPdfResult(
      items: items,
      total: effectiveTotal,
      storeName: knownStoreName ?? 'Unbekannter Händler',
    );
  }

  bool _isBlacklisted(String name) {
    // Erst externe Bannliste prüfen
    if (OcrBanlist.shouldIgnore(name)) {
      return true;
    }
    
    final upper = name.toUpperCase();
    final blacklist = [
      'SUMME', 'BETRAG', 'STEUER', 'NETTO', 'BRUTTO', 'DATUM', 'UHRZEIT',
      'KASSE', 'BELEG', 'TERMINAL', 'ZAHLUNG', 'MASTERCARD', 'VISA',
      'GIROCARD', 'RABATT', 'COUPON', 'GESAMTBETRAG', 'MWST', 'UST',
      'BAR', 'GEGEBEN', 'RÜCKGELD', 'DANKE', 'EUR',
      'PFAND', 'EINWEGPFAND', 'MEHRWEGPFAND', 'LEERGUT',
    ];
    for (final word in blacklist) {
      if (upper.contains(word)) return true;
    }
    return false;
  }

  double _findTotal(String fullText) {
    final patterns = [
      RegExp(r'SUMME[^0-9]*([\d]+[,.][\d]{2})', caseSensitive: false),
      RegExp(r'GESAMT[^0-9]*([\d]+[,.][\d]{2})', caseSensitive: false),
      RegExp(r'TOTAL[^0-9]*([\d]+[,.][\d]{2})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(fullText);
      if (match != null) {
        final value = _parseEuro(match.group(1)!);
        if (value > 0) return value;
      }
    }

    return 0.0;
  }
}

/// Hilfsfunktion: "12,34" / "1.234,56" / "12.34" → 12.34
double _parseEuro(String input) {
  var s = input.trim();

  // Tausenderpunkt/-komma entfernen
  if (s.contains('.') && s.contains(',')) {
    s = s.replaceAll('.', '');
  }
  if (s.contains(',')) {
    s = s.replaceAll(',', '.');
  }

  return double.tryParse(s) ?? 0.0;
}