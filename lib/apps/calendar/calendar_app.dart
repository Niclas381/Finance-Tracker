import 'package:flutter/material.dart';
import '../../suite/sub_app.dart';
import 'ui/calendar_home_page.dart';

const calendarSubApp = SubApp(
  id: 'calendar',
  title: 'Kalender',
  icon: Icons.calendar_month,
  accent: Colors.purple,
  builder: _build,
);

Widget _build(BuildContext context) => const CalendarHomePage();
