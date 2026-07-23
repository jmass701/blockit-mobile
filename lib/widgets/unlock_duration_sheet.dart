/// UnlockDurationSheet — the bottom-sheet duration picker, the Flutter
/// equivalent of the web dashboard's #unlockModal (5 min / 30 min / 1 hour /
/// until re-locked). Returns the chosen duration as one of "5" / "30" / "60" /
/// "indefinite" (the exact wire values dashboard_server's VALID_DURATIONS
/// accepts), or null if cancelled.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class UnlockDurationSheet extends StatelessWidget {
  final String itemName;
  const UnlockDurationSheet({super.key, required this.itemName});

  static Future<String?> show(BuildContext context, String itemName) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => UnlockDurationSheet(itemName: itemName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.gray200,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text('Request unlock — $itemName',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Choose how long to unlock this for. Your approver still has to '
              'say yes.',
              style: TextStyle(fontSize: 14, color: AppColors.gray500),
            ),
            const SizedBox(height: 14),
            _option(context, '5 minutes', '5'),
            _option(context, '30 minutes', '30'),
            _option(context, '1 hour', '60'),
            _option(context, 'Until I re-lock it', 'indefinite'),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.gray500,
                  side: const BorderSide(color: AppColors.gray200, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => Navigator.of(context).pop(value),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
