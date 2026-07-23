/// StorageService — file-based persistence of config.json / blocklist.json /
/// state.json in the app documents directory (via path_provider), NOT
/// shared_preferences, so the data mirrors the Windows app's on-disk files and
/// stays easy to inspect/back up.
///
/// Ported from blocker_common.py's load_config/save/load_blocklist/load_state/
/// save_state and prune_resolved_requests(). IMPORTANT: the Kotlin
/// AccessibilityService and VpnService read these SAME three files directly
/// (see JsonState.kt), so the on-disk key names here must stay in lock-step
/// with that Kotlin code.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';
import '../models/blocked_item.dart';
import '../models/pending_request.dart';
import '../models/unlock_state.dart';

class Blocklist {
  final List<BlockedItem> apps; // blocked_processes
  final List<BlockedItem> sites; // blocked_domains

  Blocklist({List<BlockedItem>? apps, List<BlockedItem>? sites})
      : apps = apps ?? [],
        sites = sites ?? [];

  List<BlockedItem> get all => [...apps, ...sites];

  /// Human summary used in unlock-request emails — ported from
  /// blocker_common.describe_blocklist().
  String describe() {
    final parts = <String>[];
    if (apps.isNotEmpty) {
      parts.add('apps: ${apps.map((a) => a.name).join(', ')}');
    }
    if (sites.isNotEmpty) {
      parts.add('sites: ${sites.map((s) => s.target).join(', ')}');
    }
    if (parts.isEmpty) return 'nothing is currently on the blocklist';
    return parts.join('; ');
  }
}

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  Directory? _dir;

  /// Resolves to the same directory the Kotlin side reads from:
  /// context.getDir("app_flutter", MODE_PRIVATE), which is exactly what
  /// path_provider's getApplicationDocumentsDirectory() returns on Android.
  Future<Directory> _documentsDir() async {
    return _dir ??= await getApplicationDocumentsDirectory();
  }

  Future<File> _file(String name) async {
    final dir = await _documentsDir();
    return File('${dir.path}/$name');
  }

  Future<Map<String, dynamic>> _readJson(String name) async {
    final f = await _file(name);
    if (!await f.exists()) return {};
    try {
      final text = await f.readAsString();
      if (text.trim().isEmpty) return {};
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeJson(String name, Map<String, dynamic> data) async {
    final f = await _file(name);
    // Pretty-print with 2-space indent to match save_json(indent=2).
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  // ---- config.json ----------------------------------------------------------

  Future<AppConfig> loadConfig() async =>
      AppConfig.fromJson(await _readJson('config.json'));

  Future<void> saveConfig(AppConfig cfg) async =>
      _writeJson('config.json', cfg.toJson());

  // ---- blocklist.json -------------------------------------------------------

  Future<Blocklist> loadBlocklist() async {
    final json = await _readJson('blocklist.json');
    final procs = (json['blocked_processes'] as List?) ?? const [];
    final domains = (json['blocked_domains'] as List?) ?? const [];
    return Blocklist(
      apps: procs.map((e) => BlockedItem.fromJson(ItemKind.app, e)).toList(),
      sites:
          domains.map((e) => BlockedItem.fromJson(ItemKind.site, e)).toList(),
    );
  }

  Future<void> saveBlocklist(Blocklist bl) async {
    await _writeJson('blocklist.json', {
      'blocked_processes': bl.apps.map((e) => e.toJson()).toList(),
      'blocked_domains': bl.sites.map((e) => e.toJson()).toList(),
    });
  }

  /// Ported from blocker_common.add_blocklist_item(): tightening a restriction,
  /// so it applies immediately with no approval. Returns true if actually added.
  Future<bool> addBlocklistItem(BlockedItem item) async {
    final bl = await loadBlocklist();
    final list = item.kind == ItemKind.app ? bl.apps : bl.sites;
    if (item.target.trim().isEmpty) return false;
    if (list.any((e) => e.key == item.key)) return false;
    list.add(item);
    await saveBlocklist(bl);
    return true;
  }

  // ---- state.json -----------------------------------------------------------

  Future<UnlockState> loadState() async {
    final json = await _readJson('state.json');

    final unlocks = <String, UnlockInfo>{};
    final rawUnlocks = json['unlocks'];
    if (rawUnlocks is Map) {
      rawUnlocks.forEach((k, v) {
        if (v is Map) {
          unlocks[k.toString()] =
              UnlockInfo.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }

    final lastSent = <String, DateTime>{};
    final rawLast = json['last_unlock_request_sent'];
    if (rawLast is Map) {
      rawLast.forEach((k, v) {
        final t = DateTime.tryParse(v.toString());
        if (t != null) lastSent[k.toString()] = t;
      });
    }

    return UnlockState(
      unlocks: unlocks,
      lastUnlockRequestSent: lastSent,
      nextId: (json['next_id'] as num?)?.toInt() ?? 1,
    );
  }

  Future<List<PendingRequest>> loadPendingRequests() async {
    final json = await _readJson('state.json');
    final raw = (json['pending_requests'] as List?) ?? const [];
    return raw
        .map((e) => PendingRequest.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Saves state.json as a single unit (unlocks + bookkeeping + requests),
  /// matching the Windows app which keeps them all in one file.
  Future<void> saveState(
    UnlockState state,
    List<PendingRequest> requests,
  ) async {
    await _writeJson('state.json', {
      'unlocks':
          state.unlocks.map((k, v) => MapEntry(k, v.toJson())),
      'last_unlock_request_sent': state.lastUnlockRequestSent
          .map((k, v) => MapEntry(k, v.toIso8601String())),
      'pending_requests': requests.map((r) => r.toJson()).toList(),
      'next_id': state.nextId,
    });
  }

  /// Ported from blocker_common.prune_resolved_requests(): drops resolved
  /// (approved/denied) requests older than [olderThanHours]; never touches
  /// still-pending ones regardless of age. Mutates and returns the list.
  List<PendingRequest> pruneResolvedRequests(
    List<PendingRequest> requests, {
    int olderThanHours = 24,
  }) {
    final cutoff =
        DateTime.now().subtract(Duration(hours: olderThanHours));
    return requests.where((r) {
      if (r.status == RequestStatus.pending) return true;
      final resolved = r.resolvedAt ?? r.sentAt;
      return resolved.isAfter(cutoff);
    }).toList();
  }
}
