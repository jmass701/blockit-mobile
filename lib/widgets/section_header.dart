/// SectionHeader — the uppercase gray section title used across the app,
/// matching the web ".section-title" (with optional "no approval needed" pill
/// like ".no-approval", and an optional trailing action like the web's
/// "Clear resolved" link).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final bool noApproval;
  final Widget? trailing;

  const SectionHeader(
    this.title, {
    super.key,
    this.noApproval = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Text(title.toUpperCase(),
              style: AppTheme.sectionLabel()),
          if (noApproval) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.tealBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('no approval needed',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.tealDark)),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
