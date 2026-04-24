import 'package:isar/isar.dart';

part 'receipt_models.g.dart';

/// Ein Kassenzettel – egal ob aus E-Mail, OCR oder manuell.
@Collection()
class Receipt {
  Id id = Isar.autoIncrement;

  /// Zeitpunkt des Kaufs (Datum + Uhrzeit)
  late DateTime dateTime;

  /// Gesamtsumme des Bons
  late double total;

  /// Name des Ladens (optional, kann aus Mail/Betreff/OCR kommen)
  String? storeName;

  /// Quelle: z.B. "email", "ocr", "manual", "recurring_monthly" etc.
  String source = 'manual';

  /// Wurde der Bon in der App bereits "fertig" geladen/bearbeitet?
  bool isLoaded = false;

  /// Wurde dieser Bon gebannt?
  ///
  /// Gebannte Bons:
  /// - erscheinen NICHT unter "neu"
  /// - werden bei Sync NICHT erneut als neue Bons erzeugt
  /// - werden in Statistiken ignoriert
  bool isBanned = false;

  /// Kategorie auf Bon-Level (optional, für simple manuelle Bons)
  String? category;

  /// Gmail Message-ID (nur wenn source == 'email').
  /// Damit können wir später das PDF nochmal nachladen.
  String? emailMessageId;

  /// Lokaler Pfad der PDF-Datei (app-interner Speicher)
  /// Wird gesetzt, sobald wir ein eBon-PDF herunterladen:
  ///
  ///   <app>/files/receipts/<receiptId>.pdf
  ///
  String? pdfLocalPath;

  /// Erstellungszeitpunkt in der App
  DateTime createdAt = DateTime.now();

  /// Letztes Update
  DateTime updatedAt = DateTime.now();

  /// Alle Positionen dieses Bons
  final lineItems = IsarLinks<LineItem>();
}

/// Einzelne Position / Artikel auf einem Bon.
@Collection()
class LineItem {
  Id id = Isar.autoIncrement;

  /// Name des Artikels / der Leistung
  late String name;

  /// Menge (z.B. 2 Stück)
  double quantity = 1.0;

  /// Einzelpreis
  double unitPrice = 0.0;

  /// Gesamtpreis (quantity * unitPrice)
  double totalPrice = 0.0;

  /// Kategorie für Auswertung (food, leisure, fixed, custom...)
  String? category;

  /// Referenz auf den zugehörigen Bon
  final receipt = IsarLink<Receipt>();
}

/// Einstellungen des Nutzers: Budget, Kategorie-Budgets, Sync-Optionen
@Collection()
class UserSettings {
  /// Wir verwenden immer ID = 0 für eine einzige Settings-Instanz
  Id id = 0;

  /// Monatsbudget für den großen Ring
  double monthlyBudget = 1000.0;

  /// Optionale "ideal"-Budgets pro Kategorie (Standard 3 Kategorien)
  double foodAndDrinksBudget = 400.0;
  double leisureBudget = 300.0;
  double fixedCostsBudget = 300.0;

  /// Dynamische Zusatz-Kategorien (max. 3 oder jetzt JSON)
  String? extraCategory1Name;
  double extraCategory1Budget = 0.0;

  String? extraCategory2Name;
  double extraCategory2Budget = 0.0;

  String? extraCategory3Name;
  double extraCategory3Budget = 0.0;

  /// Sync-Optionen für E-Mail-Kassenzettel
  bool allowDuplicates = false;

  /// Ab diesem Datum sollen E-Mails berücksichtigt werden
  DateTime? syncFromDate;
}
