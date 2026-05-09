import 'package:isar/isar.dart';
import '../models/receipt_models.dart';
import 'isar_service.dart';

class ReceiptDao {
  Future<Isar> get _isar async => IsarService.getIsar();

  // -------------------------
  // RECEIPTS
  // -------------------------

  /// Inserts a receipt and enforces a de-duplication rule:
  /// Only one receipt may exist for the same amount (cent-exact) within ±5 minutes.
  ///
  /// Priority rule:
  /// - If a non-message receipt (email/scan/shared/manual/...) is inserted and a matching
  ///   message receipt exists, the message receipt is deleted and the new receipt is kept.
  /// - If a message receipt is inserted and a matching non-message receipt exists,
  ///   the message receipt is NOT inserted.
  /// - For same-type duplicates, the "better" one is kept based on a score (attachments, storeName, etc.).
  Future<Receipt> insertReceipt(Receipt receipt) async {
    final isar = await _isar;
    receipt.updatedAt = DateTime.now();

    // De-dupe window: ±5 minutes
    final windowStart = receipt.dateTime.subtract(const Duration(minutes: 5));
    final windowEnd = receipt.dateTime.add(const Duration(minutes: 5));
    final newCents = _toCents(receipt.total);

    // Find candidates in time window and compare by cent-exact total
    final candidates = await isar.receipts.filter().dateTimeBetween(windowStart, windowEnd).findAll();

    final matching = <Receipt>[];
    for (final c in candidates) {
      if (c.id == receipt.id) continue;
      final cValue = await _effectiveTotalCents(isar, c);
      if (cValue == newCents) {
        matching.add(c);
      }
    }

    if (matching.isNotEmpty) {
      // Decide winner between "receipt" and existing matches
      Receipt winner = receipt;
      final losers = <Receipt>[];

      for (final existing in matching) {
        final w = _pickWinner(winner, existing);
        if (identical(w, winner)) {
          losers.add(existing);
        } else {
          losers.add(winner);
          winner = existing;
        }
      }

      // If an existing receipt wins, we might still want to delete other duplicates.
      if (winner.id != receipt.id) {
        // Merge useful fields from the new receipt into the winner (only if missing / better)
        final merged = _mergePreferred(winner, receipt);
        await isar.writeTxn(() async {
          // Delete all losers except the winner itself
          for (final l in losers) {
            if (l.id == winner.id) continue;
            await _deleteReceiptInternal(isar, l.id);
          }
          // Persist merged winner if changed
          merged.updatedAt = DateTime.now();
          await isar.receipts.put(merged);
        });

        final saved = await isar.receipts.get(winner.id);
        return saved ?? winner;
      } else {
        // The new receipt wins -> delete loser duplicates then insert new.
        final id = await isar.writeTxn<int>(() async {
          for (final l in losers) {
            if (l.id == receipt.id) continue;
            await _deleteReceiptInternal(isar, l.id);
          }
          return await isar.receipts.put(receipt);
        });

        final saved = await isar.receipts.get(id);
        return saved ?? receipt;
      }
    }

    // No duplicates -> normal insert
    final id = await isar.writeTxn<int>(() async {
      return await isar.receipts.put(receipt);
    });

    final saved = await isar.receipts.get(id);
    return saved ?? receipt;
  }

  Future<List<Receipt>> getAllReceipts() async {
    final isar = await _isar;

    final receipts = await isar.receipts.where().sortByDateTimeDesc().findAll();

    for (final r in receipts) {
      await r.lineItems.load();
    }
    return receipts;
  }

  Future<Receipt?> getReceiptById(int id) async {
    final isar = await _isar;
    final receipt = await isar.receipts.get(id);
    if (receipt != null) {
      await receipt.lineItems.load();
    }
    return receipt;
  }

  Future<void> deleteReceipt(int id) async {
    final isar = await _isar;

    await isar.writeTxn(() async {
      await _deleteReceiptInternal(isar, id);
    });
  }

  Future<void> markReceiptAsLoaded(int id) async {
    final isar = await _isar;

    await isar.writeTxn(() async {
      final receipt = await isar.receipts.get(id);
      if (receipt != null) {
        receipt.isLoaded = true;
        receipt.updatedAt = DateTime.now();
        await isar.receipts.put(receipt);
      }
    });
  }

  /// Bon bannen / Ban aufheben
  Future<void> setReceiptBanned(int id, bool isBanned) async {
    final isar = await _isar;

    await isar.writeTxn(() async {
      final receipt = await isar.receipts.get(id);
      if (receipt != null) {
        receipt.isBanned = isBanned;
        receipt.updatedAt = DateTime.now();
        await isar.receipts.put(receipt);
      }
    });
  }

  // -------------------------
  // LINE ITEMS
  // -------------------------

  Future<void> addLineItemToReceipt(Receipt receipt, LineItem item) async {
    final isar = await _isar;

    await isar.writeTxn(() async {
      item.receipt.value = receipt;
      await isar.lineItems.put(item);
      receipt.lineItems.add(item);
      await receipt.lineItems.save();
    });
  }

  Future<void> updateLineItemsForReceipt(
    Receipt receipt,
    List<LineItem> items,
  ) async {
    final isar = await _isar;

    await isar.writeTxn(() async {
      // Alte LineItems löschen
      await receipt.lineItems.load();
      for (final old in receipt.lineItems) {
        await isar.lineItems.delete(old.id);
      }
      receipt.lineItems.clear();

      // Neue setzen
      for (final item in items) {
        item.receipt.value = receipt;
        await isar.lineItems.put(item);
        receipt.lineItems.add(item);
      }
      await receipt.lineItems.save();
    });
  }

  Future<List<LineItem>> getLineItemsForReceipt(int receiptId) async {
    final isar = await _isar;

    final receipt = await isar.receipts.get(receiptId);
    if (receipt == null) return [];
    await receipt.lineItems.load();
    return receipt.lineItems.toList();
  }

  Future<void> deleteLineItem(int lineItemId) async {
    final isar = await _isar;

    await isar.writeTxn(() async {
      await isar.lineItems.delete(lineItemId);
    });
  }

  // -------------------------
  // STATS / SUMMEN
  // -------------------------

  /// Monats-Gesamtausgaben:
  /// - gebannte Bons werden ignoriert
  /// - wenn `total` 0 ist, wird auf die Summe der LineItems zurückgegriffen
  Future<double> getTotalSpentInMonth(DateTime month) async {
    final isar = await _isar;

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    final receipts = await isar.receipts.filter().isBannedEqualTo(false).dateTimeBetween(start, end).findAll();

    double sum = 0.0;

    for (final r in receipts) {
      double value = r.total;

      if (value <= 0) {
        await r.lineItems.load();
        value = r.lineItems.fold<double>(
          0.0,
          (s, li) => s + li.totalPrice,
        );
      }

      sum += value;
    }

    return sum;
  }

  /// Monats-Gesamtausgaben pro Kategorie:
  /// - gebannte Bons werden ignoriert
  /// - es werden die LineItems nach Kategorie summiert
  Future<double> getTotalByCategoryInMonth(
    String category,
    DateTime month,
  ) async {
    final isar = await _isar;

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    final receipts = await isar.receipts.filter().isBannedEqualTo(false).dateTimeBetween(start, end).findAll();

    double sum = 0.0;

    for (final r in receipts) {
      await r.lineItems.load();
      for (final item in r.lineItems) {
        if (item.category == category) {
          sum += item.totalPrice;
        }
      }
    }

    return sum;
  }

  /// Tagesausgaben eines Monats als Map<Tag, Betrag>.
  /// Gebannte Bons werden ignoriert. Tage ohne Ausgaben fehlen in der Map.
  Future<Map<int, double>> getDailyTotalsInMonth(DateTime month) async {
    final isar = await _isar;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    final receipts = await isar.receipts
        .filter()
        .isBannedEqualTo(false)
        .dateTimeBetween(start, end)
        .findAll();

    final Map<int, double> totals = {};
    for (final r in receipts) {
      double value = r.total;
      if (value <= 0) {
        await r.lineItems.load();
        value = r.lineItems.fold<double>(0.0, (s, li) => s + li.totalPrice);
      }
      if (value > 0) {
        final day = r.dateTime.day;
        totals[day] = (totals[day] ?? 0) + value;
      }
    }
    return totals;
  }

  // -------------------------
  // INTERNAL HELPERS
  // -------------------------

  int _toCents(double value) => (value * 100).round();

  Future<int> _effectiveTotalCents(Isar isar, Receipt r) async {
    if (r.total > 0) return _toCents(r.total);

    // fallback: line items sum
    final receipt = await isar.receipts.get(r.id);
    if (receipt == null) return 0;
    await receipt.lineItems.load();
    final sum = receipt.lineItems.fold<double>(0.0, (s, li) => s + li.totalPrice);
    return _toCents(sum);
  }

  bool _isMessage(Receipt r) => r.source == 'message';

  Receipt _pickWinner(Receipt a, Receipt b) {
    // Priority: non-message beats message
    final aMsg = _isMessage(a);
    final bMsg = _isMessage(b);

    if (aMsg && !bMsg) return b;
    if (!aMsg && bMsg) return a;

    final sa = _score(a);
    final sb = _score(b);

    if (sa > sb) return a;
    if (sb > sa) return b;

    // Stable tie-breaker: keep the older one (smaller createdAt), otherwise keep a.
    if (a.createdAt.isBefore(b.createdAt)) return a;
    return b;
  }

  int _score(Receipt r) {
    int score = 0;

    // Source preference
    if (!_isMessage(r)) score += 100;
    if (r.source == 'email') score += 20;
    if (r.source == 'scan' || r.source == 'shared') score += 15;

    // Attachments
    if ((r.pdfLocalPath ?? '').trim().isNotEmpty) score += 25;
    if ((r.emailMessageId ?? '').trim().isNotEmpty) score += 20;

    // Edited state
    if (r.isLoaded) score += 10;

    // Store quality
    score += _storeScore(r.storeName);

    return score;
  }

  int _storeScore(String? name) {
    if (name == null) return 0;
    final n = name.trim();
    if (n.isEmpty) return 0;

    final lower = n.toLowerCase();

    // Penalize generic store names commonly produced by notifications
    const generic = [
      'bank',
      'kartenzahlung',
      'kreditkarte',
      'debit',
      'visa',
      'mastercard',
      'zahlung',
      'payment',
    ];
    for (final g in generic) {
      if (lower == g || lower.contains(g)) return 2;
    }

    // Prefer longer/more specific names
    return 5 + (n.length.clamp(0, 25));
  }

  Receipt _mergePreferred(Receipt target, Receipt incoming) {
    final t = target;

    // storeName: keep the more specific one
    final tScore = _storeScore(t.storeName);
    final iScore = _storeScore(incoming.storeName);
    if (iScore > tScore) {
      t.storeName = incoming.storeName;
    }

    // Attachments: fill missing
    if ((t.pdfLocalPath ?? '').isEmpty && (incoming.pdfLocalPath ?? '').isNotEmpty) {
      t.pdfLocalPath = incoming.pdfLocalPath;
    }
    if ((t.emailMessageId ?? '').isEmpty && (incoming.emailMessageId ?? '').isNotEmpty) {
      t.emailMessageId = incoming.emailMessageId;
    }

    // Category: fill missing
    if ((t.category ?? '').trim().isEmpty && (incoming.category ?? '').trim().isNotEmpty) {
      t.category = incoming.category;
    }

    // If total is 0 but incoming has total, copy it
    if (t.total <= 0 && incoming.total > 0) {
      t.total = incoming.total;
    }

    return t;
  }

  Future<void> _deleteReceiptInternal(Isar isar, int id) async {
    final receipt = await isar.receipts.get(id);
    if (receipt != null) {
      await receipt.lineItems.load();
      for (final item in receipt.lineItems) {
        await isar.lineItems.delete(item.id);
      }
    }
    await isar.receipts.delete(id);
  }
}
