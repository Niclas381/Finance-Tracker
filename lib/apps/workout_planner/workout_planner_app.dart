import 'package:flutter/material.dart';
import '../../suite/sub_app.dart';

const workoutPlannerSubApp = SubApp(
  id: 'workout_planner',
  title: 'Workouts',
  icon: Icons.fitness_center,
  accent: Colors.blueAccent,
  builder: _build,
);

Widget _build(BuildContext context) => const WorkoutPlannerHomePage();

class WorkoutPlannerHomePage extends StatelessWidget {
  const WorkoutPlannerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Planer')),
      body: const Center(child: Text('Workout Planer (in Entwicklung)')),
    );
  }
}
