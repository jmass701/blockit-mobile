/// EmailService — Gmail SMTP send + IMAP poll for the approval workflow.
///
/// Faithful Dart port of blocker_common.py's send_approval_email() and
/// fetch_approval_replies() (plus _strip_quoted_reply / _REF_TAG_RE /
/// _imap_from_any). Uses the `mailer` package for SMTP (SSL, smtp.gmail.com:465)
/// and `enough_mail` for IMAP (imap.gmail.com:993).
///
/// Key behaviours preserved from the Windows app:
///  * Every approval email uses the SAME fixed subject "BlockIT Request" — all
///    detail lives in the body — so replies are matched two ways: (a) an
///    In-Reply-To/References header equal to the stored Message-ID (a genuine
///    Reply), or (b) a lenient "[ref:<id>]" tag pulled from the body (for
///    clients that compose a fresh mail with no threading headers — the norm
///    for Android share-intent / mailto replies).
///  * The [ref:N] regex is deliberately lenient because phone-keyboard
///    autocorrect mangles the literal tag ("APPROVE [ref:12]" -> "APPROVED[ref
///    12]"), so we match "ref" + up to 3 non-digits + digits.
///  * Approved == body (quoted reply stripped) contains "APPROVE" and not
///    "DENY", case-insensitive.
///  * Every reply's From address (lowercased) is returned, because partner_add
///    (only approver_emails[0] may approve) and partner_invite (only the
///    invitee may accept) are authorization-gated on sender identity.
library;

import 'package:enough_mail/enough_mail.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../models/app_config.dart';

/// Fixed subject for every approval email — ported from
/// blocker_common.APPROVAL_SUBJECT.
const String kApprovalSubject = 'BlockIT Request';

/// One fetched approval reply. Mirrors the dicts returned by
/// fetch_approval_replies().
class ApprovalReply {
  /// The In-Reply-To (or last References) header, or null if the reply carried
  /// no threading headers.
  final String? messageId;

  /// The numeric id pulled out of a "[ref:<id>]" body tag, or null.
  final int? refId;

  /// True == body says APPROVE and not DENY.
  final bool approved;

  /// The replying partner's From address, lowercased.
  final String? fromEmail;

  const ApprovalReply({
    required this.messageId,
    required this.refId,
    required this.approved,
    required this.fromEmail,
  });
}

/// Result of sending an approval email — the Message-ID the caller stores on
/// the pending request for later matching.
class SentApproval {
  final String messageId;
  const SentApproval(this.messageId);
}

class EmailService {
  /// Quote-boundary patterns ported from blocker_common._QUOTE_BOUNDARY_PATTERNS.
  /// Everything from the first match onward is treated as quoted original text.
  static final List<RegExp> _quoteBoundaryPatterns = [
    RegExp(r'\nOn .{0,120} wrote:\s*\n', caseSensitive: false), // Gmail/most
    RegExp(r'\n-{2,}\s*Original Message\s*-{2,}', caseSensitive: false),
    RegExp(r'\nFrom:\s'),
    RegExp(r'\n>'), // first quoted ">" line
  ];

  /// Ported verbatim from blocker_common._REF_TAG_RE — lenient on purpose (see
  /// file-level doc comment).
  static final RegExp _refTagRe =
      RegExp(r'ref\D{0,3}(\d+)', caseSensitive: false);

  /// Best-effort trim of everything from the first quoted-original marker
  /// onward. Ported from _strip_quoted_reply(). Matters because the request
  /// email itself contains the words "Approve"/"Deny", and clients quote it
  /// below the reply — without this, quoted text would make any reply look
  /// approved.
  static String stripQuotedReply(String text) {
    var cut = text.length;
    for (final p in _quoteBoundaryPatterns) {
      final m = p.firstMatch(text);
      if (m != null && m.start < cut) cut = m.start;
    }
    return text.substring(0, cut);
  }

  // ---- SMTP send ------------------------------------------------------------

  SmtpServer _smtp(AppConfig cfg) => SmtpServer(
        'smtp.gmail.com',
        port: 465,
        ssl: true,
        username: cfg.gmailAddress,
        password: cfg.gmailAppPassword,
      );

  /// Sends an approval-request email. Ported from
  /// blocker_common.send_approval_email(). When [recipients] is given, sends to
  /// just that list (used for partner_add/remove/invite, which only one
  /// specific person may act on); otherwise sends to every approval partner.
  ///
  /// Note: unlike the Windows app we do NOT render mailto: Approve/Deny buttons
  /// (they're unreliable on Android) — the partner replies from any mail client
  /// with "APPROVE [ref:N]" / "DENY [ref:N]", or a genuine Reply of just
  /// "APPROVE"/"DENY". The [ref:<id>] tag is embedded plainly in the body.
  Future<SentApproval> sendApprovalEmail(
    AppConfig cfg,
    int reqId,
    String description, {
    List<String>? recipients,
  }) async {
    final to = recipients ?? cfg.approverEmails;
    final refTag = '[ref:$reqId]';

    // enough_mail's MailClient generates RFC-compliant Message-IDs; but mailer
    // owns the send here. We generate one ourselves so it can be stored and
    // matched against In-Reply-To later, exactly like make_msgid() did.
    final messageId =
        '<blockit-$reqId-${DateTime.now().microsecondsSinceEpoch}@blockit.local>';

    final body = '$description\n\n'
        'To respond, reply to this email with the word APPROVE or DENY.\n'
        'If your reply does not thread properly, include this tag so BlockIT '
        'can match it: $refTag';

    final message = Message()
      ..from = Address(cfg.gmailAddress)
      ..recipients.addAll(to)
      ..subject = kApprovalSubject
      ..text = body
      // mailer lets us pin a Message-ID via a custom header so the value we
      // store matches what the recipient's client threads against.
      ..headers['Message-ID'] = messageId;

    await send(message, _smtp(cfg));
    return SentApproval(messageId);
  }

  // ---- IMAP poll ------------------------------------------------------------

  /// Fetches unread approval replies from any current partner and marks them
  /// read. Ported from blocker_common.fetch_approval_replies() — including the
  /// two match paths (message_id / ref tag), the quoted-reply stripping, the
  /// APPROVE-and-not-DENY rule, and the lowercased From extraction.
  Future<List<ApprovalReply>> fetchApprovalReplies(AppConfig cfg) async {
    final results = <ApprovalReply>[];
    final approvers = cfg.approverEmails;
    if (approvers.isEmpty) return results;

    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer('imap.gmail.com', 993, isSecure: true);
      await client.login(cfg.gmailAddress, cfg.gmailAppPassword);
      await client.selectInbox();

      // Search UNSEEN AND (FROM a OR FROM b ...) — the OR-nesting mirrors
      // _imap_from_any(). enough_mail's search takes a raw IMAP search string.
      final searchCriteria = 'UNSEEN ${_imapFromAny(approvers)}';
      final searchResult =
          await client.searchMessages(searchCriteria: searchCriteria);

      final ids = searchResult.matchingSequence;
      if (ids == null || ids.isEmpty) return results;

      final fetchResult =
          await client.fetchMessages(ids, '(RFC822 BODY.PEEK[])');

      for (final msg in fetchResult.messages) {
        final body = _plainTextBody(msg);

        String? inReplyTo =
            _firstHeader(msg, 'in-reply-to')?.trim();
        if (inReplyTo == null || inReplyTo.isEmpty) {
          final refs = _firstHeader(msg, 'references')?.trim().split(RegExp(r'\s+'));
          inReplyTo = (refs != null && refs.isNotEmpty) ? refs.last : null;
        }
        if (inReplyTo != null && inReplyTo.isEmpty) inReplyTo = null;

        final fromEmail = msg.from?.isNotEmpty == true
            ? msg.from!.first.email.trim().toLowerCase()
            : null;

        final newText = stripQuotedReply(body);
        final refMatch = _refTagRe.firstMatch(newText);
        final refId =
            refMatch != null ? int.tryParse(refMatch.group(1)!) : null;

        final upper = newText.toUpperCase();
        final approved = upper.contains('APPROVE') && !upper.contains('DENY');

        // Mark as read so it isn't re-processed next cycle.
        await client.store(
          MessageSequence.fromMessage(msg),
          [MessageFlags.seen],
          action: StoreAction.add,
        );

        if (inReplyTo != null || refId != null) {
          results.add(ApprovalReply(
            messageId: inReplyTo,
            refId: refId,
            approved: approved,
            fromEmail: fromEmail?.isEmpty == true ? null : fromEmail,
          ));
        }
      }
      return results;
    } finally {
      try {
        await client.logout();
      } catch (_) {}
    }
  }

  /// Ported from _imap_from_any() — left-to-right nested ORs, valid without
  /// parens because each FROM "..." is a complete search-key.
  String _imapFromAny(List<String> approvers) {
    var expr = 'FROM "${approvers.first}"';
    for (final a in approvers.skip(1)) {
      expr = 'OR $expr FROM "$a"';
    }
    return expr;
  }

  String? _firstHeader(MimeMessage msg, String name) {
    final headers = msg.getHeaderValue(name);
    return headers;
  }

  /// Concatenates all text/plain parts, like the Windows app's msg.walk() loop.
  String _plainTextBody(MimeMessage msg) {
    final decoded = msg.decodeTextPlainPart();
    if (decoded != null && decoded.isNotEmpty) return decoded;
    // Fall back to any decoded content (some phones send text/html only).
    return msg.decodeTextHtmlPart() ?? '';
  }
}
