import 'package:isar/isar.dart';

import '../models/calendar_todo.dart';
import '../shared_isar_service.dart';

class TodoDao {
  Future<List<CalendarTodo>> getByDate(DateTime date) async {
    final isar = await SharedIsarService.getIsar();
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return isar.calendarTodos
        .filter()
        .dateBetween(start, end, includeLower: true, includeUpper: false)
        .findAll();
  }

  Future<void> save(CalendarTodo todo) async {
    final isar = await SharedIsarService.getIsar();
    todo.updatedAt = DateTime.now();
    await isar.writeTxn(() => isar.calendarTodos.put(todo));
  }

  Future<void> toggleDone(int id) async {
    final isar = await SharedIsarService.getIsar();
    await isar.writeTxn(() async {
      final todo = await isar.calendarTodos.get(id);
      if (todo == null) return;
      todo.isDone = !todo.isDone;
      todo.updatedAt = DateTime.now();
      await isar.calendarTodos.put(todo);
    });
  }

  Future<void> delete(int id) async {
    final isar = await SharedIsarService.getIsar();
    await isar.writeTxn(() => isar.calendarTodos.delete(id));
  }
}
