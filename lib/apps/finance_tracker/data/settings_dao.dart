import 'package:isar/isar.dart';
import '../models/receipt_models.dart';
import 'isar_service.dart';

class SettingsDao {
  Future<Isar> get _isar async => IsarService.getIsar();

  Future<UserSettings> getSettings() async {
    final isar = await _isar;
    UserSettings? settings = await isar.userSettings.get(0);

    if (settings == null) {
      settings = UserSettings();
      await isar.writeTxn(() async {
        await isar.userSettings.put(settings!);
      });
    }
    return settings;
  }

  Future<void> updateSettings(UserSettings settings) async {
    final isar = await _isar;

    await isar.writeTxn(() async {
      await isar.userSettings.put(settings);
    });
  }
}
