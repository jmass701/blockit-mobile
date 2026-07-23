/// PendingRequest — Dart equivalent of one entry in state.json's
/// "pending_requests" list.
///
/// Mirrors the dicts appended throughout blocker.py / dashboard_server.py. A
/// request is created when something that LOOSENS a restriction is asked for
/// (unlock, remove-from-blocklist, add/remove/invite partner); it starts
/// "pending" and becomes "approved"/"denied" once a matching partner reply is
/// applied by apply_replies(). prune_resolved_requests() later drops resolved
/// ones older than 24h.
library;

/// Request types — the exact string values used as req["type"] in the Windows
/// app, so the same match/authorization logic ports 1:1.
enum RequestType {
  unlock,
  blocklistAdd,
  blocklistRemove,
  domainAdd,
  domainRemove,
  partnerAdd,
  partnerInvite,
  partnerRemove,
}

const Map<RequestType, String> _typeWire = {
  RequestType.unlock: 'unlock',
  RequestType.blocklistAdd: 'blocklist_add',
  RequestType.blocklistRemove: 'blocklist_remove',
  RequestType.domainAdd: 'domain_add',
  RequestType.domainRemove: 'domain_remove',
  RequestType.partnerAdd: 'partner_add',
  RequestType.partnerInvite: 'partner_invite',
  RequestType.partnerRemove: 'partner_remove',
};

RequestType requestTypeFromWire(String s) => _typeWire.entries
    .firstWhere((e) => e.value == s,
        orElse: () => const MapEntry(RequestType.unlock, 'unlock'))
    .key;

/// Human labels matching the web dashboard's TYPE_LABELS map.
const Map<RequestType, String> requestTypeLabels = {
  RequestType.unlock: 'Unlock request',
  RequestType.blocklistAdd: 'Add app',
  RequestType.blocklistRemove: 'Remove app',
  RequestType.domainAdd: 'Add site',
  RequestType.domainRemove: 'Remove site',
  RequestType.partnerAdd: 'Add partner',
  RequestType.partnerInvite: 'Partner invite',
  RequestType.partnerRemove: 'Remove partner',
};

enum RequestStatus { pending, approved, denied }

class PendingRequest {
  final int id;
  final RequestType type;

  /// The subject of the request: a target name/domain, or a partner email.
  final String detail;

  /// For unlock requests only: the item kind ("app"/"site") and match target,
  /// so apply_replies() knows which item_key() to unlock.
  final String? kind;
  final String? target;

  /// For unlock requests: minutes (int as string) or the literal "indefinite".
  final String? durationMinutes;

  final DateTime sentAt;

  /// Message-ID of the outgoing approval email, used to match a genuine
  /// (In-Reply-To) reply back to this request.
  final String? messageId;

  RequestStatus status;
  DateTime? resolvedAt;

  PendingRequest({
    required this.id,
    required this.type,
    required this.detail,
    required this.sentAt,
    this.kind,
    this.target,
    this.durationMinutes,
    this.messageId,
    this.status = RequestStatus.pending,
    this.resolvedAt,
  });

  factory PendingRequest.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? 'pending').toString();
    final duration = json['duration_minutes'];
    return PendingRequest(
      id: (json['id'] as num).toInt(),
      type: requestTypeFromWire((json['type'] ?? 'unlock').toString()),
      detail: (json['detail'] ?? '').toString(),
      kind: json['kind']?.toString(),
      target: json['target']?.toString(),
      durationMinutes: duration?.toString(),
      sentAt: DateTime.tryParse((json['sent_at'] ?? '').toString()) ??
          DateTime.now(),
      messageId: json['message_id']?.toString(),
      status: RequestStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => RequestStatus.pending,
      ),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'type': _typeWire[type],
      'detail': detail,
      'sent_at': sentAt.toIso8601String(),
      'status': status.name,
    };
    if (kind != null) map['kind'] = kind;
    if (target != null) map['target'] = target;
    if (durationMinutes != null) {
      // Preserve int-vs-"indefinite" distinction like the Windows app.
      map['duration_minutes'] =
          durationMinutes == 'indefinite' ? 'indefinite' : int.tryParse(durationMinutes!) ?? durationMinutes;
    }
    if (messageId != null) map['message_id'] = messageId;
    if (resolvedAt != null) map['resolved_at'] = resolvedAt!.toIso8601String();
    return map;
  }
}
