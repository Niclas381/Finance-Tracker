import 'package:flutter/material.dart';
import '../../suite/sub_app.dart';

const todoSubApp = SubApp(
  id: 'todo',
  title: 'To-Do',
  icon: Icons.checklist,
  accent: Colors.blue,
  builder: _build,
);

Widget _build(BuildContext context) => const TodoHomePage();

class TodoHomePage extends StatelessWidget {
  const TodoHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('To-Do')),
      body: const Center(child: Text('To-Do Seite (in Entwicklung)')),
    );
  }
}
