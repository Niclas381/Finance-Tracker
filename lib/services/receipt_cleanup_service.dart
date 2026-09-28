import 'package:flutter/foundation.dart';

import '../data/receipt_dao.dart';
import '../models/receipt_models.dart';

/// Einmalige Migration:
/// Findet Receipts mit total>0 aber ohne LineItems
/// und erzeugt ein Fallback-LineItem ("Gesamt").
/// Danach sind diese Ausgaben wieder sichtbar und löschbar.
class ReceiptCleanupService {
  final ReceiptDao _receiptDao;

  ReceiptCleanupService(this._receiptDao);

  /// Führt die Migration aus.
  /// debugLogs=true -> prints in Console
  Future<int> addFallbackItemsToEmptyReceipts({
    bool debugLogs = true,
  }) async {
    final receipts = await _receiptDao.getAllReceipts();
    int fixed = 0;

    for (final r in receipts) {
      // "message"-Receipts (Nachrichtenerkennung) sollen NICHT automatisch
      // mit einem Fallback-LineItem versehen werden, sonst tauchen sie
      // als Fake-Produkt in Produkt-Rankings auf.
      if (r.source == 'message') {
        continue;
      }

      await r.lineItems.load();
      final hasNoItems = r.lineItems.isEmpty;
      final hasTotal = r.total > 0.0001;

      if (hasNoItems && hasTotal) {
        final fallback = LineItem()
          ..name = (r.storeName?.trim().isNotEmpty == true)
              ? r.storeName!.trim()
              : 'Gesamt'
          ..quantity = 1.0
          ..unitPrice = r.total
          ..totalPrice = r.total
          ..category = (r.category?.trim().isNotEmpty == true)
              ? r.category!.trim()
              : 'food';

        if (debugLogs) {
          debugPrint(
            '[CLEANUP] Fix receipt id=${r.id} date=${r.dateTime} total=${r.total}',
          );
        }

        await _receiptDao.updateLineItemsForReceipt(r, [fallback]);

        // sicherstellen, dass er als "geladen" gilt
        await _receiptDao.markReceiptAsLoaded(r.id);

        fixed++;
      }
    }

    if (debugLogs) {
      debugPrint('[CLEANUP] Fixed $fixed receipts.');
    }

    return fixed;
  }
}
