/// LocalApiService — the app's local "service layer", structured to mirror the
/// Windows app's dashboard_server.py REST surface (there's no actual HTTP
/// server; these are just the equivalent methods with matching semantics).
///
/// Route -> method mapping:
///   GET  /api/status          -> status()
///   POST /api/request-unlock  -> requestUnlock()
///   POST /api/lock-now        -> lockNow()
///   POST /api/cancel-request  -> cancelRequest()
///   POST /api/clear-resolved  -> clearResolved()
///   POST /api/request-change  -> requestChange()
///   POST /api/partners/add    -> partnersAdd()   (two-stage flow)
///   POST /api/partners/remove -> partnersRemove()
///   GET/POST /api/settings    -> getSettings()/saveSettings()
///
/// The same "adding tightens (immediate), removing/unlocking loosens (needs
/// approval)" rule from the Windows app is preserved throughout.
library;

import '../models/app_config.dart';
import '../models/blocked_item.dart';
import '../models/pending_request.dart';
import '../models/unlock_state.dart';
import 'block_engine_service.dart';
import 'email_service.dart';
import 'native_bridge.dart';
import 'storage_service.dart';

/// Result of a request-submitting action, mirroring the JSON the dashboard
/// endpoints return ({ok, immediate, added, request_id, error}).
class ApiResult {
  final bool ok;
  final bool immediate;
  final bool added;
  final int? requestId;
  final String? error;

  const ApiResult({
    required this.ok,
    this.immediate = false,
    this.added = false,
    this.requestId,
    this.error,
  });

  factory ApiResult.error(String message) =>
      ApiResult(ok: false, error: message);
}

/// One item's status, mirroring dashboard_server.status()'s item_status().
class ItemStatus {
  final BlockedItem item;
  final bool locked;
  final DateTime? unlockedUntil;
  final bool unlockedIndefinitely;

  const ItemStatus({
    required this.item,
    required this.locked,
    this.unlockedUntil,
    this.unlockedIndefinitely,
  });
}

class StatusSnapshot {
  final List<ItemStatus> items;
  final List<PendingRequest> pendingRequests;
  final List<String> approverEmails;
  const StatusSnapshot({
    required this.items,
    required this.pendingRequests,
    required this.approverEmails,
  });
}

class LocalApiService {
  LocalApiService._();
  static final LocalApiService instance = LocalApiService._();

  final StorageService _storage = StorageService.instance;
  final EmailService _email = EmailService();
  final BlockEngineService _engine = BlockEngineService.instance;

  /// GET /api/status — also prunes resolved requests, like the Windows route.
  Future<StatusSnapshot> status() async {
    final cfg = await _storage.loadConfig();
    final state = await _storage.loadState();
    var requests = await _storage.loadPendingRequests();

    requests = _storage.pruneResolvedRequests(requests);
    await _storage.saveState(state, requests);

    final bl = await _storage.loadBlocklist();
    ItemStatus toStatus(BlockedItem it) {
      final info = state.unlocks[it.key];
      return ItemStatus(
        item: it,
        locked: !state.isItemUnlocked(it.key),
        unlockedUntil: info?.unlockedUntil,
        unlockedIndefinitely: info?.unlockedIndefinitely ?? false,
      );
    }

    return StatusSnapshot(
      items: [...bl.apps.map(toStatus), ...bl.sites.map(toStatus)],
      pendingRequests: requests,
      approverEmails: cfg.approverEmails,
    );
  }

  static const Set<String> _validDurations = {'5', '30', '60', 'indefinite'};

  /// POST /api/request-unlock.
  Future<ApiResult> requestUnlock(BlockedItem item, String duration) async {
    if (!_validDurations.contains(duration)) {
      return ApiResult.error('invalid duration');
    }
    final cfg = await _storage.loadConfig();
    if (!cfg.isValid) {
      return ApiResult.error(
          'Finish setting up the Gmail account in Settings first.');
    }
    try {
      final req = await _engine.requestUnlock(cfg, item, duration: duration);
      return ApiResult(ok: true, requestId: req.id);
    } catch (e) {
      return ApiResult.error("Couldn't send the request email: $e");
    }
  }

  /// POST /api/lock-now — with an item, locks just it; without, locks all.
  /// Tightening a restriction, so no approval. Ported from api_lock_now().
  Future<ApiResult> lockNow({BlockedItem? item}) async {
    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();
    if (item != null) {
      state.lockItemNow(item.key);
    } else {
      state.lockAllNow();
    }
    await _storage.saveState(state, requests);
    await NativeBridge.instance.notifyStateChanged();
    return const ApiResult(ok: true);
  }

  /// POST /api/cancel-request — drops one request by id (Cancel or Dismiss).
  Future<ApiResult> cancelRequest(int id) async {
    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();
    final before = requests.length;
    requests.removeWhere((r) => r.id == id);
    await _storage.saveState(state, requests);
    return ApiResult(ok: requests.length < before);
  }

  /// POST /api/clear-resolved — bulk-dismiss resolved; never touches pending.
  Future<int> clearResolved() async {
    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();
    final before = requests.length;
    final kept =
        requests.where((r) => r.status == RequestStatus.pending).toList();
    await _storage.saveState(state, kept);
    return before - kept.length;
  }

  /// POST /api/request-change — add (immediate) or remove (approval) an item.
  /// Ported from request_change().
  Future<ApiResult> requestChange({
    required bool isAdd,
    required BlockedItem item,
  }) async {
    if (isAdd) {
      final added = await _storage.addBlocklistItem(item);
      await NativeBridge.instance.notifyStateChanged();
      return ApiResult(ok: true, immediate: true, added: added);
    }
    final cfg = await _storage.loadConfig();
    if (!cfg.isValid) {
      return ApiResult.error(
          'Finish setting up the Gmail account in Settings first.');
    }
    try {
      final req = await _engine.requestRemove(cfg, item);
      return ApiResult(ok: true, immediate: false, requestId: req.id);
    } catch (e) {
      return ApiResult.error("Couldn't send the request email: $e");
    }
  }

  /// POST /api/partners/add — first-ever partner applies immediately; otherwise
  /// only approver_emails[0] can approve a partner_add. Ported from
  /// add_partner_route().
  Future<ApiResult> partnersAdd(String email) async {
    email = email.trim();
    if (email.isEmpty || !email.contains('@')) {
      return ApiResult.error('Enter a valid email address.');
    }
    final cfg = await _storage.loadConfig();

    if (cfg.approverEmails.contains(email)) {
      return const ApiResult(ok: true, immediate: true, added: false);
    }
    // The very first partner has no one to approve it — apply immediately.
    if (cfg.approverEmails.isEmpty) {
      cfg.approverEmails.add(email);
      await _storage.saveConfig(cfg);
      return const ApiResult(ok: true, immediate: true, added: true);
    }
    if (!cfg.isValid) {
      return ApiResult.error(
          'Finish setting up the Gmail account below before requesting changes.');
    }

    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();
    final reqId = state.takeNextId();
    try {
      final sent = await _email.sendApprovalEmail(
        cfg,
        reqId,
        'Request to add "$email" as a new approval partner. Approve to send '
        "them an invite (they'll still need to accept it themselves before "
        "they're actually added), or deny to leave the partner list unchanged.",
        recipients: [cfg.approverEmails.first],
      );
      requests.add(PendingRequest(
        id: reqId,
        type: RequestType.partnerAdd,
        detail: email,
        sentAt: DateTime.now(),
        messageId: sent.messageId,
      ));
      await _storage.saveState(state, requests);
      return ApiResult(ok: true, immediate: false, requestId: reqId);
    } catch (e) {
      return ApiResult.error("Couldn't send the request email: $e");
    }
  }

  /// POST /api/partners/remove — goes through approval; needs >= 1 partner left.
  /// Ported from remove_partner_route().
  Future<ApiResult> partnersRemove(String email) async {
    email = email.trim();
    final cfg = await _storage.loadConfig();
    if (!cfg.approverEmails.contains(email)) {
      return ApiResult.error("That's not a current partner.");
    }
    if (cfg.approverEmails.length <= 1) {
      return ApiResult.error(
          "Can't remove your only partner — add another partner first.");
    }
    if (!cfg.isValid) {
      return ApiResult.error(
          'Finish setting up the Gmail account below before requesting changes.');
    }
    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();
    final reqId = state.takeNextId();
    try {
      final sent = await _email.sendApprovalEmail(
        cfg,
        reqId,
        'Request to remove "$email" as an approval partner. Approve to confirm, '
        'or deny to keep them as a partner.',
        recipients: [cfg.approverEmails.first],
      );
      requests.add(PendingRequest(
        id: reqId,
        type: RequestType.partnerRemove,
        detail: email,
        sentAt: DateTime.now(),
        messageId: sent.messageId,
      ));
      await _storage.saveState(state, requests);
      return ApiResult(ok: true, requestId: reqId);
    } catch (e) {
      return ApiResult.error("Couldn't send the request email: $e");
    }
  }

  /// GET /api/settings.
  Future<AppConfig> getSettings() => _storage.loadConfig();

  /// POST /api/settings — saves ONLY the Gmail account (partners are managed
  /// via partnersAdd/partnersRemove). Ported from save_settings().
  Future<ApiResult> saveSettings({
    required String gmailAddress,
    required String gmailAppPassword,
  }) async {
    final gmail = gmailAddress.trim();
    final pw = gmailAppPassword.trim().replaceAll(' ', '');
    if (gmail.isEmpty || !gmail.contains('@')) {
      return ApiResult.error('Enter a valid Gmail address.');
    }
    if (pw.isEmpty) {
      return ApiResult.error('Enter the Gmail App Password.');
    }
    final cfg = await _storage.loadConfig();
    await _storage.saveConfig(
        cfg.copyWith(gmailAddress: gmail, gmailAppPassword: pw));
    return const ApiResult(ok: true);
  }
}
