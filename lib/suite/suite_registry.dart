import '../apps/calendar/calendar_app.dart';
import '../apps/calorie_tracker/calorie_tracker_app.dart';
import '../apps/finance_tracker/finance_app.dart';
import '../apps/todo/todo_app.dart';
import '../apps/workout_planner/workout_planner_app.dart';
import 'sub_app.dart';

/// Reihenfolge der Kacheln auf dem Suite-Launcher.
/// Neue Sub-Apps werden hier hinzugefügt.
const List<SubApp> kSubApps = <SubApp>[
  financeSubApp,
  todoSubApp,
  calendarSubApp,
  calorieTrackerSubApp,
  workoutPlannerSubApp,
];
