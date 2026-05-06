import 'package:flutter/material.dart';
import '../../suite/sub_app.dart';

const calendarSubApp = SubApp(
  id: 'calendar',
  title: 'Kalender',
  icon: Icons.calendar_month,
  accent: Colors.purple,
  builder: _build,
);

Widget _build(BuildContext context) => const CalendarHomePage();

class CalendarHomePage extends StatelessWidget {
  const CalendarHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kalender')),
      body: const Center(child: Text('Kalender Seite (in Entwicklung)')),
    );
  }
}
