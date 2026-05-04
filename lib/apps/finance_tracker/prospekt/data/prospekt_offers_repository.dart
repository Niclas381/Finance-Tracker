import 'package:sqflite/sqflite.dart';

import '../models/prospekt_offer.dart';
import 'offers_db.dart';

class ProspektOffersRepository {
  final OffersDb _db;

  ProspektOffersRepository({OffersDb? db}) : _db = db ?? OffersDb.instance;

  Future<int> clearAll() async {
    final con = await _db.db;
    return con.delete('offers');
  }

  Future<int> upsertManyReplaceAll(List<ProspektOffer> offers) async {
    final con = await _db.db;

    return con.transaction<int>((txn) async {
      await txn.delete('offers');

      final batch = txn.batch();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (final o in offers) {
        batch.insert(
          'offers',
          {
            'market': o.market,
            'title': o.title,
            'price_eur': o.priceEur,
            'quantity': o.quantity,
            'created_at': nowMs,
            'csv_import_id': o.csvImportId,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      final res = await batch.commit(noResult: false);
      return res.length;
    });
  }

  Future<List<String>> listMarkets() async {
    final con = await _db.db;
    final rows = await con.rawQuery(
      'SELECT DISTINCT market FROM offers WHERE market != "" ORDER BY market ASC',
    );
    return rows.map((r) => (r['market'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
  }

  Future<List<ProspektOffer>> searchOffers({
    required String query,
    String? market,
    double? minPrice,
    double? maxPrice,
    int limit = 100,
    int offset = 0,
  }) async {
    final con = await _db.db;

    final where = <String>[];
    final args = <Object?>[];

    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('LOWER(title) LIKE ?');
      args.add('%${q.toLowerCase()}%');
    }

    final m = market?.trim();
    if (m != null && m.isNotEmpty && m != 'alle') {
      where.add('market = ?');
      args.add(m);
    }

    if (minPrice != null) {
      where.add('price_eur >= ?');
      args.add(minPrice);
    }
    if (maxPrice != null) {
      where.add('price_eur <= ?');
      args.add(maxPrice);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await con.rawQuery(
      '''
SELECT id, market, title, price_eur, quantity, created_at, csv_import_id
FROM offers
$whereSql
ORDER BY price_eur ASC, id DESC
LIMIT ? OFFSET ?
''',
      [...args, limit, offset],
    );

    return rows.map((r) => ProspektOffer.fromDb(r)).toList();
  }

  Future<int> countOffers({
    required String query,
    String? market,
    double? minPrice,
    double? maxPrice,
  }) async {
    final con = await _db.db;

    final where = <String>[];
    final args = <Object?>[];

    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('LOWER(title) LIKE ?');
      args.add('%${q.toLowerCase()}%');
    }

    final m = market?.trim();
    if (m != null && m.isNotEmpty && m != 'alle') {
      where.add('market = ?');
      args.add(m);
    }

    if (minPrice != null) {
      where.add('price_eur >= ?');
      args.add(minPrice);
    }
    if (maxPrice != null) {
      where.add('price_eur <= ?');
      args.add(maxPrice);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await con.rawQuery(
      'SELECT COUNT(*) AS c FROM offers $whereSql',
      args,
    );

    final v = rows.isNotEmpty ? rows.first['c'] : 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}