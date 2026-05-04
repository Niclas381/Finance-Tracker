import 'package:flutter/material.dart';

/// Contract, den jede Sub-App im Suite-Launcher erfüllt.
///
/// Eine Sub-App liefert nur die Metadaten für ihre Kachel und einen Builder,
/// der ihre Root-Seite (typischerweise ein Scaffold) erzeugt. Die Suite pusht
/// diesen Root via Navigator auf den Stack — keine geschachtelten Navigatoren,
/// kein eigener Router pro Sub-App.
class SubApp {
  /// Stabiler Schlüssel, z.B. 'finance'. Wird auch als RouteSettings.name benutzt.
  final String id;

  /// Anzeigetitel auf der Kachel.
  final String title;

  /// Icon auf der Kachel.
  final IconData icon;

  /// Akzentfarbe (Kachel-Hintergrund / Branding).
  final Color accent;

  /// Baut den Sub-App-Root, sobald der User die Kachel antippt.
  final WidgetBuilder builder;

  const SubApp({
    required this.id,
    required this.title,
    required this.icon,
    required this.accent,
    required this.builder,
  });
}
