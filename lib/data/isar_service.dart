import 'dart:async';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/receipt_models.dart';

class IsarService {
  static Isar? _isarInstance;

  /// Singleton-Zugriff auf Isar-Instanz
  static Future<Isar> getIsar() async {
    if (_isarInstance != null && _isarInstance!.isOpen) {
      return _isarInstance!;
    }

    final dir = await getApplicationDocumentsDirectory();

    _isarInstance = await Isar.open(
      [
        ReceiptSchema,
        LineItemSchema,
        UserSettingsSchema,
      ],
      directory: dir.path,
    );

    return _isarInstance!;
  }
}
