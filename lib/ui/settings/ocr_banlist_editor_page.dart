import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Seite zum Bearbeiten der OCR-Bannliste
class OcrBanlistEditorPage extends StatefulWidget {
  const OcrBanlistEditorPage({super.key});

  @override
  State<OcrBanlistEditorPage> createState() => _OcrBanlistEditorPageState();
}

class _OcrBanlistEditorPageState extends State<OcrBanlistEditorPage> {
  List<String> _banlistEntries = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBanlist();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<File> _getBanlistFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ocr_banlist.txt');
  }

  Future<void> _loadBanlist() async {
    setState(() => _isLoading = true);

    try {
      final file = await _getBanlistFile();
      
      if (await file.exists()) {
        final content = await file.readAsString();
        final entries = content
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        
        setState(() {
          _banlistEntries = entries;
          _isLoading = false;
        });
      } else {
        // Datei existiert nicht - mit Default-Werten erstellen
        await _createDefaultBanlist();
        await _loadBanlist();
      }
    } catch (e) {
      debugPrint('[Banlist] Error loading: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createDefaultBanlist() async {
    final defaultEntries = [
      '# Summen & Zahlungen',
      'summe',
      'total',
      'gesamt',
      'zu zahlen',
      'gegeben',
      'zurück',
      'wechselgeld',
      'restgeld',
      'betrag',
      '',
      '# Steuern',
      'mwst',
      'ust',
      'steuer',
      'netto',
      'brutto',
      'steuersatz',
      '',
      '# Zahlungsmethoden',
      'kreditkarte',
      'ec-cash',
      'kartenzahlung',
      'mastercard',
      'visa',
      'girocard',
      'bargeld',
      'kontaktlos',
      'bezahlung',
      '',
      '# Bon-Infos',
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
      '',
      '# Kontakt & Adresse',
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
      '',
      '# TSE & Technisches',
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
      '',
      '# Rabatte & Sparen',
      'gespart',
      'preisvorteil',
      'sie sparen',
      'rabatt',
      'lidl plus',
      'payback',
      'coupon',
      'gutschein',
      '',
      '# Pfand',
      'pfand 0',
      'einwegpfand',
      'mehrwegpfand',
      'pfandrückgabe',
      'leergut',
      '',
      '# Städte (optional)',
      'frankfurt',
      'preungesheim',
    ];

    final file = await _getBanlistFile();
    await file.writeAsString(defaultEntries.join('\n'));
  }

  Future<void> _saveBanlist() async {
    try {
      final file = await _getBanlistFile();
      await file.writeAsString(_banlistEntries.join('\n'));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bannliste gespeichert'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('[Banlist] Error saving: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Speichern: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addEntry() async {
    final controller = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neuer Eintrag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'z.B. lidl plus rabatt',
            helperText: 'Kleinbuchstaben verwenden',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final entry = result.trim().toLowerCase();
      
      if (_banlistEntries.contains(entry)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Eintrag existiert bereits'),
            ),
          );
        }
        return;
      }

      setState(() {
        _banlistEntries.add(entry);
      });
      await _saveBanlist();
    }
  }

  Future<void> _addComment() async {
    final controller = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neuer Kommentar'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'z.B. Meine eigenen Einträge',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        _banlistEntries.add('');
        _banlistEntries.add('# ${result.trim()}');
      });
      await _saveBanlist();
    }
  }

  Future<void> _deleteEntry(int index) async {
    final entry = _banlistEntries[index];
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eintrag löschen'),
        content: Text('Möchtest du "$entry" wirklich löschen?'),
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
      ),
    );

    if (confirm == true) {
      setState(() {
        _banlistEntries.removeAt(index);
      });
      await _saveBanlist();
    }
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zurücksetzen'),
        content: const Text(
          'Möchtest du die Bannliste auf die Standardwerte zurücksetzen? '
          'Alle eigenen Einträge gehen verloren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _createDefaultBanlist();
      await _loadBanlist();
    }
  }

  List<MapEntry<int, String>> get _filteredEntries {
    final entries = _banlistEntries.asMap().entries.toList();
    
    if (_searchQuery.isEmpty) {
      return entries;
    }
    
    return entries.where((e) {
      final lower = e.value.toLowerCase();
      return lower.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Bannliste'),
        actions: [
          IconButton(
            tooltip: 'Kommentar hinzufügen',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: _addComment,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'reset') {
                _resetToDefaults();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restore),
                    SizedBox(width: 8),
                    Text('Auf Standard zurücksetzen'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info-Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Wörter in dieser Liste werden beim Scannen ignoriert.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Suchfeld
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Suchen...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                ),
                
                // Anzahl
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text(
                        '${_filteredEntries.where((e) => !e.value.startsWith('#') && e.value.isNotEmpty).length} Einträge',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Liste
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _filteredEntries[index];
                      final originalIndex = entry.key;
                      final text = entry.value;
                      
                      // Kommentar (beginnt mit #)
                      if (text.startsWith('#')) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            text.substring(1).trim(),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        );
                      }
                      
                      // Leerzeile
                      if (text.isEmpty) {
                        return const SizedBox(height: 8);
                      }
                      
                      // Normaler Eintrag
                      return ListTile(
                        dense: true,
                        title: Text(text),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          onPressed: () => _deleteEntry(originalIndex),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
    );
  }
}