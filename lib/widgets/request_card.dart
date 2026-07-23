/// RequestCard — one pending/resolved approval request, matching the web
/// ".pending-row": a "<type label> — <detail>" line, a sent/resolved timestamp
/// with the request id, a colored status badge (amber Waiting / green Approved /
/// red Denied), and a Cancel (pending) / Dismiss (resolved) button.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pending_request.dart';
import '../theme/app_theme.dart';

class RequestCard extends StatelessWidget {
  final PendingRequest request;
  final VoidCallback onDismiss;

  const RequestCard({
    super.key,
    required this.request,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final r = request;
    final pending = r.status == RequestStatus.pending;
    final label = requestTypeLabels[r.type] ?? r.type.name;
    final meta = pending
        ? 'Sent ${_fmtTime(r.sentAt)} · #${r.id}'
        : 'Resolved ${_fmtTime(r.resolvedAt ?? r.sentAt)} · #${r.id}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                Text('$label — ${r.detail}',
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(meta,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.gray500)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _badge(),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.gray500,
              side: const BorderSide(color: AppColors.gray200, width: 1.5),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onDismiss,
            child: Text(pending ? 'Cancel' : 'Dismiss',
                style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _badge() {
    late final String text;
    late final Color bg;
    late final Color fg;
    switch (request.status) {
      case RequestStatus.approved:
        text = 'Approved';
        bg = AppColors.greenBg;
        fg = AppColors.green;
        break;
      case RequestStatus.denied:
        text = 'Denied';
        bg = AppColors.redBg;
        fg = AppColors.red;
        break;
      case RequestStatus.pending:
        text = 'Waiting';
        bg = AppColors.amberBg;
        fg = AppColors.amber;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  String _fmtTime(DateTime dt) => DateFormat('MMM d, h:mm a').format(dt);
}
