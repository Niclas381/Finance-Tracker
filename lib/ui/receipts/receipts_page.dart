import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../data/receipt_dao.dart';
import '../../models/receipt_models.dart';
import '../../services/receipt_pdf_text_service.dart';
import '../../services/receipt_sync_service.dart';
import 'receipt_edit_page.dart';
import 'scan_preview_page.dart';

class ReceiptsPage extends StatefulWidget {
  const ReceiptsPage({super.key});

  @override
  State<ReceiptsPage> createState() => _ReceiptsPageState();
}

enum ReceiptFilterMode {
  all,
  newOnly,
  banned,
}

class _ReceiptsPageState extends State<ReceiptsPage> {
  static const _prefsKeyExtraKeywords = 'receiptSyncExtraKeywords';

  final _receiptDao = ReceiptDao();

  late final ReceiptSyncService _syncService;
  late final ReceiptPdfTextService _pdfService;

  List<Receipt> _receipts = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  // Wir arbeiten intern IMMER im Produktmodus.
  static const bool _addItemsIndividually = true;

  // Filter: alle / nur neue / gebannte
  ReceiptFilterMode _filterMode = ReceiptFilterMode.newOnly;

  // Option: alle nicht übernommenen E-Mail-Bons vor Sync resetten
  bool _resetNotLoaded = false;

  @override
  void initState() {
    super.initState();
    _syncService = ReceiptSyncService(_receiptDao);
    _pdfService = const ReceiptPdfTextService();
    _init();
  }

  Future<void> _init() async {
    await _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    final all = await _receiptDao.getAllReceipts();

    final list = all.where((r) {
      if (r.source == 'email') return true;
      if (r.source.startsWith('ocr')) return true;
      return false;
    }).toList();

    list.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    if (!mounted) return;
    setState(() {
      _receipts = list;
      _isLoading = false;
    });
  }

  /// Löscht alle Email-Bons, die noch nicht übernommen wurden UND nicht gebannt sind.
  /// Gebannte Bons bleiben erhalten, damit sie beim nächsten Sync nicht wieder erscheinen.
  Future<void> _resetUnloadedEmailReceipts() async {
    final all = await _receiptDao.getAllReceipts();

    for (final r in all) {
      // Nur nicht-geladene UND nicht-gebannte Email-Bons löschen
      if (r.source == 'email' && !r.isLoaded && !r.isBanned) {
        await _receiptDao.deleteReceipt(r.id);
      }
    }
  }

  void _openSyncDialog() async {
    DateTimeRange? pickedRange;

    final prefs = await SharedPreferences.getInstance();
    String customKeywordsText = prefs.getString(_prefsKeyExtraKeywords) ?? '';
    final customKeywordsController =
        TextEditingController(text: customKeywordsText);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final rangeText = pickedRange == null
                ? 'Kein Filter (alle verfügbaren Bons)'
                : '${DateFormat.yMd('de_DE').format(pickedRange!.start)}'
                    ' – ${DateFormat.yMd('de_DE').format(pickedRange!.end)}';

            return AlertDialog(
              title: const Text('Synchronisation'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Zeitraum (optional)'),
                      subtitle: Text(rangeText),
                      trailing: IconButton(
                        icon: const Icon(Icons.date_range),
                        onPressed: () async {
                          final now = DateTime.now();
                          final initial = pickedRange ??
                              DateTimeRange(
                                start: DateTime(now.year, now.month, now.day)
                                    .subtract(const Duration(days: 7)),
                                end: DateTime(now.year, now.month, now.day),
                              );
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2015),
                            lastDate: DateTime(now.year + 1),
                            initialDateRange: initial,
                            helpText: 'Zeitraum für Gmail-Suche',
                          );
                          if (picked != null) {
                            setDialogState(() {
                              pickedRange = picked;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: customKeywordsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Zusätzliche Suchwörter',
                        helperText: 'Kommagetrennt, z. B. "Spotify, Bahn"',
                        helperMaxLines: 2,
                      ),
                      onChanged: (value) {
                        customKeywordsText = value;
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Es werden nur Emails mit PDF-Anhang und passenden '
                      'Suchwörtern im Betreff oder Inhalt gefunden.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Alle nicht hinzugefügten E-Mail-Bons resetten',
                      ),
                      subtitle: const Text(
                        'Vor der Synchronisation alle grauen E-Mail-Bons '
                        'löschen und den gesamten Verlauf neu durchsuchen. '
                        'Bereits übernommene Bons bleiben erhalten.',
                      ),
                      value: _resetNotLoaded,
                      onChanged: (value) {
                        setDialogState(() {
                          _resetNotLoaded = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await prefs.setString(
                      _prefsKeyExtraKeywords,
                      customKeywordsText,
                    );

                    final extras = customKeywordsText
                        .split(RegExp(r'[,\n;]'))
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();

                    Navigator.pop(context);
                    _runSync(
                      fromDate: pickedRange?.start,
                      toDate: pickedRange?.end,
                      extraKeywords: extras,
                    );
                  },
                  child: const Text('Starten'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _runSync({
    required DateTime? fromDate,
    required DateTime? toDate,
    required List<String> extraKeywords,
  }) async {
    if (!mounted) return;

    setState(() => _isSyncing = true);

    try {
      DateTime? effectiveFrom = fromDate;
      DateTime? effectiveTo = toDate;

      if (_resetNotLoaded) {
        await _resetUnloadedEmailReceipts();
        effectiveFrom = null;
        effectiveTo = null;
      }

      final count = await _syncService.syncEmailReceipts(
        fromDate: effectiveFrom,
        toDate: effectiveTo,
        extraKeywords: extraKeywords,
      );

      await _loadReceipts();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Keine neuen Bons gefunden.'
                : '$count neue Bon(s) hinzugefügt.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler bei der Synchronisation: $e'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _downloadAndPreview(Receipt receipt) async {
    final messageId = receipt.emailMessageId;
    if (messageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message-ID nicht gefunden.')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdfPath =
          await _syncService.downloadReceiptPdf(messageId: messageId);

      final parsed = await _pdfService.parsePdfPath(
        pdfPath,
        knownStoreName: receipt.storeName,
      );

      final draftItems = parsed.items.map((p) {
        final li = LineItem()
          ..name = p.name
          ..quantity = p.quantity
          ..unitPrice = p.unitPrice
          ..totalPrice = p.totalPrice
          ..category = receipt.category ?? 'food';
        return li;
      }).toList();

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ScanPreviewPage(
            receiptId: receipt.id,
            addItemsIndividually: _addItemsIndividually,
            draftItems: draftItems,
            draftTotal: parsed.total,
          ),
        ),
      );

      if (changed == true) {
        await _loadReceipts();
      }
    } catch (e) {
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Laden/Scannen des Bons: $e'),
        ),
      );
    }
  }

  /// Öffnet die PDF-Ansicht für **alle** Bons (neu, hinzugefügt, gebannt).
  Future<void> _openPdfView(Receipt receipt) async {
    String? pdfPath = receipt.pdfLocalPath;
    final messageId = receipt.emailMessageId;

    // Falls wir noch keinen lokalen Pfad haben, aber eine Message-ID:
    if ((pdfPath == null || pdfPath.isEmpty) && messageId != null) {
      try {
        pdfPath =
            await _syncService.downloadReceiptPdf(messageId: messageId);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Laden der PDF: $e'),
          ),
        );
        return;
      }
    }

    if (pdfPath == null || pdfPath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keine PDF-Datei für diesen Bon verfügbar.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SimplePdfViewerPage(pdfPath: pdfPath!),
      ),
    );
  }

  Future<void> _openEdit(Receipt receipt) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiptEditPage(receipt: receipt),
      ),
    );

    if (changed == true) {
      await _loadReceipts();
    }
  }

  Future<void> _toggleBan(Receipt receipt) async {
    final updated = receipt..isBanned = !receipt.isBanned;
    await _receiptDao.insertReceipt(updated);
    await _loadReceipts();
  }

  List<Receipt> _applyFilter() {
    switch (_filterMode) {
      case ReceiptFilterMode.all:
        return _receipts;
      case ReceiptFilterMode.newOnly:
        return _receipts.where((r) => !r.isLoaded && !r.isBanned).toList();
      case ReceiptFilterMode.banned:
        return _receipts.where((r) => r.isBanned).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final visibleReceipts = _applyFilter();
    final hasAnyReceipts = _receipts.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kassenzettel'),
        actions: [
          IconButton(
            tooltip: 'Synchronisieren',
            onPressed: _isSyncing ? null : _openSyncDialog,
            icon: _isSyncing
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filter (alle / neu / gebannt)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                      const SizedBox(width: 8),
                      SegmentedButton<ReceiptFilterMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ReceiptFilterMode.all,
                            label: Text('alle'),
                          ),
                          ButtonSegment(
                            value: ReceiptFilterMode.newOnly,
                            label: Text('neu'),
                          ),
                          ButtonSegment(
                            value: ReceiptFilterMode.banned,
                            label: Text('gebannt'),
                          ),
                        ],
                        selected: {_filterMode},
                        onSelectionChanged: (s) {
                          setState(() {
                            _filterMode = s.first;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visibleReceipts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              !hasAnyReceipts
                                  ? 'Noch keine Kassenzettel vorhanden.'
                                  : switch (_filterMode) {
                                      ReceiptFilterMode.all =>
                                        'Keine Kassenzettel vorhanden.',
                                      ReceiptFilterMode.newOnly =>
                                        'Alle Kassenzettel wurden bereits\nzu den Ausgaben hinzugefügt\noder gebannt.',
                                      ReceiptFilterMode.banned =>
                                        'Es wurden noch keine Bons geblockt.',
                                    },
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          // Performance-Optimierungen:
                          cacheExtent: 500, // Mehr Items im Cache
                          itemCount: visibleReceipts.length,
                          // Feste Höhe für bessere Performance
                          itemExtent: 90,
                          itemBuilder: (context, index) {
                            final receipt = visibleReceipts[index];
                            return _ReceiptTile(
                              key: ValueKey(receipt.id),
                              receipt: receipt,
                              onTap: () {
                                final isEmail = receipt.source == 'email';
                                final isLoaded = receipt.isLoaded;
                                final isBanned = receipt.isBanned;
                                
                                if (isEmail && !isLoaded && !isBanned) {
                                  _downloadAndPreview(receipt);
                                } else {
                                  _openEdit(receipt);
                                }
                              },
                              onToggleBan: () => _toggleBan(receipt),
                              onOpenPdf: () => _openPdfView(receipt),
                              onAction: () {
                                final isEmail = receipt.source == 'email';
                                final isLoaded = receipt.isLoaded;
                                final isBanned = receipt.isBanned;
                                
                                if (isEmail && !isLoaded && !isBanned) {
                                  _downloadAndPreview(receipt);
                                } else {
                                  _openEdit(receipt);
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// Separates Widget für einen einzelnen Receipt.
/// Verhindert, dass die gesamte Liste bei Änderungen neu gebaut wird.
class _ReceiptTile extends StatelessWidget {
  final Receipt receipt;
  final VoidCallback onTap;
  final VoidCallback onToggleBan;
  final VoidCallback onOpenPdf;
  final VoidCallback onAction;

  const _ReceiptTile({
    super.key,
    required this.receipt,
    required this.onTap,
    required this.onToggleBan,
    required this.onOpenPdf,
    required this.onAction,
  });

  // Statische Farben - werden nicht bei jedem Build neu erstellt
  static const _green = Color(0xFF4CAF50);
  static const _red = Color(0xFFF44336);
  static const _greenBg = Color(0xFF1B5E20);
  static const _redBg = Color(0xFF3B1515);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Berechne Werte einmal
    final isEmail = receipt.source == 'email';
    final isLoaded = receipt.isLoaded;
    final isBanned = receipt.isBanned;
    
    // Farben basierend auf Status
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final Color subtextColor;

    if (isBanned) {
      bgColor = _redBg;
      borderColor = _red;
      textColor = Colors.white;
      subtextColor = Colors.white70;
    } else if (isLoaded) {
      bgColor = _greenBg;
      borderColor = _green;
      textColor = Colors.white;
      subtextColor = Colors.white70;
    } else {
      bgColor = theme.colorScheme.surface;
      borderColor = Colors.grey.withOpacity(0.5);
      textColor = theme.colorScheme.onSurface;
      subtextColor = theme.colorScheme.onSurface.withOpacity(0.7);
    }

    // Datum-String (gecached im Widget)
    final dateStr = DateFormat.yMMMd('de_DE').add_Hm().format(receipt.dateTime);
    final storeName = receipt.storeName ?? 'Unbekannter Händler';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // PDF Icon
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 18,
                  color: (isLoaded || isBanned)
                      ? Colors.white.withOpacity(0.9)
                      : theme.colorScheme.onSurface.withOpacity(0.25),
                ),
                const SizedBox(width: 10),
                
                // Text Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        storeName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: subtextColor,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'Quelle: ${receipt.source}',
                        style: TextStyle(
                          color: subtextColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Action Buttons - kompakter
                _TileIconButton(
                  icon: Icons.block,
                  color: isBanned ? _red : null,
                  tooltip: isBanned ? 'Freigeben' : 'Blockieren',
                  onPressed: onToggleBan,
                ),
                _TileIconButton(
                  icon: Icons.picture_as_pdf_outlined,
                  tooltip: 'PDF anzeigen',
                  onPressed: onOpenPdf,
                ),
                _TileIconButton(
                  icon: isEmail && !isLoaded && !isBanned
                      ? Icons.cloud_download
                      : Icons.check_circle,
                  color: isBanned
                      ? _red
                      : (isLoaded ? _green : (isEmail ? theme.colorScheme.primary : null)),
                  tooltip: isEmail && !isLoaded && !isBanned
                      ? 'Laden & scannen'
                      : 'Bearbeiten',
                  onPressed: onAction,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kompakter Icon-Button für die Tile
class _TileIconButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String tooltip;
  final VoidCallback onPressed;

  const _TileIconButton({
    required this.icon,
    this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, size: 20, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// Sehr einfache PDF-Anzeige für einen lokalen Pfad.
class _SimplePdfViewerPage extends StatelessWidget {
  final String pdfPath;

  const _SimplePdfViewerPage({required this.pdfPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kassenzettel'),
      ),
      body: SfPdfViewer.file(File(pdfPath)),
    );
  }
}