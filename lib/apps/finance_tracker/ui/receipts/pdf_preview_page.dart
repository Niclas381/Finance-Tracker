import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

class PdfPreviewPage extends StatefulWidget {
  final String pdfPath;
  final String title;

  const PdfPreviewPage({
    super.key,
    required this.pdfPath,
    required this.title,
  });

  @override
  State<PdfPreviewPage> createState() => _PdfPreviewPageState();
}

class _PdfPreviewPageState extends State<PdfPreviewPage> {
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final file = File(widget.pdfPath);
    final exists = file.existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isReady && _totalPages > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              child: Center(
                child: Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
        ],
      ),
      body: !exists
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'PDF-Datei wurde nicht gefunden.\n'
                  'Pfad: ${widget.pdfPath}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.redAccent),
                ),
              ),
            )
          : Stack(
              children: [
                PDFView(
                  filePath: widget.pdfPath,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                  onRender: (pages) {
                    setState(() {
                      _totalPages = pages ?? 0;
                      _isReady = true;
                    });
                  },
                  onError: (error) {
                    setState(() {
                      _errorMessage = error.toString();
                    });
                  },
                  onPageError: (page, error) {
                    setState(() {
                      _errorMessage =
                          'Fehler auf Seite ${page ?? 0}: ${error.toString()}';
                    });
                  },
                  onPageChanged: (page, total) {
                    setState(() {
                      _currentPage = page ?? 0;
                      _totalPages = total ?? _totalPages;
                    });
                  },
                ),
                if (!_isReady && _errorMessage == null)
                  const Center(child: CircularProgressIndicator()),
                if (_errorMessage != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.redAccent),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
