import 'package:flutter/material.dart';
import '../../suite/sub_app.dart';

const calorieTrackerSubApp = SubApp(
  id: 'calorie_tracker',
  title: 'Kalorien',
  icon: Icons.fastfood,
  accent: Colors.orange,
  builder: _build,
);

Widget _build(BuildContext context) => const CalorieTrackerHomePage();

class CalorieTrackerHomePage extends StatelessWidget {
  const CalorieTrackerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kalorientracker')),
      body: const Center(child: Text('Kalorientracker (in Entwicklung)')),
    );
  }
}
