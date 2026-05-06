import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'models/calendar_event.dart';
import 'models/calendar_todo.dart';

class SharedIsarService {
  static Isar? _instance;

  static Future<Isar> getIsar() async {
    if (_instance != null && _instance!.isOpen) return _instance!;

    final dir = await getApplicationDocumentsDirectory();
    _instance = await Isar.open(
      [CalendarTodoSchema, CalendarEventSchema],
      directory: dir.path,
      name: 'suite_shared',
    );
    return _instance!;
  }
}
