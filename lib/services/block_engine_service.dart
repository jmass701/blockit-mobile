/// BlockEngineService — the Dart "brain" of the blocker, ported from
/// blocker.py's main_loop / apply_replies / request_unlock / in_unlock_cooldown.
///
/// Runs a periodic cycle (every check_interval_seconds, fixed at 10s) that:
///   1. Polls IMAP for approval replies and applies the approved ones exactly
///      like apply_replies() — unlocking items for N minutes / indefinitely,
///      adding/removing blocklist entries, and driving the two-stage partner
///      add/invite/remove flow with the same sender-identity authorization.
///   2. Prunes resolved requests older than 24h.
///   3. Notifies the native services that state changed, so the Android
///      AccessibilityService (app blocking) and VpnService (DNS site blocking)
///      re-read the JSON and enforce the new lock set instantly.
///
/// Enforcement itself lives natively (the services read blocklist.json /
/// state.json directly — see JsonState.kt), so this engine never kills apps or
/// touches DNS itself; it only owns config/state and the email round-trip. The
/// Kotlin foreground service (EngineForegroundService.kt) keeps the process
/// alive so this timer keeps ticking, mirroring BlockIT's elevated tray process.
library;

import 'dart:async';

import '../models/app_config.dart';
import '../models/blocked_item.dart';
import '../models/pending_request.dart';
import '../models/unlock_state.dart';
import 'email_service.dart';
import 'native_bridge.dart';
import 'storage_service.dart';

class BlockEngineService {
  BlockEngineService._();
  static final BlockEngineService instance = BlockEngineService._();

  final StorageService _storage = StorageService.instance;
  final EmailService _email = EmailService();

  Timer? _timer;
  bool _cycleInFlight = false;

  /// Broadcast so UIs can refresh whenever a cycle mutates state.
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get onChanged => _changes.stream;

  bool get isRunning => _timer != null;

  /// Starts the periodic engine loop. Also asks the native side to spin up its
  /// foreground service so the process survives backgrounding.
  Future<void> start() async {
    if (_timer != null) return;
    await NativeBridge.instance.startEngine();
    final cfg = await _storage.loadConfig();
    _timer = Timer.periodic(
      Duration(seconds: cfg.checkIntervalSeconds),
      (_) => runCycle(),
    );
    // Kick one off immediately rather than waiting a full interval.
    unawaited(runCycle());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await NativeBridge.instance.stopEngine();
  }

  /// One iteration of main_loop(). Wrapped so a transient email/network error
  /// just logs-and-retries next tick, exactly like the Windows loop's
  /// try/except that sleeps 10s and continues.
  Future<void> runCycle() async {
    if (_cycleInFlight) return;
    _cycleInFlight = true;
    try {
      final cfg = await _storage.loadConfig();
      if (!cfg.isValid) return; // nothing to poll until Gmail is set up
      await applyReplies(cfg);
    } catch (_) {
      // Swallow — retry on the next tick.
    } finally {
      _cycleInFlight = false;
    }
  }

  /// Ported from blocker.py apply_replies(). Fetches replies, matches each to a
  /// still-pending request (by message-id OR ref-id), enforces the per-type
  /// sender-identity authorization, and applies approved changes.
  Future<void> applyReplies(AppConfig cfg) async {
    final replies = await _email.fetchApprovalReplies(cfg);
    if (replies.isEmpty) return;

    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();
    var blocklist = await _storage.loadBlocklist();
    var configChanged = false;

    // Follow-on invite requests queued while iterating — appended after, so we
    // don't mutate the list we're iterating (matches the Windows new_requests).
    final newRequests = <PendingRequest>[];

    for (final req in requests) {
      if (req.status != RequestStatus.pending) continue;

      final matched = _firstWhereOrNull(
        replies,
        (r) =>
            (r.messageId != null && r.messageId == req.messageId) ||
            (r.refId != null && r.refId == req.id),
      );
      if (matched == null) continue;

      // partner_add / partner_remove: only the FIRST approval partner may act.
      if (req.type == RequestType.partnerAdd ||
          req.type == RequestType.partnerRemove) {
        final firstPartner = cfg.approverEmails.isNotEmpty
            ? cfg.approverEmails.first.trim().toLowerCase()
            : null;
        if (firstPartner == null || matched.fromEmail != firstPartner) {
          continue; // leave pending — wrong person replied
        }
      }

      // partner_invite: only the invitee themselves may accept/decline.
      if (req.type == RequestType.partnerInvite) {
        final invitee = req.detail.trim().toLowerCase();
        if (invitee.isEmpty || matched.fromEmail != invitee) {
          continue;
        }
      }

      req.status =
          matched.approved ? RequestStatus.approved : RequestStatus.denied;
      req.resolvedAt = DateTime.now();

      if (!matched.approved) continue;

      switch (req.type) {
        case RequestType.unlock:
          final kind = req.kind ?? 'app';
          final target = req.target ?? req.detail;
          final key = BlockedItem(
            kind: ItemKindX.fromWire(kind),
            target: target,
            name: target,
          ).key;
          final duration = req.durationMinutes ??
              cfg.unlockDurationDefault.toString();
          if (duration == 'indefinite') {
            state.unlocks[key] =
                const UnlockInfo(unlockedUntil: null, unlockedIndefinitely: true);
          } else {
            final until = DateTime.now()
                .add(Duration(minutes: int.parse(duration)));
            state.unlocks[key] =
                UnlockInfo(unlockedUntil: until, unlockedIndefinitely: false);
          }
          break;

        case RequestType.blocklistAdd:
          if (!blocklist.apps.any((a) => a.target == req.detail)) {
            blocklist.apps.add(BlockedItem(
                kind: ItemKind.app, target: req.detail, name: req.detail));
            await _storage.saveBlocklist(blocklist);
          }
          break;

        case RequestType.blocklistRemove:
          blocklist.apps.removeWhere((a) => a.target == req.detail);
          await _storage.saveBlocklist(blocklist);
          state.unlocks.remove(
              BlockedItem(kind: ItemKind.app, target: req.detail, name: req.detail)
                  .key);
          break;

        case RequestType.domainAdd:
          if (!blocklist.sites.any((s) => s.target == req.detail)) {
            blocklist.sites.add(BlockedItem(
                kind: ItemKind.site, target: req.detail, name: req.detail));
            await _storage.saveBlocklist(blocklist);
          }
          break;

        case RequestType.domainRemove:
          blocklist.sites.removeWhere((s) => s.target == req.detail);
          await _storage.saveBlocklist(blocklist);
          state.unlocks.remove(BlockedItem(
                  kind: ItemKind.site, target: req.detail, name: req.detail)
              .key);
          break;

        case RequestType.partnerAdd:
          // First partner approving doesn't add the person outright — it sends
          // THEM an invite that only they can accept (partner_invite branch).
          final email = req.detail;
          final inviteId = state.takeNextId();
          final sent = await _email.sendApprovalEmail(
            cfg,
            inviteId,
            "You've been invited to become a BlockIT approval partner for "
            "${cfg.gmailAddress}. As a partner, you'll get emails asking you "
            "to approve or deny unlock and blocklist-change requests. Reply "
            "APPROVE to confirm, or DENY to decline the invite.",
            recipients: [email],
          );
          newRequests.add(PendingRequest(
            id: inviteId,
            type: RequestType.partnerInvite,
            detail: email,
            sentAt: DateTime.now(),
            messageId: sent.messageId,
          ));
          break;

        case RequestType.partnerInvite:
          final email = req.detail;
          if (!cfg.approverEmails.contains(email)) {
            cfg.approverEmails.add(email);
            configChanged = true;
          }
          break;

        case RequestType.partnerRemove:
          final email = req.detail;
          cfg.approverEmails.remove(email);
          configChanged = true;
          break;

        case RequestType.contentFilterDisable:
          cfg.adultContentFilterEnabled = false;
          configChanged = true;
          break;
      }
    }

    requests.addAll(newRequests);

    final pruned = _storage.pruneResolvedRequests(requests);
    await _storage.saveState(state, pruned);
    if (configChanged) await _storage.saveConfig(cfg);

    _changes.add(null);
    await NativeBridge.instance.notifyStateChanged();
  }

  /// Applies an unlock immediately, with NO email round-trip — used only by
  /// the in-person PIN flow (LocalApiService.unlockWithPin). That flow fires
  /// its own tamper alert as the safety net that normally would be "your
  /// approver had to say yes"; this just writes the same state.json shape
  /// applyReplies()'s unlock case would, so enforcement (JsonState.kt) picks
  /// it up identically either way.
  Future<void> applyDirectUnlock(BlockedItem item, String duration) async {
    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();
    if (duration == 'indefinite') {
      state.unlocks[item.key] =
          const UnlockInfo(unlockedUntil: null, unlockedIndefinitely: true);
    } else {
      final until =
          DateTime.now().add(Duration(minutes: int.parse(duration)));
      state.unlocks[item.key] =
          UnlockInfo(unlockedUntil: until, unlockedIndefinitely: false);
    }
    await _storage.saveState(state, requests);
    _changes.add(null);
    await NativeBridge.instance.notifyStateChanged();
  }

  // ---- Request creation (mirrors request_unlock / dashboard endpoints) ------

  /// Ported from request_unlock() / dashboard_server request-unlock route.
  /// Sends an approval email for one specific item and records the pending
  /// request. Records the per-item cooldown timestamp too.
  Future<PendingRequest> requestUnlock(
    AppConfig cfg,
    BlockedItem item, {
    String duration = '30',
  }) async {
    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();

    final reqId = state.takeNextId();
    final durationDesc = duration == 'indefinite'
        ? 'until you re-lock it'
        : 'for $duration minutes';
    final sent = await _email.sendApprovalEmail(
      cfg,
      reqId,
      'Unlock requested for "${item.name}" — approving will unlock it '
      '$durationDesc, or deny to leave it blocked.',
    );

    final req = PendingRequest(
      id: reqId,
      type: RequestType.unlock,
      kind: item.kind.wire,
      target: item.target,
      detail: item.name,
      durationMinutes: duration,
      sentAt: DateTime.now(),
      messageId: sent.messageId,
    );
    requests.add(req);
    state.lastUnlockRequestSent[item.key] = DateTime.now();
    await _storage.saveState(state, requests);
    _changes.add(null);
    return req;
  }

  /// Ported from in_unlock_cooldown().
  bool inUnlockCooldown(UnlockState state, String key, int cooldownMinutes) {
    final last = state.lastUnlockRequestSent[key];
    if (last == null) return false;
    return DateTime.now()
        .isBefore(last.add(Duration(minutes: cooldownMinutes)));
  }

  /// Ported from dashboard_server request-change (remove half). Sends an
  /// approval email to remove an app/site; the change only applies once
  /// approved by apply_replies().
  Future<PendingRequest> requestRemove(AppConfig cfg, BlockedItem item) async {
    final state = await _storage.loadState();
    final requests = await _storage.loadPendingRequests();
    final reqId = state.takeNextId();
    final sent = await _email.sendApprovalEmail(
      cfg,
      reqId,
      'Request to remove "${item.name}" from the blocklist. Approve to confirm '
      'this change, or deny to leave the blocklist unchanged.',
    );
    final req = PendingRequest(
      id: reqId,
      type: item.kind == ItemKind.app
          ? RequestType.blocklistRemove
          : RequestType.domainRemove,
      detail: item.target,
      sentAt: DateTime.now(),
      messageId: sent.messageId,
    );
    requests.add(req);
    await _storage.saveState(state, requests);
    _changes.add(null);
    return req;
  }

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final i in items) {
      if (test(i)) return i;
    }
    return null;
  }
}
