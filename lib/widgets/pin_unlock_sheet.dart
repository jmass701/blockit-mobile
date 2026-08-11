/// PinUnlockSheet — bottom sheet for the in-person PIN unlock flow. Lets the
/// user pick a duration (same choices as UnlockDurationSheet) and enter the
/// PIN, returning both to the caller so LocalApiService.unlockWithPin() can
/// verify the PIN and apply the unlock immediately — no email round-trip,
/// but the caller always fires a tamper alert as the safety net for that.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PinUnlockResult {
  final String duration;
  final String pin;
  const PinUnlockResult({required this.duration, required this.pin});
}

class PinUnlockSheet extends StatefulWidget {
  final String itemName;
  const PinUnlockSheet({super.key, required this.itemName});

  static Future<PinUnlockResult?> show(BuildContext context, String itemName) {
    return showModalBottomSheet<PinUnlockResult>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => PinUnlockSheet(itemName: itemName),
    );
  }

  @override
  State<PinUnlockSheet> createState() => _PinUnlockSheetState();
}

class _PinUnlockSheetState extends State<PinUnlockSheet> {
  final _pinController = TextEditingController();
  String _duration = '30';

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;
    Navigator.of(context)
        .pop(PinUnlockResult(duration: _duration, pin: pin));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
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
              Text('Unlock with PIN — ${widget.itemName}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'For when your approval partner is right here. This skips '
                'the email request and unlocks immediately — but always '
                'sends them a tamper alert the moment the PIN is used.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.gray500, height: 1.4),
              ),
              const SizedBox(height: 14),
              _durationOption('5 minutes', '5'),
              _durationOption('30 minutes', '30'),
              _durationOption('1 hour', '60'),
              _durationOption('Until I re-lock it', 'indefinite'),
              const SizedBox(height: 10),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(hintText: 'Enter PIN'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.gray500,
                        side: const BorderSide(
                            color: AppColors.gray200, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: const Text('Unlock'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _durationOption(String label, String value) {
    final selected = _duration == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color:
            selected ? AppColors.teal.withOpacity(0.12) : AppColors.gray100,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => setState(() => _duration = value),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? AppColors.teal : AppColors.gray500,
                ),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
