import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/receipt_dao.dart';
import '../../data/settings_dao.dart';
import '../../models/receipt_models.dart';
import '../../services/receipt_ocr_service.dart';
import '../../services/ocr_banlist.dart';
import 'widgets/budget_ring.dart';
import 'widgets/category_wheel.dart';
import '../receipts/receipts_page.dart';
import '../receipts/scan_preview_page.dart';
import '../history/history_page.dart';
import '../history/day_details_page.dart';
import '../statistics/statistics_page.dart';
import '../../services/receipt_cleanup_service.dart';
import '../statistics/category_details_page.dart';
import '../settings/ocr_banlist_editor_page.dart';

import '../../platform/inbound_message_bridge.dart';
import '../../services/message_ingestion_manager.dart';
import '../../services/message_payment_recognition_service.dart';

class FinanceHomePage extends StatefulWidget {
  const FinanceHomePage({super.key});

  @override
  State<FinanceHomePage> createState() => _FinanceHomePageState();
}

/// Dynamische Kategorie mit Budget & aktuellem Verbrauch
class _DynamicCategory {
  final String name;
  double budget;
  double spent;

  _DynamicCategory({
    required this.name,
    required this.budget,
    required this.spent,
  });
}

class _FinanceHomePageState extends State<FinanceHomePage> {
  final _receiptDao = ReceiptDao();
  final _settingsDao = SettingsDao();

  UserSettings? _settings;
  double _totalThisMonth = 0.0;
  double _totalToday = 0.0;
  double _foodThisMonth = 0.0;
  double _leisureThisMonth = 0.0;
  double _fixedThisMonth = 0.0;
  bool _isLoading = true;
  bool _isEditMode = false;

  // Nachrichtenerkennung (SMS + Benachrichtigungen)
  final InboundMessageBridge _inboundBridge = InboundMessageBridge();
  bool _msgIngestionEnabled = false;
  bool _notifAccessEnabled = false;

  /// Unbegrenzt viele dynamische Kategorien
  List<_DynamicCategory> _dynamicCategories = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadMessageIngestionState();
  }

  /// Hilfsfunktion: Summe für eine Kategorie im Monat aus einer bestehenden
  /// Receipt-Liste berechnen (ignoriert gebannte Bons).
  double _sumCategoryInMonth(
    String categoryKey,
    DateTime month,
    List<Receipt> receipts,
  ) {
    double sum = 0.0;

    for (final r in receipts) {
      if (r.isBanned) continue;

      final d = r.dateTime;
      if (d.year != month.year || d.month != month.month) continue;

      for (final item in r.lineItems) {
        if (item.category == categoryKey) {
          sum += item.totalPrice;
        }
      }
    }

    return sum;
  }

  bool _importingInbound = false;

  Future<void> _importPendingInboundMessages({bool showSnack = true}) async {
    if (_importingInbound) return;
    if (!_msgIngestionEnabled) return;

    _importingInbound = true;
    try {
      final pending = await _inboundBridge.getPendingMessages();
      if (pending.isEmpty) return;

      final svc = MessagePaymentRecognitionService(_receiptDao);
      final summary = await svc.importMessages(pending, debugLogs: true);

      // Clear queue AFTER successful import so they don't get re-imported.
      await _inboundBridge.clearPendingMessages();

      await _loadData();

      if (showSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import: scanned=${summary.scanned}, detected=${summary.detected}, '
              'inserted=${summary.inserted}, skipped=${summary.skippedBecauseReceiptExists}, '
              'deleted=${summary.deletedMessageDuplicates}',
            ),
          ),
        );
      }
    } finally {
      _importingInbound = false;
    }
  }


  Future<void> _loadData() async {
    final now = DateTime.now();

    // Fallback-Items für alte Bons auffüllen
    await ReceiptCleanupService(_receiptDao).addFallbackItemsToEmptyReceipts();

    final settings = await _settingsDao.getSettings();

    // Wir ziehen ALLE Receipts und rechnen im Speicher – wie bei "Heute ausgegeben".
    final allReceipts = await _receiptDao.getAllReceipts();

    double totalMonth = 0.0;
    double totalToday = 0.0;
    double food = 0.0;
    double leisure = 0.0;
    double fixed = 0.0;

    for (final r in allReceipts) {
      if (r.isBanned) continue; // gebannte Bons komplett ignorieren

      final d = r.dateTime;
      final sameMonth = (d.year == now.year && d.month == now.month);
      final sameDay = sameMonth && d.day == now.day;

      // Effektive Summe für den Bon:
      // - wenn total > 0 → nehmen
      // - sonst Fallback: Summe der LineItems
      double effectiveTotal = r.total;
      if (effectiveTotal <= 0.0) {
        effectiveTotal = r.lineItems.fold<double>(
          0.0,
          (s, li) => s + li.totalPrice,
        );
      }

      if (sameMonth) {
        totalMonth += effectiveTotal;

        // Kategorien über LineItems summieren
        for (final li in r.lineItems) {
          final amount = li.totalPrice;
          switch (li.category) {
            case 'food':
              food += amount;
              break;
            case 'leisure':
              leisure += amount;
              break;
            case 'fixed':
              fixed += amount;
              break;
            default:
              // dynamische Kategorien werden separat behandelt
              break;
          }
        }
      }

      if (sameDay) {
        totalToday += effectiveTotal;
      }
    }

    // Dynamische Kategorien aus Settings + gleichen Receipt-Daten berechnen
    final dynamicCategories =
        await _loadDynamicCategoriesFromSettings(settings, now, allReceipts);

    if (!mounted) return;

    setState(() {
      _settings = settings;
      _totalThisMonth = totalMonth;
      _totalToday = totalToday;
      _foodThisMonth = food;
      _leisureThisMonth = leisure;
      _fixedThisMonth = fixed;
      _dynamicCategories = dynamicCategories;
      _isLoading = false;
    });
  }

  Future<List<_DynamicCategory>> _loadDynamicCategoriesFromSettings(
    UserSettings settings,
    DateTime now,
    List<Receipt> allReceipts,
  ) async {
    final result = <_DynamicCategory>[];

    List<Map<String, dynamic>> entries = [];

    final raw = settings.extraCategory1Name;
    if (raw != null && raw.trim().isNotEmpty && raw.trim().startsWith('[')) {
      // Neuer JSON-Modus
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) {
              final name = (e['name'] ?? '').toString().trim();
              if (name.isEmpty) continue;
              final budgetNum = e['budget'];
              final budget = budgetNum is num ? budgetNum.toDouble() : 0.0;
              entries.add({'name': name, 'budget': budget});
            }
          }
        }
      } catch (_) {
        // Falls JSON kaputt ist, ignorieren und Legacy-Felder nutzen
      }
    }

    // Fallback / Migration von alten Feldern
    if (entries.isEmpty) {
      if (settings.extraCategory1Name != null &&
          settings.extraCategory1Name!.isNotEmpty) {
        entries.add({
          'name': settings.extraCategory1Name!,
          'budget': settings.extraCategory1Budget,
        });
      }
      if (settings.extraCategory2Name != null &&
          settings.extraCategory2Name!.isNotEmpty) {
        entries.add({
          'name': settings.extraCategory2Name!,
          'budget': settings.extraCategory2Budget,
        });
      }
      if (settings.extraCategory3Name != null &&
          settings.extraCategory3Name!.isNotEmpty) {
        entries.add({
          'name': settings.extraCategory3Name!,
          'budget': settings.extraCategory3Budget,
        });
      }
    }

    for (final e in entries) {
      final name = e['name'] as String;
      final budget = (e['budget'] as num?)?.toDouble() ?? 0.0;
      final spent = _sumCategoryInMonth(name, now, allReceipts);
      result.add(
        _DynamicCategory(
          name: name,
          budget: budget,
          spent: spent,
        ),
      );
    }

    return result;
  }

  Future<void> _saveDynamicCategoriesToSettings() async {
    if (_settings == null) return;

    final listJson = _dynamicCategories
        .map((c) => {
              'name': c.name,
              'budget': c.budget,
            })
        .toList();

    _settings!
      ..extraCategory1Name =
          listJson.isEmpty ? null : jsonEncode(listJson)
      ..extraCategory1Budget = 0.0
      ..extraCategory2Name = null
      ..extraCategory2Budget = 0.0
      ..extraCategory3Name = null
      ..extraCategory3Budget = 0.0;

    await _settingsDao.updateSettings(_settings!);
  }

  Future<void> _changeMonthlyBudget() async {
    if (_settings == null) return;

    final controller = TextEditingController(
      text: _settings!.monthlyBudget.toStringAsFixed(0),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Monatsbudget ändern'),
          content: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monatsbudget in €',
            ),
          ),
          actions: [

            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                final value =
                    double.tryParse(controller.text.replaceAll(',', '.'));
                Navigator.of(context).pop(value);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (result != null && result > 0) {
      _settings!.monthlyBudget = result;
      await _settingsDao.updateSettings(_settings!);
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _changeCategoryBudget(String categoryKey, String label) async {
    if (_settings == null) return;

    double currentBudget;
    switch (categoryKey) {
      case 'food':
        currentBudget = _settings!.foodAndDrinksBudget;
        break;
      case 'leisure':
        currentBudget = _settings!.leisureBudget;
        break;
      case 'fixed':
        currentBudget = _settings!.fixedCostsBudget;
        break;
      default:
        currentBudget = 0;
    }

    final controller = TextEditingController(
      text: currentBudget.toStringAsFixed(0),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Budget für $label ändern'),
          content: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Budget in €',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                final value =
                    double.tryParse(controller.text.replaceAll(',', '.'));
                Navigator.of(context).pop(value);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (result != null && result > 0) {
      switch (categoryKey) {
        case 'food':
          _settings!.foodAndDrinksBudget = result;
          break;
        case 'leisure':
          _settings!.leisureBudget = result;
          break;
        case 'fixed':
          _settings!.fixedCostsBudget = result;
          break;
      }
      await _settingsDao.updateSettings(_settings!);
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _changeDynamicCategoryBudget(_DynamicCategory category) async {
    if (_settings == null) return;

    final controller = TextEditingController(
      text: category.budget.toStringAsFixed(0),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Budget für ${category.name} ändern'),
          content: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Budget in €',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                final value =
                    double.tryParse(controller.text.replaceAll(',', '.'));
                Navigator.of(context).pop(value);
              },
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (result != null && result > 0) {
      category.budget = result;
      await _saveDynamicCategoriesToSettings();
      await _loadData();
    }
  }

  Future<void> _addDynamicCategory() async {
    if (_settings == null) return;

    final nameController = TextEditingController();
    final budgetController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neue Kategorie hinzufügen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name der Kategorie',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budgetController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Budget in €',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    final name = nameController.text.trim();
    final budget =
        double.tryParse(budgetController.text.replaceAll(',', '.')) ?? 0.0;

    if (name.isEmpty || budget <= 0) {
      return;
    }

    final existingNames = <String>[
      'food',
      'leisure',
      'fixed',
      ..._dynamicCategories.map((c) => c.name),
    ];
    if (existingNames.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dieser Kategoriename wird bereits verwendet.'),
        ),
      );
      return;
    }

    final allReceipts = await _receiptDao.getAllReceipts();
    final now = DateTime.now();
    final spent = _sumCategoryInMonth(name, now, allReceipts);

    _dynamicCategories.add(
      _DynamicCategory(name: name, budget: budget, spent: spent),
    );

    await _saveDynamicCategoriesToSettings();
    await _loadData();
  }

  Future<void> _confirmDeleteDynamicCategory(_DynamicCategory category) async {
    if (_settings == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kategorie löschen'),
          content: Text(
            'Möchtest du die Kategorie "${category.name}" wirklich löschen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    _dynamicCategories.removeWhere((c) => c.name == category.name);
    await _saveDynamicCategoriesToSettings();
    await _loadData();
  }

  /// Öffnet die Kamera zum Scannen eines Kassenzettels
  Future<void> _openReceiptScanner() async {
    final picker = ImagePicker();
    
    // Bottom Sheet für Auswahl: Kamera oder Galerie
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Kamera'),
                  subtitle: const Text('Kassenzettel fotografieren'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Galerie'),
                  subtitle: const Text('Bild aus Galerie wählen'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
    
    if (source == null) return;
    
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      
      if (pickedFile == null) return;
      
      if (!mounted) return;
      
      // Loading anzeigen
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Kassenzettel wird gescannt...'),
                ],
              ),
            ),
          ),
        ),
      );
      
      // Bild in App-Verzeichnis kopieren
      final appDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${appDir.path}/scanned_receipts');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'scan_$timestamp.jpg';
      final permanentPath = '${targetDir.path}/$fileName';
      
      await File(pickedFile.path).copy(permanentPath);
      
      // OCR ausführen
      const ocrService = ReceiptOcrService();
      final ocrResult = await ocrService.scanImage(permanentPath);
      
      if (!mounted) return;
      Navigator.of(context).pop(); // Loading schließen
      
      // Erkanntes Datum oder heute
      final receiptDate = ocrResult.dateTime ?? DateTime.now();
      
      // Receipt erstellen
      final receipt = Receipt()
        ..dateTime = receiptDate
        ..storeName = ocrResult.storeName ?? 'Gescannter Bon'
        ..total = ocrResult.total
        ..source = 'scan'
        ..pdfLocalPath = permanentPath
        ..isLoaded = ocrResult.items.isNotEmpty
        ..isBanned = false
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now();
      
      final savedReceipt = await _receiptDao.insertReceipt(receipt);
      
      // LineItems erstellen
      final lineItems = ocrResult.items.map((item) {
        return LineItem()
          ..name = item.name
          ..quantity = item.quantity
          ..unitPrice = item.unitPrice
          ..totalPrice = item.totalPrice
          ..category = 'food';
      }).toList();
      
      // Falls keine Items erkannt, Platzhalter erstellen
      if (lineItems.isEmpty && ocrResult.total > 0) {
        lineItems.add(LineItem()
          ..name = 'Gesamt'
          ..quantity = 1.0
          ..unitPrice = ocrResult.total
          ..totalPrice = ocrResult.total
          ..category = 'food');
      }
      
      if (lineItems.isNotEmpty) {
        final freshReceipt = await _receiptDao.getReceiptById(savedReceipt.id);
        if (freshReceipt != null) {
          await _receiptDao.updateLineItemsForReceipt(freshReceipt, lineItems);
        }
      }
      
      if (!mounted) return;
      
      // Zur Bearbeitungsseite navigieren
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ScanPreviewPage(
            receiptId: savedReceipt.id,
            addItemsIndividually: true,
            draftItems: lineItems,
            draftTotal: ocrResult.total,
          ),
        ),
      );
      
      // Wenn User NICHT bestätigt hat (zurück oder abgebrochen), Receipt wieder löschen
      if (changed != true) {
        await _receiptDao.deleteReceipt(savedReceipt.id);
        // Auch das Bild löschen
        try {
          final imageFile = File(permanentPath);
          if (await imageFile.exists()) {
            await imageFile.delete();
          }
        } catch (_) {}
        
        debugPrint('[Scanner] Receipt ${savedReceipt.id} deleted (user cancelled)');
      } else {
        await _loadData();
      }
      
    } catch (e) {
      if (!mounted) return;
      
      // Loading schließen falls noch offen
      Navigator.of(context).popUntil((route) => route.isFirst == false || route.isFirst);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Scannen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openAddManualExpense() async {
    final amountController = TextEditingController();
    final storeController = TextEditingController();

    final baseCategories = [
      {'key': 'food', 'label': 'Essen & Trinken'},
      {'key': 'leisure', 'label': 'Freizeit & Hobbies'},
      {'key': 'fixed', 'label': 'Monatliche Kosten'},
    ];

    final extraCategories = _dynamicCategories
        .map((c) => {'key': c.name, 'label': c.name})
        .toList();

    final allCategories = [...baseCategories, ...extraCategories];

    String category = allCategories.first['key'] as String;

    bool isRecurring = false;
    String recurrence = 'monthly';
    DateTime selectedDate = DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickDate() async {
              FocusScope.of(dialogContext).unfocus();
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setDialogState(() {
                  selectedDate = picked;
                });
              }
            }

            return AlertDialog(
              scrollable: true,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              title: const Text('Ausgaben manuell hinzufügen'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Betrag (€)',
                      hintText: 'z. B. 23,45',
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Datum',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat.yMMMd('de_DE').format(selectedDate),
                          ),
                          const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: storeController,
                    decoration: const InputDecoration(
                      labelText: 'Ort / Beschreibung',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(
                      labelText: 'Kategorie',
                    ),
                    items: allCategories
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c['key'] as String,
                            child: Text(c['label'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        category = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Wiederkehrende Ausgabe'),
                    value: isRecurring,
                    onChanged: (v) {
                      setDialogState(() {
                        isRecurring = v;
                      });
                    },
                  ),
                  if (isRecurring)
                    DropdownButtonFormField<String>(
                      value: recurrence,
                      decoration: const InputDecoration(
                        labelText: 'Intervall',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text('Monatlich'),
                        ),
                        DropdownMenuItem(
                          value: 'weekly',
                          child: Text('Wöchentlich'),
                        ),
                        DropdownMenuItem(
                          value: 'yearly',
                          child: Text('Jährlich'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          recurrence = v;
                        });
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Abbrechen'),
                ),
                TextButton(
                  onPressed: () async {
                    final txt = amountController.text.replaceAll(',', '.');
                    final value = double.tryParse(txt);
                    if (value == null || value < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Bitte einen gültigen Betrag eingeben.'),
                        ),
                      );
                      return;
                    }

                    final now = DateTime.now();
                    final effectiveDate = selectedDate;

                    String source = 'manual';
                    if (isRecurring) {
                      source = 'recurring_$recurrence';
                    }

                    final receipt = Receipt()
                      ..dateTime = effectiveDate
                      ..total = value
                      ..storeName = storeController.text.isEmpty
                          ? 'Manuell'
                          : storeController.text
                      ..source = source
                      ..category = category
                      ..isLoaded = true
                      ..createdAt = now
                      ..updatedAt = now;

                    final savedReceipt =
                        await _receiptDao.insertReceipt(receipt);

                    final lineItem = LineItem()
                      ..name = storeController.text.isNotEmpty
                          ? storeController.text
                          : 'Manuelle Ausgabe'
                      ..quantity = 1
                      ..unitPrice = value
                      ..totalPrice = value
                      ..category = category;

                    await _receiptDao.updateLineItemsForReceipt(
                      savedReceipt,
                      [lineItem],
                    );

                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      await _loadData();
    }
  }

  /// Kategorie-Details öffnen
  Future<void> _openCategoryDetails(
    String categoryKey,
    String label,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryDetailsPage(
          categoryKey: categoryKey,
          categoryLabel: label,
        ),
      ),
    );
    await _loadData();
  }

  /// Dynamische Kategorien – als Grid: max. 3 Kacheln pro Reihe, einheitliche Größe
  Widget _buildDynamicCategoriesRow(BuildContext context) {
    final showAddTile = _isEditMode;

    if (_dynamicCategories.isEmpty && !showAddTile) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final maxWidth = constraints.maxWidth;
        final itemWidth = (maxWidth - 2 * spacing) / 3;

        final tiles = <Widget>[];

        for (final cat in _dynamicCategories) {
          tiles.add(
            SizedBox(
              width: itemWidth,
              height: 170,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _isEditMode
                          ? () => _changeDynamicCategoryBudget(cat)
                          : () => _openCategoryDetails(cat.name, cat.name),
                      child: CategoryWheel(
                        label: cat.name,
                        categoryKey: cat.name,
                        spent: cat.spent,
                        budget: cat.budget,
                        isEditing: _isEditMode,
                      ),
                    ),
                  ),
                  if (_isEditMode)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        elevation: 3,
                        shape: const CircleBorder(),
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withOpacity(0.95),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _confirmDeleteDynamicCategory(cat),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.close,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        if (showAddTile) {
          tiles.add(
            SizedBox(
              width: itemWidth,
              height: 170,
              child: GestureDetector(
                onTap: _addDynamicCategory,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.secondary,
                      width: 1.5,
                    ),
                  ),
                  elevation: 2,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add),
                        SizedBox(height: 4),
                        Text(
                          'Kategorie\nhinzufügen',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles,
        );
      },
    );
  }

  Future<void> _loadMessageIngestionState() async {
    // Ensure manager init (also safe if already called in app.dart)
    await MessageIngestionManager.instance.init();

    final enabled = MessageIngestionManager.instance.enabled;
    final notifEnabled = await _inboundBridge.isNotificationListenerEnabled();

    if (!mounted) return;
    setState(() {
      _msgIngestionEnabled = enabled;
      _notifAccessEnabled = notifEnabled;
    });
  }

  Future<void> _setMessageIngestionEnabled(bool value) async {
    await MessageIngestionManager.instance.setEnabled(value);
    final notifEnabled = await _inboundBridge.isNotificationListenerEnabled();

    if (!mounted) return;
    setState(() {
      _msgIngestionEnabled = value;
      _notifAccessEnabled = notifEnabled;
    });
  }

  Future<MessageImportSummary> _runMessageTestImport() async {
    final now = DateTime.now();

    final svc = MessagePaymentRecognitionService(_receiptDao);
    final msgs = <InboundMessage>[
      InboundMessage(
        id: 'test-1-${now.millisecondsSinceEpoch}',
        dateTime: now,
        text: 'Kartenzahlung 12,34 EUR bei Google Play',
        sender: 'com.android.vending',
        channel: 'notification',
      ),
      // Optional: Duplikat (Bank) innerhalb von 2 Minuten -> sollte dedupliziert werden (±5 min)
      InboundMessage(
        id: 'test-2-${now.millisecondsSinceEpoch}',
        dateTime: now.add(const Duration(minutes: 2)),
        text: 'Kartenzahlung 12,34 EUR bei Bank',
        sender: 'BANK',
        channel: 'notification',
      ),
    ];

    final summary = await svc.importMessages(msgs, debugLogs: true);
    await _loadData();
    return summary;
  }

  void _openMessageIngestionSheet() {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> refreshNotifAccess() async {
              final enabled = await _inboundBridge.isNotificationListenerEnabled();
              if (!mounted) return;
              setState(() => _notifAccessEnabled = enabled);
              setModalState(() {});
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              builder: (ctx, controller) {
                final bottomPad = MediaQuery.of(ctx).padding.bottom;

                final statusText = _notifAccessEnabled
                    ? 'Benachrichtigungszugriff ist aktiv.'
                    : 'Benachrichtigungszugriff ist aus. Aktivieren, damit Google Play/Bank erkannt werden.';

                return SingleChildScrollView(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Nachrichtenerkennung',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Schließen',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Liest Benachrichtigungen (z.B. Google Play, Bank) und SMS und erkennt Kartenzahlungen. '
                        'Duplikate (gleicher Betrag, ±5 min) werden automatisch zusammengeführt. '
                        'Kassenzettel haben immer Vorrang.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 18),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Aktiviert', style: theme.textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text(
                                  'Ein-/Ausschalten der Nachrichtenerkennung',
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Switch.adaptive(
                              value: _msgIngestionEnabled,
                              onChanged: (v) async {
                                setModalState(() => _msgIngestionEnabled = v);
                                await _setMessageIngestionEnabled(v);
                                setModalState(() {});
                              },
                            ),
                            Text(
                              _msgIngestionEnabled ? 'Aktiv' : 'Aus',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _msgIngestionEnabled ? Colors.greenAccent : Colors.white54,
                              ),
                            ),
                          ],
                        ),
                        ],
                      ),

                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _notifAccessEnabled ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                            size: 18,
                            color: _notifAccessEnabled ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              statusText,
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            label: const Text('Notification Access'),
                            onPressed: () async {
                              await _inboundBridge.openNotificationListenerSettings();
                              // Der User muss zurück zur App kommen; danach Status refreshen
                              Future.delayed(const Duration(milliseconds: 800), refreshNotifAccess);
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Aktualisieren'),
                            onPressed: refreshNotifAccess,
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.science_outlined, size: 18),
                            label: const Text('Test Import'),
                            onPressed: () async {
                              final summary = await _runMessageTestImport();
                              if (!mounted) return;
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Test importiert: scanned=${summary.scanned}, detected=${summary.detected}, '
                                      'inserted=${summary.inserted}, skipped=${summary.skippedBecauseReceiptExists}, '
                                      'deleted=${summary.deletedMessageDuplicates}',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Importieren'),
                            onPressed: () async {
                              await _importPendingInboundMessages();
                              // also refresh permission status if you want
                              await refreshNotifAccess();
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),
                      Text(
                        'End-to-end Test (ADB)',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1) Notification access aktivieren\n'
                        '2) Am PC ausführen:\n',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const SelectableText(
                          'adb shell cmd notification post -t "Kartenzahlung" -S bigtext -b "Kartenzahlung 12,34 EUR bei Google Play" testTag',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '3) App öffnen → es sollte eine neue Ausgabe auftauchen.',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        leading: _isEditMode
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Bearbeiten beenden',
                    icon: const Icon(Icons.check),
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      setState(() {
                        _isEditMode = false;
                      });
                    },
                  ),
                ],
              )
            : IconButton(
                tooltip: 'Budgets bearbeiten',
                icon: const Icon(Icons.edit),
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  setState(() {
                    _isEditMode = true;
                  });
                },
              ),
        // Klick auf "Heute ausgegeben" -> DayDetailsPage für heute
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            final today = DateTime.now();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DayDetailsPage(
                  day: DateTime(today.year, today.month, today.day),
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Heute ausgegeben',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                Text(
                  '${_totalToday.toStringAsFixed(2)} €',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        ),
        centerTitle: false,
        actions: [
          // Zahnrad für OCR-Bannliste (nur im Edit-Modus)
          if (_isEditMode)
            IconButton(
              tooltip: 'OCR-Filter bearbeiten',
              icon: const Icon(Icons.tune),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OcrBanlistEditorPage(),
                  ),
                );
                OcrBanlist.clearCache();
              },
            ),
          IconButton(
            tooltip: 'Verlauf',
            icon: const Icon(Icons.history),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () {
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (_) => const HistoryPage(),
                ),
              )
                  .then((_) => _loadData());
            },
          ),
          IconButton(
            tooltip: 'Statistik',
            icon: const Icon(Icons.bar_chart_rounded),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StatisticsPage(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Kassenzettel',
            icon: const Icon(Icons.receipt_long_outlined),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () {
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (_) => const ReceiptsPage(),
                ),
              )
                  .then((_) => _loadData());
            },
          ),
          IconButton(
            tooltip: 'Nachrichtenerkennung',
            icon: const Icon(Icons.settings),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () async {
              await _loadMessageIngestionState();
              _openMessageIngestionSheet();
            },
          ),
        ],
      ),
      body: _isLoading || _settings == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                  await _importPendingInboundMessages(showSnack: false);
                  await _loadData();
                },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  Center(
                    child: BudgetRing(
                      monthlyBudget: _settings!.monthlyBudget,
                      spent: _totalThisMonth,
                      onTap: _isEditMode ? _changeMonthlyBudget : () {},
                      isEditing: _isEditMode,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Ausgaben',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Kassenzettel scannen',
                        icon: const Icon(Icons.document_scanner_outlined),
                        onPressed: _openReceiptScanner,
                      ),
                      IconButton(
                        tooltip: 'Manuelle Ausgabe hinzufügen',
                        icon: const Icon(Icons.add),
                        onPressed: _openAddManualExpense,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _isEditMode
                              ? () => _changeCategoryBudget(
                                    'food',
                                    'Essen & Trinken',
                                  )
                              : () => _openCategoryDetails(
                                    'food',
                                    'Essen & Trinken',
                                  ),
                          child: CategoryWheel(
                            label: 'Essen & Trinken',
                            categoryKey: 'food',
                            spent: _foodThisMonth,
                            budget: _settings!.foodAndDrinksBudget,
                            isEditing: _isEditMode,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isEditMode
                              ? () => _changeCategoryBudget(
                                    'leisure',
                                    'Freizeit & Hobbies',
                                  )
                              : () => _openCategoryDetails(
                                    'leisure',
                                    'Freizeit & Hobbies',
                                  ),
                          child: CategoryWheel(
                            label: 'Freizeit & Hobbies',
                            categoryKey: 'leisure',
                            spent: _leisureThisMonth,
                            budget: _settings!.leisureBudget,
                            isEditing: _isEditMode,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isEditMode
                              ? () => _changeCategoryBudget(
                                    'fixed',
                                    'Monatliche Kosten',
                                  )
                              : () => _openCategoryDetails(
                                    'fixed',
                                    'Monatliche Kosten',
                                  ),
                          child: CategoryWheel(
                            label: 'Monatliche Kosten',
                            categoryKey: 'fixed',
                            spent: _fixedThisMonth,
                            budget: _settings!.fixedCostsBudget,
                            isEditing: _isEditMode,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildDynamicCategoriesRow(context),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}