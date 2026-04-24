import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Very small persistent key/value store without additional dependencies.
///
/// Stored as JSON in the app's Application Support Directory.
class FeatureFlagsStore {
  static const String _fileName = 'feature_flags.json';
  static const String _keyMessageIngestionEnabled = 'message_ingestion_enabled';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, dynamic>> _readAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return <String, dynamic>{};

      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return <String, dynamic>{};

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> _writeAll(Map<String, dynamic> data) async {
    final f = await _file();
    try {
      if (!await f.parent.exists()) {
        await f.parent.create(recursive: true);
      }
      await f.writeAsString(jsonEncode(data));
    } catch (_) {
      // ignore
    }
  }

  static Future<bool> getMessageIngestionEnabled() async {
    final data = await _readAll();
    final v = data[_keyMessageIngestionEnabled];
    if (v is bool) return v;
    return false;
  }

  static Future<void> setMessageIngestionEnabled(bool enabled) async {
    final data = await _readAll();
    data[_keyMessageIngestionEnabled] = enabled;
    await _writeAll(data);
  }
}
