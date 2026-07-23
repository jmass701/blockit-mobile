/// UnlockState — Dart equivalent of state.json's "unlocks" map plus the
/// bookkeeping fields around it (last_unlock_request_sent, next_id).
///
/// Mirrors blocker_common.py's load_state()/save_state() shape and the
/// is_item_unlocked() / lock_item_now() / lock_all_now() helpers. Each app/site
/// has its OWN independent lock, keyed by item_key() ("kind:target") — unlocking
/// one item never touches another.
library;

/// Per-item unlock record: either unlocked until a wall-clock time, or unlocked
/// indefinitely (until manually re-locked). Absent key == locked (the default).
class UnlockInfo {
  final DateTime? unlockedUntil;
  final bool unlockedIndefinitely;

  const UnlockInfo({this.unlockedUntil, this.unlockedIndefinitely = false});

  factory UnlockInfo.fromJson(Map<String, dynamic> json) => UnlockInfo(
        unlockedUntil: json['unlocked_until'] != null
            ? DateTime.tryParse(json['unlocked_until'].toString())
            : null,
        unlockedIndefinitely: json['unlocked_indefinitely'] == true,
      );

  Map<String, dynamic> toJson() => {
        'unlocked_until': unlockedUntil?.toIso8601String(),
        'unlocked_indefinitely': unlockedIndefinitely,
      };
}

class UnlockState {
  /// item_key -> UnlockInfo
  final Map<String, UnlockInfo> unlocks;

  /// item_key -> ISO timestamp of the last auto-fired unlock request (cooldown).
  final Map<String, DateTime> lastUnlockRequestSent;

  int nextId;

  UnlockState({
    Map<String, UnlockInfo>? unlocks,
    Map<String, DateTime>? lastUnlockRequestSent,
    this.nextId = 1,
  })  : unlocks = unlocks ?? {},
        lastUnlockRequestSent = lastUnlockRequestSent ?? {};

  /// Ported from blocker_common.is_item_unlocked().
  bool isItemUnlocked(String key) {
    final info = unlocks[key];
    if (info == null) return false;
    if (info.unlockedIndefinitely) return true;
    final until = info.unlockedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  /// Ported from blocker_common.lock_item_now() — tightening a restriction,
  /// so no approval needed.
  void lockItemNow(String key) => unlocks.remove(key);

  /// Ported from blocker_common.lock_all_now().
  void lockAllNow() => unlocks.clear();

  /// Consumes the next request id, mirroring state["next_id"] += 1.
  int takeNextId() {
    final id = nextId;
    nextId += 1;
    return id;
  }
}
