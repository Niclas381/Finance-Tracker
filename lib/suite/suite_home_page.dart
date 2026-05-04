import 'package:flutter/material.dart';

import 'sub_app.dart';
import 'suite_registry.dart';
import 'widgets/sub_app_tile.dart';

class SuiteHomePage extends StatelessWidget {
  const SuiteHomePage({super.key});

  void _openSubApp(BuildContext context, SubApp app) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: app.builder,
        settings: RouteSettings(name: app.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suite'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1,
          ),
          itemCount: kSubApps.length,
          itemBuilder: (context, index) {
            final app = kSubApps[index];
            return SubAppTile(
              app: app,
              onTap: () => _openSubApp(context, app),
            );
          },
        ),
      ),
    );
  }
}
