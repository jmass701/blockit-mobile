/// AppPickerScreen — lists installed launchable apps (via the native
/// PackageManager query on the MethodChannel) so the user can pick one or
/// more to block. Already-blocked apps are shown with a "Blocked" badge
/// (and can't be re-selected). Tapping a row toggles its checkbox; nothing
/// is added until "Add" is pressed, so multiple apps can be queued up in one
/// visit instead of re-opening this screen per app. Returns the list of
/// chosen InstalledApps to HomeScreen. Adding tightens restrictions, so the
/// actual add happens immediately with no approval.
library;

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../theme/app_theme.dart';

class AppPickerScreen extends StatefulWidget {
  /// Package names already on the blocklist, so this screen can show them as
  /// already-selected instead of letting the user pick them again.
  final Set<String> blockedPackages;

  const AppPickerScreen({super.key, this.blockedPackages = const {}});

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  List<InstalledApp>? _apps;
  String _query = '';
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await NativeBridge.instance.listInstalledApps();
    if (mounted) setState(() => _apps = apps);
  }

  void _toggle(InstalledApp app) {
    if (widget.blockedPackages.contains(app.packageName)) return;
    setState(() {
      if (_selected.contains(app.packageName)) {
        _selected.remove(app.packageName);
      } else {
        _selected.add(app.packageName);
      }
    });
  }

  void _submit() {
    final apps = _apps ?? const <InstalledApp>[];
    final chosen =
        apps.where((a) => _selected.contains(a.packageName)).toList();
    Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    final filtered = apps == null
        ? const <InstalledApp>[]
        : apps
            .where((a) =>
                a.label.toLowerCase().contains(_query.toLowerCase()) ||
                a.packageName.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty
            ? 'Pick apps to block'
            : '${_selected.length} selected'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _submit,
              child: Text('Add (${_selected.length})',
                  style: const TextStyle(
                      color: AppColors.teal, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search apps',
                prefixIcon: Icon(Icons.search, color: AppColors.gray500),
              ),
            ),
          ),
          if (apps == null)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.gray200),
                itemBuilder: (_, i) {
                  final app = filtered[i];
                  final alreadyBlocked =
                      widget.blockedPackages.contains(app.packageName);
                  final isSelected = _selected.contains(app.packageName);
                  return ListTile(
                    title: Text(app.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(app.packageName,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.gray500)),
                    tileColor: isSelected
                        ? AppColors.teal.withOpacity(0.08)
                        : null,
                    enabled: !alreadyBlocked,
                    trailing: alreadyBlocked
                        ? const _BlockedBadge()
                        : Checkbox(
                            value: isSelected,
                            activeColor: AppColors.teal,
                            onChanged: (_) => _toggle(app),
                          ),
                    onTap: alreadyBlocked ? null : () => _toggle(app),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BlockedBadge extends StatelessWidget {
  const _BlockedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: AppColors.gray200),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: AppColors.gray500),
          SizedBox(width: 4),
          Text('Blocked',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gray500)),
        ],
      ),
    );
  }
}
