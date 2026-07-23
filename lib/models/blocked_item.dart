/// BlockedItem — one entry on the blocklist (Dart equivalent of an element of
/// blocklist.json's blocked_processes / blocked_domains lists).
///
/// The Windows app stores these as bare strings (process name / domain). On
/// Android an "app" is identified by its package name, which is opaque, so we
/// also carry a human-readable [name] for display. Sites keep name == target.
///
/// [kind] is either "app" or "site", matching the two argument forms used
/// throughout blocker_common.py (item_key(kind, target), add_blocklist_item).
library;

enum ItemKind { app, site }

extension ItemKindX on ItemKind {
  String get wire => this == ItemKind.app ? 'app' : 'site';
  static ItemKind fromWire(String s) =>
      s == 'app' ? ItemKind.app : ItemKind.site;
}

class BlockedItem {
  final ItemKind kind;

  /// The match target: an Android package name (e.g. "com.instagram.android")
  /// for apps, or a domain (e.g. "facebook.com") for sites.
  final String target;

  /// Display label. For sites this equals [target]; for apps it's the app label.
  final String name;

  const BlockedItem({
    required this.kind,
    required this.target,
    required this.name,
  });

  /// Canonical per-item identifier — ported verbatim from
  /// blocker_common.item_key(): "{kind}:{target.strip().lower()}".
  String get key => '${kind.wire}:${target.trim().toLowerCase()}';

  factory BlockedItem.fromJson(ItemKind kind, dynamic json) {
    // Be tolerant of a legacy bare-string entry as well as the object form.
    if (json is String) {
      return BlockedItem(kind: kind, target: json, name: json);
    }
    final map = json as Map<String, dynamic>;
    final target = (map['target'] ?? '').toString();
    return BlockedItem(
      kind: kind,
      target: target,
      name: (map['name'] ?? target).toString(),
    );
  }

  Map<String, dynamic> toJson() => {'target': target, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is BlockedItem && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
