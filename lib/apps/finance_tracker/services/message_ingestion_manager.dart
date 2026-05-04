import '../data/receipt_dao.dart';
import '../platform/inbound_message_bridge.dart';
import 'feature_flags_store.dart';
import 'inbound_message_ingestion_service.dart';

/// Central controller to enable/disable inbound message ingestion (SMS + notifications).
///
/// - Persists the toggle without touching the Isar schema.
/// - Starts/stops the ingestion service accordingly.
class MessageIngestionManager {
  static final MessageIngestionManager instance = MessageIngestionManager._();

  MessageIngestionManager._();

  InboundMessageIngestionService? _service;
  bool _enabled = false;
  bool _initialized = false;

  bool get enabled => _enabled;
  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _enabled = await FeatureFlagsStore.getMessageIngestionEnabled();
    _initialized = true;

    if (_enabled) {
      await _start();
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await FeatureFlagsStore.setMessageIngestionEnabled(value);

    if (value) {
      await _start();
    } else {
      await _stop();
    }
  }

  Future<void> _start() async {
    _service ??= InboundMessageIngestionService(
      bridge: InboundMessageBridge(),
      receiptDao: ReceiptDao(),
    );

    await _service!.start();
  }

  Future<void> _stop() async {
    await _service?.stop();
  }
}
