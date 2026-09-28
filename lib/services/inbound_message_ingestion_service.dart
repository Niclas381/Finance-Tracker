import 'dart:async';

import '../data/receipt_dao.dart';
import '../platform/inbound_message_bridge.dart';
import 'message_payment_recognition_service.dart';

/// Subscribes to inbound messages (SMS + notifications) from the native layer
/// and imports detected payments as receipts.
///
/// This service batches incoming events and also processes a persistent pending
/// queue for messages that arrived while the app was closed.
class InboundMessageIngestionService {
  final InboundMessageBridge _bridge;
  final MessagePaymentRecognitionService _recognition;

  StreamSubscription<InboundMessage>? _sub;
  final Set<String> _seenIds = <String>{};

  final List<InboundMessage> _buffer = <InboundMessage>[];
  Timer? _flushTimer;

  InboundMessageIngestionService({
    required InboundMessageBridge bridge,
    required ReceiptDao receiptDao,
  })  : _bridge = bridge,
        _recognition = MessagePaymentRecognitionService(receiptDao);

  Future<void> start() async {
    // 1) Import pending messages (arrived while app was closed)
    final pending = await _bridge.getPendingMessages();
    await _importBatch(pending);

    // 2) Clear pending after import
    await _bridge.clearPendingMessages();

    // 3) Listen live
    await _sub?.cancel();
    _sub = _bridge.messages().listen((msg) {
      if (_seenIds.contains(msg.id)) return;
      _seenIds.add(msg.id);

      _buffer.add(msg);
      _flushTimer?.cancel();
      _flushTimer = Timer(const Duration(milliseconds: 800), () async {
        final batch = List<InboundMessage>.from(_buffer);
        _buffer.clear();
        await _importBatch(batch);
      });
    });
  }

  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _importBatch(List<InboundMessage> messages) async {
    if (messages.isEmpty) return;

    for (final m in messages) {
      _seenIds.add(m.id);
    }

    await _recognition.importMessages(messages);
  }
}
