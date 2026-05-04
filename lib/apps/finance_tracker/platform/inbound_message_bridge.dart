import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../services/message_payment_recognition_service.dart';

/// Bridge to the Android native layer:
/// - MethodChannel: fetch / clear pending queued messages
/// - EventChannel: live stream of inbound messages while the app is open
class InboundMessageBridge {
  static const MethodChannel _method = MethodChannel('inbound_messages/method');
  static const EventChannel _events = EventChannel('inbound_messages/events');

  Stream<InboundMessage>? _stream;

  Stream<InboundMessage> messages() {
    _stream ??= _events.receiveBroadcastStream().map((dynamic event) {
      final map = (event is String)
          ? (jsonDecode(event) as Map<String, dynamic>)
          : (event as Map<String, dynamic>);
      return _fromMap(map);
    });
    return _stream!;
  }

  Future<List<InboundMessage>> getPendingMessages() async {
    final res = await _method.invokeMethod<String>('getPending');
    if (res == null || res.isEmpty) return [];

    final list = jsonDecode(res) as List<dynamic>;
    return list
        .map((e) => _fromMap(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> clearPendingMessages() => _method.invokeMethod<void>('clearPending');

  Future<void> openNotificationListenerSettings() =>
      _method.invokeMethod<void>('openNotificationListenerSettings');

  Future<bool> isNotificationListenerEnabled() async {
    final res = await _method.invokeMethod<bool>('isNotificationListenerEnabled');
    return res ?? false;
  }

  InboundMessage _fromMap(Map<String, dynamic> m) {
    final id = (m['id'] as String?) ??
        '${m['timestampMillis']}-${m['sender']}-${m['channel']}-${m['text']}';

    return InboundMessage(
      id: id,
      dateTime: DateTime.fromMillisecondsSinceEpoch(m['timestampMillis'] as int),
      text: (m['text'] as String?) ?? '',
      sender: m['sender'] as String?,
      channel: (m['channel'] as String?) ?? 'notification',
    );
  }
}
