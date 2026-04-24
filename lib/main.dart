import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'services/share_intent_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialisieren
  await Firebase.initializeApp();

  // Locale-Daten für Deutsch initialisieren
  await initializeDateFormatting('de_DE', null);
  Intl.defaultLocale = 'de_DE';

  // Share Intent Service initialisieren
  ShareIntentService.instance.initialize();

  runApp(const MyApp());
}