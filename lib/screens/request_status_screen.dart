/// RequestStatusScreen — a standalone view of all approval requests, reusing the
/// same RequestCard the Home "Request status" section uses. HomeScreen already
/// embeds this as a section (matching the single-page web dashboard); this
/// screen exists for a dedicated, full-height list with the "Clear resolved"
/// bulk action, and can be pushed from anywhere that wants it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pending_request.dart';
import '../services/local_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/request_card.dart';

class RequestStatusScreen extends StatefulWidget {
  const RequestStatusScreen({super.key});

  @override
  State<RequestStatusScreen> createState() => _RequestStatusScreenState();
}

class _RequestStatusScreenState extends State<RequestStatusScreen> {
  final LocalApiService _api = LocalApiService.instance;
  List<PendingRequest> _requests = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final snap = await _api.status();
    if (mounted) setState(() => _requests = snap.pendingRequests);
  }

  @override
  Widget build(BuildContext context) {
    final hasResolved =
        _requests.any((r) => r.status != RequestStatus.pending);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request status',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          if (hasResolved)
            TextButton(
              onPressed: () async {
                await _api.clearResolved();
                _refresh();
              },
              child: const Text('Clear resolved'),
            ),
        ],
      ),
      body: _requests.isEmpty
          ? const Center(
              child: Text('Nothing pending.',
                  style: TextStyle(color: AppColors.gray500)))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _requests
                    .map((r) => RequestCard(
                          request: r,
                          onDismiss: () async {
                            await _api.cancelRequest(r.id);
                            _refresh();
                          },
                        ))
                    .toList(),
              ),
            ),
    );
  }
}
