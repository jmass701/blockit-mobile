/// AppPickerScreen — lists installed launchable apps (via the native
/// PackageManager query on the MethodChannel) so the user can pick one to block.
/// Returns the chosen InstalledApp to HomeScreen. Adding tightens restrictions,
/// so the actual add happens immediately with no approval.
library;

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../theme/app_theme.dart';

class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({super.key});

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  List<InstalledApp>? _apps;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await NativeBridge.instance.listInstalledApps();
    if (mounted) setState(() => _apps = apps);
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
      appBar: AppBar(title: const Text('Pick an app to block')),
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
                  return ListTile(
                    title: Text(app.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(app.packageName,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.gray500)),
                    trailing: const Icon(Icons.add, color: AppColors.teal),
                    onTap: () => Navigator.of(context).pop(app),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
