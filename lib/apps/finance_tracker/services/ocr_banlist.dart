import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Bannliste für OCR-Produkterkennung
/// 
/// Diese Klasse lädt die Bannliste aus einer lokalen Datei,
/// damit der Benutzer sie in der App bearbeiten kann.
class OcrBanlist {
  static List<String>? _cachedEntries;
  static DateTime? _lastLoad;

  /// Lädt die Bannliste aus der Datei (mit Caching)
  static Future<List<String>> _loadEntries() async {
    // Cache für 5 Sekunden
    if (_cachedEntries != null && _lastLoad != null) {
      if (DateTime.now().difference(_lastLoad!).inSeconds < 5) {
        return _cachedEntries!;
      }
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/ocr_banlist.txt');
      
      if (await file.exists()) {
        final content = await file.readAsString();
        final entries = content
            .split('\n')
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty && !e.startsWith('#'))
            .toList();
        
        _cachedEntries = entries;
        _lastLoad = DateTime.now();
        return entries;
      }
    } catch (e) {
      debugPrint('[OcrBanlist] Error loading file: $e');
    }

    // Fallback: Default-Einträge
    return _defaultEntries;
  }

  /// Synchrone Prüfung mit gecachten Daten
  /// Falls noch nicht geladen, wird die Default-Liste verwendet
  static bool shouldIgnore(String line) {
    final lower = line.toLowerCase().trim();
    
    // Leere oder sehr kurze Zeilen
    if (lower.length < 3) return true;
    
    // Nur Zahlen, Sonderzeichen oder Whitespace
    if (RegExp(r'^[\s\-\*\=\#\.\d\,]+$').hasMatch(lower)) return true;
    
    // Lange Zahlenfolgen (IDs, Transaktionsnummern)
    if (RegExp(r'^\d{4,}').hasMatch(lower)) return true;
    
    // Exakte Matches
    if (_exactMatches.contains(lower)) return true;
    
    // Prozent-Zeilen (MwSt)
    if (_isPercentLine(lower)) return true;
    
    // Contains Matches aus Cache oder Default
    final entries = _cachedEntries ?? _defaultEntries;
    for (final word in entries) {
      if (lower.contains(word)) {
        debugPrint('[OcrBanlist] Blocked: "$line" (matched: "$word")');
        return true;
      }
    }
    
    return false;
  }

  /// Asynchrone Prüfung - lädt die Datei falls nötig
  static Future<bool> shouldIgnoreAsync(String line) async {
    final lower = line.toLowerCase().trim();
    
    // Leere oder sehr kurze Zeilen
    if (lower.length < 3) return true;
    
    // Nur Zahlen, Sonderzeichen oder Whitespace
    if (RegExp(r'^[\s\-\*\=\#\.\d\,]+$').hasMatch(lower)) return true;
    
    // Lange Zahlenfolgen (IDs, Transaktionsnummern)
    if (RegExp(r'^\d{4,}').hasMatch(lower)) return true;
    
    // Exakte Matches
    if (_exactMatches.contains(lower)) return true;
    
    // Prozent-Zeilen (MwSt)
    if (_isPercentLine(lower)) return true;
    
    // Contains Matches aus Datei
    final entries = await _loadEntries();
    for (final word in entries) {
      if (lower.contains(word)) {
        debugPrint('[OcrBanlist] Blocked: "$line" (matched: "$word")');
        return true;
      }
    }
    
    return false;
  }

  /// Initialisiert die Bannliste (sollte beim App-Start aufgerufen werden)
  static Future<void> initialize() async {
    await _loadEntries();
  }

  /// Leert den Cache (nach Änderungen in der Editor-Seite aufrufen)
  static void clearCache() {
    _cachedEntries = null;
    _lastLoad = null;
  }

  /// Prozent-Muster die ignoriert werden (MwSt-Zeilen)
  static bool _isPercentLine(String line) {
    return RegExp(r'^\s*[ab]?\s*\d+\s*%', caseSensitive: false).hasMatch(line);
  }

  /// Wörter die EXAKT matchen müssen
  static const List<String> _exactMatches = [
    'eur',
    'a',
    'b',
    'netto',
    'brutto',
    'betrag',
    'summe',
    'total',
    'gesamt',
  ];

  /// Default-Einträge falls keine Datei existiert
  static const List<String> _defaultEntries = [
    // Summen & Zahlungen
    'summe',
    'total',
    'gesamt',
    'zu zahlen',
    'gegeben',
    'zurück',
    'wechselgeld',
    'restgeld',
    'betrag',
    
    // Steuern
    'mwst',
    'ust',
    'steuer',
    'netto',
    'brutto',
    'steuersatz',
    
    // Zahlungsmethoden
    'kreditkarte',
    'ec-cash',
    'kartenzahlung',
    'mastercard',
    'visa',
    'girocard',
    'bargeld',
    'kontaktlos',
    'bezahlung',
    
    // Bon-Infos
    'bon-nr',
    'beleg-nr',
    'kasse',
    'filiale',
    'datum',
    'uhrzeit',
    'vielen dank',
    'auf wiedersehen',
    'einkauf getätigt',
    'details zur',
    
    // Kontakt & Adresse
    'tel',
    'fax',
    'www.',
    'http',
    '.de',
    '.com',
    'iban',
    'bic',
    'ust-id',
    'str.',
    'straße',
    'platz',
    
    // TSE & Technisches
    'tse',
    'seriennr',
    'prüfwert',
    'signatur',
    'transaktion',
    'autorisierung',
    'terminal',
    'emv-daten',
    'ta-nr',
    'kartennr',
    'vu-nummer',
    'antwortcode',
    't-id',
    
    // Rabatte & Sparen
    'gespart',
    'preisvorteil',
    'sie sparen',
    'rabatt',
    'lidl plus',
    'payback',
    'coupon',
    'gutschein',
    
    // Pfand
    'pfand',
    'pfand 0',
    'einwegpfand',
    'mehrwegpfand',
    'pfandrückgabe',
    'leergut',
    
    // Sonstiges
    'kunde',
    'händler',
    'kostenlose',
    'servicenummer',
    'frankfurt',
    'preungesheim',
  ];
}