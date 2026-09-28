import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/receipt_dao.dart';
import '../models/receipt_models.dart';
import 'auth_service.dart';
import 'receipt_pdf_text_service.dart';

/// Synchronisiert Kassenzettel/Rechnungen aus Gmail.
///
/// Regeln:
/// 1) Email enthält explizite Bon/Rechnung-Keywords (Subject oder Body)
/// 2) PDF-Attachment vorhanden
///
/// Verhalten:
/// - Es werden nur neue Bons hinzugefügt (per emailMessageId dedupliziert)
/// - Bereits vorhandene Bons (egal ob geladen oder nicht) werden NICHT gelöscht
///
/// Token:
/// - vor jedem Call wird ein Token geholt
/// - bei 401 wird interaktiv neu eingeloggt und einmal neu versucht
class ReceiptSyncService {
  final ReceiptDao _receiptDao;
  final ReceiptPdfTextService _pdfService = const ReceiptPdfTextService();

  ReceiptSyncService(this._receiptDao);

  // ------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------

  /// Synchronisiert Email-Bons.
  ///
  /// - [fromDate]/[toDate] werden nur als Filter für Gmail verwendet.
  /// - KEIN PDF-Scan mehr während des Syncs (nur Gmail-Filter).
  /// - Es werden nur Bons mit neuer messageId angelegt (keine Duplikate).
  /// - [extraKeywords]: vom User definierte Zusatzbegriffe für den Gmail-Filter.
  Future<int> syncEmailReceipts({
    DateTime? fromDate,
    DateTime? toDate,
    List<String>? extraKeywords,
  }) async {
    var accessToken = await _getValidAccessToken(interactiveIfNeeded: true);

    final existing = await _receiptDao.getAllReceipts();
    // Alle bekannten messageIds (egal ob isLoaded oder isBanned)
    // So werden gebannte Bons nicht erneut hinzugefügt
    final existingMsgIds = <String>{
      for (final r in existing)
        if (r.emailMessageId != null) r.emailMessageId!,
    };

    // 1) Kandidaten holen (nur Gmail-Filter, kein PDF-Scan)
    final messages = await _fetchReceiptMessages(
      accessToken: accessToken,
      fromDate: fromDate,
      toDate: toDate,
      extraKeywords: extraKeywords ?? const [],
      onTokenExpired: () async {
        accessToken = await _getValidAccessToken(interactiveIfNeeded: true);
        return accessToken;
      },
    );

    // 2) Nur neue messageIds anlegen
    int created = 0;
    for (final msg in messages) {
      if (existingMsgIds.contains(msg.id)) {
        // Bon ist bereits als Kachel vorhanden (egal ob geladen oder nicht)
        continue;
      }

      final receipt = Receipt()
        ..dateTime = msg.dateTime
        ..storeName = msg.storeName
        ..total = 0.0
        ..source = 'email'
        ..emailMessageId = msg.id
        ..isLoaded = false;

      await _receiptDao.insertReceipt(receipt);
      created++;
    }

    return created;
  }

  /// Lädt die PDF-Attachment eines Gmail-Messages herunter und speichert sie lokal.
  /// Gibt den lokalen Dateipfad zurück.
  ///
  /// Robust:
  /// - holt frischen Token
  /// - bei 401 -> interaktiv neu einloggen + retry
  Future<String> downloadReceiptPdf({
    required String messageId,
  }) async {
    // 1) Versuch mit frischem Token
    var accessToken = await _getValidAccessToken(interactiveIfNeeded: false);
    var msgJson = await _getMessageJson(accessToken, messageId);

    // 2) Falls 401 -> interaktiv neu einloggen + retry
    if (msgJson == null) {
      accessToken = await _getValidAccessToken(interactiveIfNeeded: true);
      msgJson = await _getMessageJson(accessToken, messageId);

      if (msgJson == null) {
        throw Exception('Gmail Auth fehlgeschlagen (401). Bitte erneut anmelden.');
      }
    }

    final payload = msgJson['payload'] as Map<String, dynamic>?;
    if (payload == null) {
      throw Exception('Gmail Message hat kein Payload.');
    }

    final pdfPart = _findPdfPart(payload);
    if (pdfPart == null) {
      throw Exception('Keine PDF-Attachment im eBon gefunden.');
    }

    final body = pdfPart['body'] as Map<String, dynamic>?;
    final attachmentId = body?['attachmentId'] as String?;
    final filename = (pdfPart['filename'] as String?)?.trim();

    if (attachmentId == null) {
      throw Exception('PDF-Part hat keine attachmentId.');
    }

    final bytes = await _downloadAttachmentBytes(
      accessToken: accessToken,
      messageId: messageId,
      attachmentId: attachmentId,
    );

    final safeName = (filename != null && filename.toLowerCase().endsWith('.pdf'))
        ? filename
        : 'ebon_$messageId.pdf';

    final dir = Directory.systemTemp.createTempSync('finance_tracker_ebons_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);

    return file.path;
  }

  // ------------------------------------------------------------
  // Token handling / retry
  // ------------------------------------------------------------

  Future<String> _getValidAccessToken({
    required bool interactiveIfNeeded,
  }) async {
    final auth = AuthService.instance;

    var token = auth.accessToken;
    if (token != null) return token;

    token = await auth.refreshAccessTokenSilently();
    if (token != null) return token;

    if (!interactiveIfNeeded) {
      throw Exception('Kein Access Token für Gmail erhalten.');
    }

    await auth.signInWithGoogle();
    token = auth.accessToken;

    if (token == null) {
      throw Exception('Kein Access Token für Gmail erhalten.');
    }

    return token;
  }

  Future<Map<String, dynamic>?> _getMessageJson(
    String accessToken,
    String messageId,
  ) async {
    final msgUrl =
        'https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId'
        '?format=full';

    final resp = await http.get(
      Uri.parse(msgUrl),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (resp.statusCode == 401) {
      return null;
    }

    if (resp.statusCode != 200) {
      throw Exception(
        'Gmail getMessage fehlgeschlagen: '
        '${resp.statusCode} ${resp.body}',
      );
    }

    return json.decode(resp.body) as Map<String, dynamic>;
  }

  Future<List<int>> _downloadAttachmentBytes({
    required String accessToken,
    required String messageId,
    required String attachmentId,
  }) async {
    final attUrl =
        'https://gmail.googleapis.com/gmail/v1/users/me/messages/'
        '$messageId/attachments/$attachmentId';

    final attResp = await http.get(
      Uri.parse(attUrl),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (attResp.statusCode == 401) {
      throw Exception('Gmail Attachment 401 (Token ungültig).');
    }

    if (attResp.statusCode != 200) {
      throw Exception(
        'Gmail getAttachment fehlgeschlagen: '
        '${attResp.statusCode} ${attResp.body}',
      );
    }

    final attJson = json.decode(attResp.body) as Map<String, dynamic>;
    final data = attJson['data'] as String?;
    if (data == null) {
      throw Exception('Attachment hat keine Daten.');
    }

    return base64Url.decode(
      data.replaceAll('-', '+').replaceAll('_', '/'),
    );
  }

  // ------------------------------------------------------------
  // Intern: Gmail Suche (ohne PDF-Validierung)
  // ------------------------------------------------------------

  /// 1) Sucht Kandidaten per Query (PDF + Keywords).
  /// 2) Holt für jede Message Datum / Store.
  Future<List<_GmailReceiptMessage>> _fetchReceiptMessages({
    required String accessToken,
    DateTime? fromDate,
    DateTime? toDate,
    required List<String> extraKeywords,
    required Future<String> Function() onTokenExpired,
  }) async {
    final candidateIds = await _listCandidateMessageIds(
      accessToken: accessToken,
      fromDate: fromDate,
      toDate: toDate,
      extraKeywords: extraKeywords,
    );

    final result = <_GmailReceiptMessage>[];

    for (final id in candidateIds) {
      var detail = await _fetchMessageDetail(
        accessToken: accessToken,
        messageId: id,
      );

      if (detail == null) {
        final newToken = await onTokenExpired();
        detail = await _fetchMessageDetail(
          accessToken: newToken,
          messageId: id,
        );
        if (detail == null) continue;
        accessToken = newToken;
      }

      result.add(detail);
    }

    return result;
  }

  /// Kandidaten:
  /// - PDF Attachment
  /// - explizite Bon/Rechnung-Keywords ODER extraKeywords
  ///
  /// Wichtig: REWE-eBon wird explizit mitgenommen:
  ///  eBon / e-bon / Ihr eBon / ebon / EBon etc.
  Future<List<String>> _listCandidateMessageIds({
    required String accessToken,
    DateTime? fromDate,
    DateTime? toDate,
    required List<String> extraKeywords,
  }) async {
    final keywords = <String>[
      // Rechnung/Bon DE
      'rechnung',
      'rechnungsnummer',
      'bon',
      'kassenbon',
      'kassenzettel',
      'kassenbeleg',
      'einkaufsbeleg',
      'beleg',
      'quittung',
      'zahlungsbeleg',
      // REWE / eBon Varianten
      'ebon',
      '"eBon"',
      '"e-bon"',
      '"e bon"',
      '"ihr ebon"',
      '"Ihr eBon"',
      // EN
      'invoice',
      'receipt',
      '"tax invoice"',
      '"purchase receipt"',
      '"proof of purchase"',
    ];

    // User-spezifische Extra-Keywords bereinigt hinzufügen
    final cleanedExtra = extraKeywords
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final allKeywords = [...keywords, ...cleanedExtra];

    final keywordClause =
        '(subject:(${allKeywords.join(' OR ')}) OR (${allKeywords.join(' OR ')}))';

    final buffer = StringBuffer();
    buffer.write('has:attachment filename:pdf ');
    buffer.write('(');
    buffer.write(keywordClause);
    buffer.write(')');

    // Datumsfilter mit YYYY/MM/DD Format (Gmail-Standard)
    // WICHTIG: 
    // - after:DATUM bedeutet "ab diesem Datum (inklusiv)"
    // - before:DATUM bedeutet "vor diesem Datum (exklusiv)"
    // Daher muss toDate um 1 Tag erhöht werden, um den Endtag einzuschließen
    if (fromDate != null) {
      final dateStr = _formatDateForGmail(fromDate);
      buffer.write(' after:$dateStr');
      debugPrint('[ReceiptSync] Gmail filter: after:$dateStr');
    }
    if (toDate != null) {
      // +1 Tag, da "before:" exklusiv ist (d.h. "before:2024/12/06" findet NICHT den 6.12.)
      final adjustedToDate = toDate.add(const Duration(days: 1));
      final dateStr = _formatDateForGmail(adjustedToDate);
      buffer.write(' before:$dateStr');
      debugPrint('[ReceiptSync] Gmail filter: before:$dateStr (original toDate + 1 day)');
    }

    final queryString = buffer.toString();
    debugPrint('[ReceiptSync] Full Gmail query: $queryString');
    
    final query = Uri.encodeQueryComponent(queryString);

    final listUrl =
        'https://gmail.googleapis.com/gmail/v1/users/me/messages'
        '?q=$query&maxResults=100';

    final listResponse = await http.get(
      Uri.parse(listUrl),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (listResponse.statusCode == 401) {
      throw Exception('Gmail listMessages 401 (Token ungültig).');
    }

    if (listResponse.statusCode != 200) {
      throw Exception(
        'Gmail listMessages fehlgeschlagen: '
        '${listResponse.statusCode} ${listResponse.body}',
      );
    }

    final listJson = json.decode(listResponse.body) as Map<String, dynamic>;
    final messages = (listJson['messages'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        <Map<String, dynamic>>[];

    debugPrint('[ReceiptSync] Found ${messages.length} candidate messages');

    final ids = <String>[];
    for (final msg in messages) {
      final id = msg['id'] as String?;
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// Formatiert ein Datum für Gmail-Suche als YYYY/MM/DD
  String _formatDateForGmail(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year/$month/$day';
  }

  Future<_GmailReceiptMessage?> _fetchMessageDetail({
    required String accessToken,
    required String messageId,
  }) async {
    final url =
        'https://gmail.googleapis.com/gmail/v1/users/me/messages/$messageId'
        '?format=metadata'
        '&metadataHeaders=Subject'
        '&metadataHeaders=From';

    final resp = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (resp.statusCode == 401) return null;
    if (resp.statusCode != 200) return null;

    final jsonMap = json.decode(resp.body) as Map<String, dynamic>;

    final internalDateMs = int.tryParse('${jsonMap['internalDate']}');
    if (internalDateMs == null) return null;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(internalDateMs);

    String? subject;
    String? from;

    final payload = jsonMap['payload'] as Map<String, dynamic>?;
    final headers = (payload?['headers'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        <Map<String, dynamic>>[];

    for (final h in headers) {
      final name = (h['name'] as String?)?.toLowerCase();
      final value = h['value'] as String?;
      if (name == null || value == null) continue;

      switch (name) {
        case 'subject':
          subject = value;
          break;
        case 'from':
          from = value;
          break;
      }
    }

    final storeName = _guessStoreName(subject, from);

    return _GmailReceiptMessage(
      id: messageId,
      storeName: storeName,
      dateTime: dateTime,
    );
  }

  String _guessStoreName(String? subject, String? from) {
    final text = '${subject ?? ''} ${from ?? ''}'.toLowerCase();

    if (text.contains('rewe')) return 'REWE';
    if (text.contains('edeka')) return 'EDEKA';
    if (text.contains('aldi')) return 'ALDI';
    if (text.contains('lidl')) return 'LIDL';
    if (text.contains('kaufland')) return 'Kaufland';
    if (text.contains('netto')) return 'Netto';
    if (text.contains('penny')) return 'PENNY';
    if (text.contains('rossmann')) return 'Rossmann';
    if (text.contains('dm')) return 'dm';
    if (text.contains('mueller') || text.contains('müller')) return 'Müller';

    if (subject != null && subject.trim().isNotEmpty) return subject.trim();
    if (from != null && from.trim().isNotEmpty) return from.trim();
    return 'Unbekannter Händler';
  }

  Future<String> _downloadPdfForValidation({
    required String accessToken,
    required String messageId,
    required Future<String> Function() onTokenExpired,
  }) async {
    // Diese Funktion wird aktuell nicht mehr vom Sync genutzt,
    // bleibt aber vorhanden, falls du später wieder eine Validierung
    // auf PDF-Ebene beim Sync einbauen willst.
    var msgJson = await _getMessageJson(accessToken, messageId);

    if (msgJson == null) {
      final newToken = await onTokenExpired();
      accessToken = newToken;
      msgJson = await _getMessageJson(accessToken, messageId);
      if (msgJson == null) {
        throw Exception('401');
      }
    }

    final payload = msgJson['payload'] as Map<String, dynamic>?;
    if (payload == null) throw Exception('no payload');

    final pdfPart = _findPdfPart(payload);
    if (pdfPart == null) throw Exception('no pdf');

    final body = pdfPart['body'] as Map<String, dynamic>?;
    final attachmentId = body?['attachmentId'] as String?;
    final filename = (pdfPart['filename'] as String?)?.trim();

    if (attachmentId == null) throw Exception('no attachmentId');

    final bytes = await _downloadAttachmentBytes(
      accessToken: accessToken,
      messageId: messageId,
      attachmentId: attachmentId,
    );

    final safeName = (filename != null && filename.toLowerCase().endsWith('.pdf'))
        ? filename
        : 'ebon_$messageId.pdf';

    final dir = Directory.systemTemp.createTempSync('finance_tracker_ebons_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);

    return file.path;
  }

  Map<String, dynamic>? _findPdfPart(Map<String, dynamic> node) {
    final mime = (node['mimeType'] as String?)?.toLowerCase();
    final filename = (node['filename'] as String?)?.toLowerCase();

    if ((mime == 'application/pdf') ||
        (filename != null && filename.endsWith('.pdf'))) {
      return node;
    }

    final parts = (node['parts'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    for (final p in parts) {
      final found = _findPdfPart(p);
      if (found != null) return found;
    }
    return null;
  }
}

class _GmailReceiptMessage {
  final String id;
  final String storeName;
  final DateTime dateTime;

  _GmailReceiptMessage({
    required this.id,
    required this.storeName,
    required this.dateTime,
  });
}