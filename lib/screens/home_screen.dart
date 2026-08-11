/// HomeScreen — the main dashboard, the Flutter counterpart of the web
/// dashboard_static/index.html <main>. Shows:
///   * Block list  — one ItemCard per app/site, each with its own lock/unlock
///     state and countdown; tapping the lock opens the unlock duration sheet.
///   * Add to block list — pick an installed app (native PackageManager) or
///     type a site domain. Adding tightens restrictions, so it applies
///     immediately with no approval (add_blocklist_item()'s reasoning).
///   * Request status — pending/approved/denied cards with a "Clear resolved"
///     bulk action.
///
/// Live refresh: re-queries LocalApiService.status() on a poll, on native
/// engine events, on engine change notifications, and when the app resumes —
/// mirroring the web version's 4s poll + focus/visibility refresh.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/blocked_item.dart';
import '../services/block_engine_service.dart';
import '../services/local_api_service.dart';
import '../services/native_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/item_card.dart';
import '../widgets/pin_unlock_sheet.dart';
import '../widgets/request_card.dart';
import '../widgets/section_header.dart';
import '../widgets/unlock_duration_sheet.dart';
import 'app_picker_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final LocalApiService _api = LocalApiService.instance;
  final TextEditingController _siteController = TextEditingController();

  StatusSnapshot? _snapshot;
  bool _hasPin = false;
  Timer? _pollTimer;
  StreamSubscription<String>? _eventSub;
  StreamSubscription<void>? _engineSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    _eventSub =
        NativeBridge.instance.engineEvents.listen((_) => _refresh());
    _engineSub =
        BlockEngineService.instance.onChanged.listen((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _eventSub?.cancel();
    _engineSub?.cancel();
    _siteController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final snap = await _api.status();
    final cfg = await _api.getSettings();
    if (mounted) {
      setState(() {
        _snapshot = snap;
        _hasPin = cfg.hasInPersonPin;
      });
    }
  }

  void _confirm(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.red : AppColors.ink,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _requestUnlock(ItemStatus s) async {
    final duration =
        await UnlockDurationSheet.show(context, s.item.name);
    if (duration == null) return;
    final res = await _api.requestUnlock(s.item, duration);
    if (res.ok) {
      _confirm('Unlock request #${res.requestId} sent for "${s.item.name}"');
    } else {
      _confirm(res.error ?? 'Request failed', error: true);
    }
    _refresh();
  }

  Future<void> _unlockWithPin(ItemStatus s) async {
    final result = await PinUnlockSheet.show(context, s.item.name);
    if (result == null) return;
    final res = await _api.unlockWithPin(s.item, result.pin,
        duration: result.duration);
    if (res.ok) {
      _confirm(
          'Unlocked "${s.item.name}" with PIN — your approval partner has '
          'been alerted.');
    } else {
      _confirm(res.error ?? 'Could not unlock with that PIN', error: true);
    }
    _refresh();
  }

  Future<void> _lockNow(ItemStatus s) async {
    await _api.lockNow(item: s.item);
    _confirm('Locked "${s.item.name}"');
    _refresh();
  }

  Future<void> _requestRemove(ItemStatus s) async {
    final res = await _api.requestChange(isAdd: false, item: s.item);
    if (res.ok) {
      _confirm('Removal request #${res.requestId} sent — needs approval');
    } else {
      _confirm(res.error ?? 'Request failed', error: true);
    }
    _refresh();
  }

  Future<void> _addApp() async {
    final blockedPackages = (_snapshot?.items ?? const <ItemStatus>[])
        .where((s) => s.item.kind == ItemKind.app)
        .map((s) => s.item.target)
        .toSet();
    final picked = await Navigator.of(context).push<List<InstalledApp>>(
      MaterialPageRoute(
        builder: (_) => AppPickerScreen(blockedPackages: blockedPackages),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    var addedCount = 0;
    for (final app in picked) {
      final item = BlockedItem(
        kind: ItemKind.app,
        target: app.packageName,
        name: app.label,
      );
      final res = await _api.requestChange(isAdd: true, item: item);
      if (res.added) addedCount++;
    }
    _confirm(picked.length == 1
        ? (addedCount > 0
            ? 'Added "${picked.first.label}"'
            : '"${picked.first.label}" is already blocked')
        : 'Added $addedCount app${addedCount == 1 ? '' : 's'}');
    _refresh();
  }

  Future<void> _addSite() async {
    final val = _siteController.text.trim();
    if (val.isEmpty) return;
    _siteController.clear();
    final item =
        BlockedItem(kind: ItemKind.site, target: val, name: val.toLowerCase());
    final res = await _api.requestChange(isAdd: true, item: item);
    _confirm(res.added ? 'Added "$val"' : '"$val" is already blocked');
    _refresh();
  }

  Future<void> _clearResolved() async {
    final cleared = await _api.clearResolved();
    _confirm(cleared > 0
        ? 'Cleared $cleared resolved request${cleared == 1 ? '' : 's'}'
        : 'Nothing to clear');
    _refresh();
  }

  Future<void> _cancelRequest(int id) async {
    await _api.cancelRequest(id);
    _confirm('Removed');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final items = snap?.items ?? const [];
    final requests = snap?.pendingRequests ?? const [];
    final hasResolved =
        requests.any((r) => r.status.name != 'pending');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF14B8A6), AppColors.tealDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.shield_outlined,
                  color: Colors.white, size: 19),
            ),
            const SizedBox(width: 12),
            const Text('BlockIT'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: AppColors.gray500),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, color: AppColors.gray500),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SettingsScreen()));
              _refresh();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            const SectionHeader('Block list'),
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                "Each item's lock icon opens unlock options for just that item "
                "— unlocking one leaves the others blocked, and re-locking it "
                "is instant. Removing an item needs your approver's OK.",
                style: TextStyle(fontSize: 12.5, color: AppColors.gray500),
              ),
            ),
            if (items.isEmpty)
              _empty('Nothing blocked yet — add one below.')
            else
              ...items.map((s) => ItemCard(
                    status: s,
                    onRequestUnlock: () => _requestUnlock(s),
                    onLockNow: () => _lockNow(s),
                    onRequestRemove: () => _requestRemove(s),
                    onCountdownExpired: _refresh,
                    hasPin: _hasPin,
                    onUnlockWithPin: () => _unlockWithPin(s),
                  )),
            const SectionHeader('Add to block list', noApproval: true),
            _addAppCard(),
            const SizedBox(height: 12),
            _addSiteCard(),
            SectionHeader(
              'Request status',
              trailing: hasResolved
                  ? TextButton(
                      onPressed: _clearResolved,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.gray500),
                      child: const Text('Clear resolved',
                          style: TextStyle(
                              fontSize: 12.5,
                              decoration: TextDecoration.underline)),
                    )
                  : null,
            ),
            if (requests.isEmpty)
              _empty('Nothing pending.')
            else
              ...requests.map((r) => RequestCard(
                    request: r,
                    onDismiss: () => _cancelRequest(r.id),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _addAppCard() {
    return _card(
      label: 'App',
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _addApp,
          icon: const Icon(Icons.apps, size: 18),
          label: const Text('Pick an installed app'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _addSiteCard() {
    return _card(
      label: 'Website',
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _siteController,
              onSubmitted: (_) => _addSite(),
              decoration: const InputDecoration(hintText: 'e.g. facebook.com'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _addSite, child: const Text('Add')),
        ],
      ),
    );
  }

  Widget _card({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.gray200),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.gray500)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 14.5, color: AppColors.gray500)),
      );
}
