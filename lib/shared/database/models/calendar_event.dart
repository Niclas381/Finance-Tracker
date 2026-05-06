import 'package:isar/isar.dart';

part 'calendar_event.g.dart';

@Collection()
class CalendarEvent {
  Id id = Isar.autoIncrement;

  late String title;
  String? description;

  @Index()
  late DateTime startTime;

  DateTime? endTime;
  bool isAllDay = false;

  DateTime createdAt = DateTime.now();
}
