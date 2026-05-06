import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../shared/auth/auth_service.dart';
import 'sub_app.dart';
import 'suite_registry.dart';
import 'widgets/sub_app_tile.dart';

class SuiteHomePage extends StatefulWidget {
  const SuiteHomePage({super.key});

  @override
  State<SuiteHomePage> createState() => _SuiteHomePageState();
}

class _SuiteHomePageState extends State<SuiteHomePage> {
  bool _authBusy = false;

  void _openSubApp(BuildContext context, SubApp app) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: app.builder,
        settings: RouteSettings(name: app.id),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => _authBusy = true);
    try {
      await AuthService.instance.signInWithGoogle();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anmeldung fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _authBusy = true);
    try {
      await AuthService.instance.signOut();
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suite'),
        actions: [
          StreamBuilder<User?>(
            stream: AuthService.instance.authStateChanges,
            builder: (context, snapshot) {
              if (_authBusy) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final isLoggedIn = snapshot.hasData;
              return IconButton(
                tooltip: isLoggedIn ? 'Abmelden' : 'Mit Google anmelden',
                icon: Icon(isLoggedIn ? Icons.logout : Icons.person_outline),
                onPressed: isLoggedIn ? _signOut : _signIn,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            AspectRatio(
              aspectRatio: 2.2,
              child: SubAppTile(
                app: kSubApps[0], // Finance Tracker
                onTap: () => _openSubApp(context, kSubApps[0]),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SubAppTile(
                      app: kSubApps[1], // To-Do
                      onTap: () => _openSubApp(context, kSubApps[1]),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SubAppTile(
                      app: kSubApps[2], // Kalender
                      onTap: () => _openSubApp(context, kSubApps[2]),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SubAppTile(
                      app: kSubApps[3], // Kalorientracker
                      onTap: () => _openSubApp(context, kSubApps[3]),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SubAppTile(
                      app: kSubApps[4], // Workout Planer
                      onTap: () => _openSubApp(context, kSubApps[4]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
