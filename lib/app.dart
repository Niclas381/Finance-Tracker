import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'data/receipt_dao.dart';
import 'services/share_intent_service.dart';
import 'services/message_ingestion_manager.dart';
import 'ui/auth/auth_gate.dart';
import 'ui/receipts/shared_receipt_preview_page.dart';

/// GlobalKey für Navigation von überall in der App
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _setupShareIntentHandler();
    _setupInboundMessageIngestion();
  }

  void _setupShareIntentHandler() {
    ShareIntentService.instance.onFilesShared = (files) {
      debugPrint('[App] Received ${files.length} shared file(s)');
      
      // Warte kurz bis Navigation bereit ist
      Future.delayed(const Duration(milliseconds: 500), () {
        final navigator = navigatorKey.currentState;
        if (navigator != null && files.isNotEmpty) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => SharedReceiptPreviewPage(sharedFiles: files),
            ),
          );
        }
      });
    };
  }

  void _setupInboundMessageIngestion() {
    // Only runs when enabled via settings.
    // Safe to call even if permissions are missing.
    MessageIngestionManager.instance.init();
  }

  @override
  void dispose() {    ShareIntentService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Finanztracker',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}