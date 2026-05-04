import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/receipt_models.dart';

class ReceiptTile extends StatelessWidget {
  final Receipt receipt;
  final VoidCallback onTap;
  final VoidCallback onManualLoadPressed;

  const ReceiptTile({
    super.key,
    required this.receipt,
    required this.onTap,
    required this.onManualLoadPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dt = receipt.dateTime;
    final dateStr = DateFormat.yMMMd('de_DE').add_Hm().format(dt);

    final isLoaded = receipt.isLoaded;
    final isEmail = receipt.source == 'email';

    const green = Color(0xFF4CAF50);

    final bgColor =
        isLoaded ? const Color(0xFF1B5E20) : theme.colorScheme.surface;
    final borderColor =
        isLoaded ? green : Colors.grey[500]!.withOpacity(0.9);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 1.8),
        ),
        color: bgColor,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 18,
                    color: isLoaded
                        ? Colors.white.withOpacity(0.9)
                        : theme.colorScheme.onSurface.withOpacity(0.25),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      receipt.storeName ?? 'Unbekannter Händler',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color:
                            isLoaded ? Colors.white : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                dateStr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isLoaded
                      ? Colors.white70
                      : theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Quelle: ${receipt.source}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isLoaded ? Colors.white70 : Colors.grey[400],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    tooltip: isEmail && !isLoaded
                        ? 'PDF laden & scannen'
                        : 'Bearbeiten',
                    icon: Icon(
                      isEmail && !isLoaded
                          ? Icons.cloud_download
                          : Icons.check_circle,
                      color: isLoaded
                          ? green
                          : (isEmail
                              ? theme.colorScheme.primary
                              : theme.iconTheme.color),
                    ),
                    onPressed: () {
                      if (isEmail && !isLoaded) {
                        onManualLoadPressed();
                      } else {
                        onTap();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
