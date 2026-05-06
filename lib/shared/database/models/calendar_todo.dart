import 'package:isar/isar.dart';

part 'calendar_todo.g.dart';

@Collection()
class CalendarTodo {
  Id id = Isar.autoIncrement;

  late String title;
  String? description;

  /// Datum der Aufgabe (nur Tag, ohne Uhrzeit)
  @Index()
  late DateTime date;

  bool isDone = false;

  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
}
