import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class OffersDb {
  OffersDb._();
  static final OffersDb instance = OffersDb._();

  Database? _db;

  Future<Database> get db async {
    final existing = _db;
    if (existing != null) return existing;
    final opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final basePath = await getDatabasesPath();
    final filePath = p.join(basePath, 'prospekt_offers.sqlite');

    return openDatabase(
      filePath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
CREATE TABLE offers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  market TEXT NOT NULL,
  title TEXT NOT NULL,
  price_eur REAL NOT NULL,
  quantity TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  csv_import_id INTEGER
);
''');

        await db.execute('CREATE INDEX idx_offers_title ON offers(title);');
        await db.execute('CREATE INDEX idx_offers_market ON offers(market);');
      },
    );
  }

  Future<void> close() async {
    final existing = _db;
    _db = null;
    if (existing != null) {
      await existing.close();
    }
  }
}