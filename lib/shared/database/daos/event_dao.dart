import 'package:isar/isar.dart';

import '../models/calendar_event.dart';
import '../shared_isar_service.dart';

class EventDao {
  Future<List<CalendarEvent>> getByDate(DateTime date) async {
    final isar = await SharedIsarService.getIsar();
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return isar.calendarEvents
        .filter()
        .startTimeBetween(start, end, includeLower: true, includeUpper: false)
        .findAll();
  }

  Future<List<CalendarEvent>> getByRange(DateTime from, DateTime to) async {
    final isar = await SharedIsarService.getIsar();
    return isar.calendarEvents
        .filter()
        .startTimeBetween(from, to, includeLower: true, includeUpper: true)
        .findAll();
  }

  Future<void> save(CalendarEvent event) async {
    final isar = await SharedIsarService.getIsar();
    await isar.writeTxn(() => isar.calendarEvents.put(event));
  }

  Future<void> delete(int id) async {
    final isar = await SharedIsarService.getIsar();
    await isar.writeTxn(() => isar.calendarEvents.delete(id));
  }
}
