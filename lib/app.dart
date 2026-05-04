import 'package:flutter/material.dart';

import 'shared/theme/theme.dart';
import 'shared/navigation/navigator_key.dart';
import 'shared/auth/auth_gate.dart';
import 'apps/finance_tracker/services/share_intent_service.dart';
import 'apps/finance_tracker/services/message_ingestion_manager.dart';
import 'apps/finance_tracker/ui/receipts/shared_receipt_preview_page.dart';

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