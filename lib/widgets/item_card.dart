/// ItemCard — one blocklist entry rendered as a card, matching the web
/// ".item-card": name, a "APP"/"SITE" kind pill, an "Unlocked · <countdown>"
/// green pill when unlocked, and the lock/unlock-now + delete action buttons.
///
///   * locked   -> teal lock button (tap opens the unlock duration sheet)
///   * unlocked -> green unlock-now button (tap re-locks instantly, no approval)
///   * delete   -> red outline button (tap requests removal — needs approval)
library;

import 'package:flutter/material.dart';

import '../services/local_api_service.dart';
import '../theme/app_theme.dart';
import 'countdown_text.dart';

class ItemCard extends StatelessWidget {
  final ItemStatus status;
  final VoidCallback onRequestUnlock;
  final VoidCallback onLockNow;
  final VoidCallback onRequestRemove;
  final VoidCallback? onCountdownExpired;

  const ItemCard({
    super.key,
    required this.status,
    required this.onRequestUnlock,
    required this.onLockNow,
    required this.onRequestRemove,
    this.onCountdownExpired,
  });

  @override
  Widget build(BuildContext context) {
    final it = status.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.gray200),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(it.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    _pill(it.kind.wire.toUpperCase(), AppColors.gray100,
                        AppColors.gray500),
                  ],
                ),
                if (!status.locked) ...[
                  const SizedBox(height: 6),
                  _unlockedPill(),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (status.locked)
            _iconBtn(
              bg: AppColors.teal,
              icon: Icons.lock_outline,
              iconColor: Colors.white,
              tooltip: 'Blocked — request unlock',
              onTap: onRequestUnlock,
            )
          else
            _iconBtn(
              bg: AppColors.green,
              icon: Icons.lock_open_outlined,
              iconColor: Colors.white,
              tooltip: 'Unlocked — lock now',
              onTap: onLockNow,
            ),
          const SizedBox(width: 8),
          _iconBtn(
            bg: Colors.white,
            border: AppColors.red,
            icon: Icons.delete_outline,
            iconColor: AppColors.red,
            tooltip: 'Remove (needs approval)',
            onTap: onRequestRemove,
          ),
        ],
      ),
    );
  }

  Widget _unlockedPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.greenBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Unlocked · ',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green)),
          if (status.unlockedIndefinitely)
            const Text('no limit',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green))
          else if (status.unlockedUntil != null)
            DefaultTextStyle(
              style: const TextStyle(fontSize: 11),
              child: CountdownText(
                until: status.unlockedUntil!,
                onExpired: onCountdownExpired,
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: fg)),
      );

  Widget _iconBtn({
    required Color bg,
    required IconData icon,
    required Color iconColor,
    required String tooltip,
    required VoidCallback onTap,
    Color? border,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border:
                  border != null ? Border.all(color: border, width: 1.5) : null,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }
}
