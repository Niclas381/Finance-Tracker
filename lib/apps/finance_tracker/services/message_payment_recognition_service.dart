import 'package:flutter/foundation.dart';

import '../data/receipt_dao.dart';
import '../models/receipt_models.dart';

class InboundMessage {
  final String id;
  final DateTime dateTime;
  final String text;
  final String? sender; // packageName for notifications, phone/sender for sms
  final String channel; // 'notification' | 'sms'

  const InboundMessage({
    required this.id,
    required this.dateTime,
    required this.text,
    this.sender,
    required this.channel,
  });
}

class DetectedCardPayment {
  final DateTime dateTime;
  final int amountCents;
  final String? merchant;
  final String rawText;
  final String? sender;
  final String channel;

  const DetectedCardPayment({
    required this.dateTime,
    required this.amountCents,
    required this.rawText,
    required this.channel,
    this.merchant,
    this.sender,
  });

  double get amountEur => amountCents / 100.0;
}

class MessageImportSummary {
  final int scanned;
  final int detected;
  final int inserted;
  final int skippedBecauseReceiptExists;
  final int deletedMessageDuplicates;
  final int updatedExistingMessageReceipt;
  final int skippedBecauseDuplicateInBatch;

  const MessageImportSummary({
    required this.scanned,
    required this.detected,
    required this.inserted,
    required this.skippedBecauseReceiptExists,
    required this.deletedMessageDuplicates,
    required this.updatedExistingMessageReceipt,
    required this.skippedBecauseDuplicateInBatch,
  });
}

class MessagePaymentRecognitionService {
  final ReceiptDao _receiptDao;

  const MessagePaymentRecognitionService(this._receiptDao);

  static const List<String> paymentKeywords = [
    'kartenzahlung',
    'karten-zahlung',
    'kartenumsatz',
    'visa',
    'mastercard',
    'debit',
    'zahlung',
    'purchase',
    'pos',
    'transaktion',
    'umsatz',
    'betrag',
    'amount',
    'paid',
  ];

  static const List<String> negativeKeywords = [
    'gutschrift',
    'eingang',
    'refund',
    'rückerstattung',
    'rueckerstattung',
    'chargeback',
    'storno',
  ];

  static final RegExp _amountRegex = RegExp(
    r'(?:(€)\s*)?(\d{1,3}(?:[.\s]\d{3})*[.,]\d{2})\s*(?:€|eur|euro)?',
    caseSensitive: false,
  );

  static final RegExp _merchantBei =
      RegExp(r'\bbei\s+([^\n,;]{2,})', caseSensitive: false);
  static final RegExp _merchantAn =
      RegExp(r'\ban\s+([^\n,;]{2,})', caseSensitive: false);
  static final RegExp _merchantHaendler = RegExp(
    r'\b(?:haendler|händler|merchant)\s*[:\-]?\s*([^\n,;]{2,})',
    caseSensitive: false,
  );

  DetectedCardPayment? detect(InboundMessage msg) {
    final raw = msg.text.trim();
    if (raw.isEmpty) return null;

    final lower = raw.toLowerCase();

    final amountMatch = _amountRegex.firstMatch(lower);
    if (amountMatch == null) return null;

    final hasKeyword = paymentKeywords.any(lower.contains);
    final looksLikePayment =
        hasKeyword || lower.contains(' bei ') || lower.contains('\nbei ');
    if (!looksLikePayment) return null;

    if (negativeKeywords.any(lower.contains)) return null;

    final amountText = amountMatch.group(2);
    if (amountText == null) return null;

    final amountCents = _parseAmountToCents(amountText);
    if (amountCents <= 0) return null;

    final merchant = _extractMerchant(raw) ?? _merchantFromSender(msg.sender);

    return DetectedCardPayment(
      dateTime: msg.dateTime,
      amountCents: amountCents,
      merchant: merchant,
      rawText: raw,
      sender: msg.sender,
      channel: msg.channel,
    );
  }

  Future<MessageImportSummary> importMessages(
    List<InboundMessage> messages, {
    Duration window = const Duration(minutes: 5),
    bool debugLogs = false,
  }) async {
    int scanned = 0;
    int detected = 0;
    int inserted = 0;
    int skippedBecauseReceiptExists = 0;
    int deletedMessageDuplicates = 0;
    int updatedExistingMessageReceipt = 0;
    int skippedBecauseDuplicateInBatch = 0;

    scanned = messages.length;

    // 1) Detect first
    final detectedPayments = <DetectedCardPayment>[];
    for (final msg in messages) {
      final p = detect(msg);
      if (p != null) detectedPayments.add(p);
    }
    detected = detectedPayments.length;

    if (detectedPayments.isEmpty) {
      return MessageImportSummary(
        scanned: scanned,
        detected: detected,
        inserted: inserted,
        skippedBecauseReceiptExists: skippedBecauseReceiptExists,
        deletedMessageDuplicates: deletedMessageDuplicates,
        updatedExistingMessageReceipt: updatedExistingMessageReceipt,
        skippedBecauseDuplicateInBatch: skippedBecauseDuplicateInBatch,
      );
    }

    detectedPayments.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    // 2) Group duplicates WITHIN THE BATCH (SMS + Notification etc.)
    final groups = <_PaymentGroup>[];
    for (final p in detectedPayments) {
      _PaymentGroup? target;
      for (final g in groups) {
        if (g.amountCents != p.amountCents) continue;
        if (_absDiff(g.center, p.dateTime) <= window) {
          target = g;
          break;
        }
      }
      if (target == null) {
        groups.add(_PaymentGroup(amountCents: p.amountCents, center: p.dateTime, payments: [p]));
      } else {
        target.payments.add(p);
        // keep the earliest as stable center
        if (p.dateTime.isBefore(target.center)) target.center = p.dateTime;
      }
    }

    // If there were duplicates in batch, count them
    for (final g in groups) {
      if (g.payments.length > 1) skippedBecauseDuplicateInBatch += (g.payments.length - 1);
    }

    // 3) Choose best representative per group (best merchant)
    final uniquePayments = <DetectedCardPayment>[];
    for (final g in groups) {
      uniquePayments.add(_chooseBestPayment(g.payments));
    }

    // Load receipts once; keep cache updated
    final receiptsCache = await _receiptDao.getAllReceipts();

    // 4) Import unique payments with your DB-window rules
    for (final payment in uniquePayments) {
      final candidates = _findCandidatesInCache(
        receiptsCache,
        amountCents: payment.amountCents,
        center: payment.dateTime,
        window: window,
      );

      final nonMessage = candidates.where((r) => r.source != 'message').toList();
      final messageOnes = candidates.where((r) => r.source == 'message').toList();

      // Real receipt exists -> delete message duplicates, skip insert
      if (nonMessage.isNotEmpty) {
        if (messageOnes.isNotEmpty) {
          for (final r in messageOnes) {
            await _receiptDao.deleteReceipt(r.id);
            receiptsCache.removeWhere((x) => x.id == r.id);
          }
          deletedMessageDuplicates += messageOnes.length;
        }
        skippedBecauseReceiptExists++;
        if (debugLogs) {
          debugPrint('[MSG] Skip ${payment.amountEur.toStringAsFixed(2)}€ @ ${payment.dateTime} (non-message exists)');
        }
        continue;
      }

      // Message receipt already exists in window -> keep one, optionally improve merchant, delete extras
      if (messageOnes.isNotEmpty) {
        final winner = _chooseWinner(messageOnes);
        final incoming = (payment.merchant ?? '').trim();
        final current = (winner.storeName ?? '').trim();
        final better = _preferMerchant(current, incoming);

        if (better != current && better.isNotEmpty) {
          winner.storeName = better;
          await _receiptDao.insertReceipt(winner); // update existing
          updatedExistingMessageReceipt++;
        }

        for (final r in messageOnes) {
          if (r.id == winner.id) continue;
          await _receiptDao.deleteReceipt(r.id);
          receiptsCache.removeWhere((x) => x.id == r.id);
          deletedMessageDuplicates++;
        }

        if (debugLogs) {
          debugPrint('[MSG] Window dupe: keep id=${winner.id}, store=${winner.storeName}');
        }
        continue;
      }

      // Insert new message receipt
      final r = Receipt()
        ..dateTime = payment.dateTime
        ..total = payment.amountEur
        ..storeName = (payment.merchant?.trim().isNotEmpty == true)
            ? payment.merchant!.trim()
            : 'Kartenzahlung'
        ..source = 'message'
        ..isLoaded = true
        ..isBanned = false
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now();

      final saved = await _receiptDao.insertReceipt(r);
      receiptsCache.add(saved);
      inserted++;

      if (debugLogs) {
        debugPrint('[MSG] Insert ${payment.amountEur.toStringAsFixed(2)}€ @ ${payment.dateTime} store=${saved.storeName}');
      }
    }

    return MessageImportSummary(
      scanned: scanned,
      detected: detected,
      inserted: inserted,
      skippedBecauseReceiptExists: skippedBecauseReceiptExists,
      deletedMessageDuplicates: deletedMessageDuplicates,
      updatedExistingMessageReceipt: updatedExistingMessageReceipt,
      skippedBecauseDuplicateInBatch: skippedBecauseDuplicateInBatch,
    );
  }

  static Duration _absDiff(DateTime a, DateTime b) {
    final d = a.difference(b);
    return d.isNegative ? -d : d;
  }

  List<Receipt> _findCandidatesInCache(
    List<Receipt> receipts, {
    required int amountCents,
    required DateTime center,
    required Duration window,
  }) {
    final start = center.subtract(window);
    final end = center.add(window);

    return receipts.where((r) {
      if (r.isBanned == true) return false;
      final dt = r.dateTime;
      if (dt.isBefore(start) || dt.isAfter(end)) return false;
      return _receiptAmountCents(r) == amountCents;
    }).toList();
  }

  int _receiptAmountCents(Receipt r) {
    double value = r.total;
    if (value <= 0 && r.lineItems.isNotEmpty) {
      value = r.lineItems.fold<double>(0.0, (sum, li) => sum + li.totalPrice);
    }
    return (value * 100.0).round();
  }

  Receipt _chooseWinner(List<Receipt> messageReceipts) {
    Receipt winner = messageReceipts.first;

    int score(Receipt r) {
      final name = (r.storeName ?? '').trim().toLowerCase();
      if (name.isEmpty) return 0;
      if (name == 'kartenzahlung') return 1;
      if (name == 'bank') return 2;
      return 3;
    }

    for (final r in messageReceipts) {
      final sR = score(r);
      final sW = score(winner);
      if (sR > sW) {
        winner = r;
      } else if (sR == sW) {
        if (r.dateTime.isBefore(winner.dateTime)) winner = r;
      }
    }

    return winner;
  }

  DetectedCardPayment _chooseBestPayment(List<DetectedCardPayment> payments) {
    DetectedCardPayment best = payments.first;

    int score(DetectedCardPayment p) {
      final m = (p.merchant ?? '').trim().toLowerCase();
      if (m.isEmpty) return 0;
      if (m == 'kartenzahlung' || m == 'bank') return 1;
      // Prefer merchant present in text (usually better than sender-based)
      final rawLower = p.rawText.toLowerCase();
      final hasBei = rawLower.contains(' bei ') || rawLower.contains('\nbei ');
      return hasBei ? 3 : 2;
    }

    for (final p in payments) {
      final sP = score(p);
      final sB = score(best);
      if (sP > sB) {
        best = p;
      } else if (sP == sB) {
        // keep earliest for stability
        if (p.dateTime.isBefore(best.dateTime)) best = p;
      }
    }

    // If another payment has a longer/more specific merchant, prefer it
    for (final p in payments) {
      final b = (best.merchant ?? '').trim();
      final c = (p.merchant ?? '').trim();
      if (c.isNotEmpty && c.length > b.length && _preferMerchant(b, c) == c) {
        best = p;
      }
    }

    return best;
  }

  String _preferMerchant(String current, String incoming) {
    final cur = current.trim();
    final inc = incoming.trim();

    if (inc.isEmpty) return cur;
    if (cur.isEmpty) return inc;

    final curLower = cur.toLowerCase();
    final incLower = inc.toLowerCase();

    const generic = {'kartenzahlung', 'bank'};

    final curIsGeneric = generic.contains(curLower);
    final incIsGeneric = generic.contains(incLower);

    if (curIsGeneric && !incIsGeneric) return inc;
    if (!curIsGeneric && incIsGeneric) return cur;

    if (curLower != incLower) {
      return (inc.length > cur.length) ? inc : cur;
    }

    return cur;
  }

  int _parseAmountToCents(String amountText) {
    var t = amountText.trim().replaceAll(' ', '');

    if (t.contains('.') && t.contains(',')) {
      t = t.replaceAll('.', '');
      t = t.replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '.');
    }

    final v = double.tryParse(t);
    if (v == null) return 0;
    return (v * 100.0).round();
  }

  String? _extractMerchant(String raw) {
    final m1 = _merchantBei.firstMatch(raw);
    final m2 = _merchantAn.firstMatch(raw);
    final m3 = _merchantHaendler.firstMatch(raw);

    String? candidate = m1?.group(1) ?? m2?.group(1) ?? m3?.group(1);
    if (candidate == null) return null;

    candidate = candidate.trim();
    candidate = candidate
        .split(RegExp(r'\b(am|um|on|at)\b', caseSensitive: false))
        .first
        .trim();

    candidate = candidate.replaceAll(RegExp(r'[\s\.]+$'), '').trim();

    if (candidate.length < 2) return null;
    if (candidate.length > 60) candidate = candidate.substring(0, 60).trim();

    return candidate;
  }

  String? _merchantFromSender(String? sender) {
    if (sender == null) return null;
    final s = sender.toLowerCase();

    if (s.contains('com.android.vending') || s.contains('google play')) return 'Google Play';
    if (s.contains('paypal')) return 'PayPal';
    if (s.contains('revolut')) return 'Revolut';
    if (s.contains('sparkasse')) return 'Sparkasse';
    if (s.contains('n26')) return 'N26';
    if (s.contains('dkb')) return 'DKB';

    if (sender.contains('.')) {
      final last = sender.split('.').last;
      if (last.length >= 2) return last;
    }

    return sender;
  }
}

class _PaymentGroup {
  final int amountCents;
  DateTime center;
  final List<DetectedCardPayment> payments;

  _PaymentGroup({
    required this.amountCents,
    required this.center,
    required this.payments,
  });
}
