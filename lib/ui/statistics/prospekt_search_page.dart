import 'package:flutter/material.dart';

import '../../prospekt/prospekt.dart';

enum _SortMode {
  standard,
  priceAsc,
  priceDesc,
  titleLenAsc, // Überraschung
  titleLenDesc,
}

class ProspektSearchPage extends StatefulWidget {
  final ProspektSearchDataSource dataSource;
  final ProspektOffersRepository repo;

  const ProspektSearchPage({
    super.key,
    required this.dataSource,
    required this.repo,
  });

  @override
  State<ProspektSearchPage> createState() => _ProspektSearchPageState();
}

class _ProspektSearchPageState extends State<ProspektSearchPage> {
  final _serverUrlCtrl = TextEditingController();
  final _queryCtrl = TextEditingController();

  String _market = 'alle';
  double? _minPrice;
  double? _maxPrice;

  bool _loading = false;
  String _status = '';
  List<String> _markets = const ['alle'];

  int _total = 0;
  int _limit = 50;
  int _offset = 0;

  List<ProspektOffer> _items = const [];

  _SortMode _sortMode = _SortMode.standard;

  @override
  void initState() {
    super.initState();
    // Default leer lassen, damit du testen kannst.
    // Wenn du willst: hier einen Default reinsetzen.
    _serverUrlCtrl.text = '';
    _init();
  }

  Future<void> _init() async {
    await _reloadMarkets();
    await _runSearch(resetPaging: true);
  }

  @override
  void dispose() {
    _serverUrlCtrl.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  String _normalizeBaseUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;

    // Wenn User nur "foo.trycloudflare.com" eingibt -> https://...
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }

    // trailing slash entfernen
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Future<void> _reloadMarkets() async {
    try {
      final ms = await widget.dataSource.markets();
      if (!mounted) return;
      setState(() {
        _markets = ['alle', ...ms];
        if (!_markets.contains(_market)) _market = 'alle';
      });
    } catch (_) {
      // ignorieren
    }
  }

  List<ProspektOffer> _applyLocalSort(List<ProspektOffer> input) {
    final out = [...input];

    switch (_sortMode) {
      case _SortMode.standard:
        return out; // Reihenfolge wie geliefert (Paging/DB)
      case _SortMode.priceAsc:
        out.sort((a, b) => a.priceEur.compareTo(b.priceEur));
        return out;
      case _SortMode.priceDesc:
        out.sort((a, b) => b.priceEur.compareTo(a.priceEur));
        return out;
      case _SortMode.titleLenAsc:
        out.sort((a, b) => a.title.trim().length.compareTo(b.title.trim().length));
        return out;
      case _SortMode.titleLenDesc:
        out.sort((a, b) => b.title.trim().length.compareTo(a.title.trim().length));
        return out;
    }
  }

  Future<void> _runSearch({required bool resetPaging}) async {
    setState(() {
      _loading = true;
      _status = '';
      if (resetPaging) _offset = 0;
    });

    final q = _queryCtrl.text.trim();

    try {
      final count = await widget.dataSource.count(
        query: q,
        market: _market == 'alle' ? null : _market,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
      );

      final res = await widget.dataSource.search(
        query: q,
        market: _market == 'alle' ? null : _market,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        limit: _limit,
        offset: _offset,
      );

      if (!mounted) return;
      setState(() {
        _total = count;
        _items = _applyLocalSort(res);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Fehler: $e';
        _items = const [];
        _total = 0;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    final raw = _serverUrlCtrl.text;
    final baseUrl = _normalizeBaseUrl(raw);

    if (baseUrl.isEmpty) {
      setState(() => _status = 'Bitte eine Server-URL eingeben (z.B. https://….trycloudflare.com)');
      return;
    }

    setState(() {
      _loading = true;
      _status = 'Sync startet…';
    });

    try {
      // ✅ WICHTIG: Jedes Mal neu aus der Eingabe bauen -> nimmt garantiert die aktuelle URL
      final api = ProspektApiClient(baseUrl: baseUrl);
      final svc = OffersSyncService(api: api, repo: widget.repo);

      await svc.syncReplaceAll(onProgress: (s) {
        if (mounted) setState(() => _status = s);
      });

      await _reloadMarkets();
      await _runSearch(resetPaging: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Sync Fehler: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _nextPage() {
    final next = _offset + _limit;
    if (next >= _total) return;
    setState(() => _offset = next);
    _runSearch(resetPaging: false);
  }

  void _prevPage() {
    final prev = _offset - _limit;
    if (prev < 0) return;
    setState(() => _offset = prev);
    _runSearch(resetPaging: false);
  }

  String _sortLabel(_SortMode m) {
    switch (m) {
      case _SortMode.standard:
        return 'Standard';
      case _SortMode.priceAsc:
        return 'Preis ↑';
      case _SortMode.priceDesc:
        return 'Preis ↓';
      case _SortMode.titleLenAsc:
        return 'Titel-Länge ↑ (überraschend)';
      case _SortMode.titleLenDesc:
        return 'Titel-Länge ↓ (überraschend)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prospekt-Suche'),
        actions: [
          IconButton(
            tooltip: 'Sync',
            onPressed: _loading ? null : _sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
          children: [
            // Server URL (Test)
            TextField(
              controller: _serverUrlCtrl,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Server-URL (Test)',
                hintText: 'https://…trycloudflare.com',
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) {
                // nur UI, Sync passiert bewusst über Sync-Button
                setState(() {
                  _status = 'Server-URL gesetzt: ${_normalizeBaseUrl(_serverUrlCtrl.text)}';
                });
              },
            ),

            const SizedBox(height: 14),

            // Suche
            TextField(
              controller: _queryCtrl,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Suche',
                hintText: 'z.B. Lachs, Cola, Rocher…',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _runSearch(resetPaging: true),
            ),

            const SizedBox(height: 10),

            // Markt
            DropdownButtonFormField<String>(
              value: _market,
              items: _markets.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _market = v);
                _runSearch(resetPaging: true);
              },
              decoration: const InputDecoration(
                labelText: 'Markt',
                prefixIcon: Icon(Icons.store),
              ),
            ),

            const SizedBox(height: 10),

            // min/max + Sortierung (kein Overflow: Wrap statt Row)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'min €'),
                    onChanged: (v) => _minPrice = double.tryParse(v.replaceAll(',', '.')),
                    onFieldSubmitted: (_) => _runSearch(resetPaging: true),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextFormField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'max €'),
                    onChanged: (v) => _maxPrice = double.tryParse(v.replaceAll(',', '.')),
                    onFieldSubmitted: (_) => _runSearch(resetPaging: true),
                  ),
                ),
                SizedBox(
                  width: 340,
                  child: DropdownButtonFormField<_SortMode>(
                    value: _sortMode,
                    isExpanded: true,
                    items: _SortMode.values
                        .map(
                          (m) => DropdownMenuItem<_SortMode>(
                            value: m,
                            child: Text(
                              _sortLabel(m),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _sortMode = v;
                        _items = _applyLocalSort(_items);
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Sortierung',
                      prefixIcon: Icon(Icons.sort),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _loading ? null : () => _runSearch(resetPaging: true),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Suchen'),
                ),
                const SizedBox(width: 12),
                Text(
                  _loading ? 'lädt…' : '$_total Treffer',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),

            if (_status.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _status,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],

            const SizedBox(height: 14),

            if (_items.isEmpty && !_loading)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Text('Keine Ergebnisse.'),
              ),

            for (final o in _items) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${o.market} • ${o.quantity} • ${o.priceEur.toStringAsFixed(2)} €',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: (_loading || _offset <= 0) ? null : _prevPage,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Zurück'),
                ),
                Text(
                  '${_offset + 1}-${(_offset + _items.length).clamp(0, _total)} / $_total',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                TextButton.icon(
                  onPressed: (_loading || (_offset + _limit) >= _total) ? null : _nextPage,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Weiter'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
