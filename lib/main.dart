import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'apps/finance_tracker/services/share_intent_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Print full stack traces for every framework exception (Flutter normally
  // dedupes them to "Another exception was thrown" with no context).
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
  };

  // Höchste vom Display unterstützte Bildwiederholrate anfordern (Android only;
  // iOS/ProMotion läuft seit Flutter 3.13 automatisch). Schlägt auf nicht
  // unterstützten Plattformen still fehl.
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {}
  }

  // Firebase initialisieren
  await Firebase.initializeApp();

  // Locale-Daten für Deutsch initialisieren
  await initializeDateFormatting('de_DE', null);
  Intl.defaultLocale = 'de_DE';

  // Share Intent Service initialisieren
  ShareIntentService.instance.initialize();

  runApp(const MyApp());
}