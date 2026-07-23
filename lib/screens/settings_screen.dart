/// SettingsScreen — the Flutter counterpart of the web dashboard's #settingsModal.
///   * Collapsible Gmail account section (tap the label to expand; auto-expanded
///     when the account isn't set up yet — matches setGmailFieldsOpen()).
///   * Approval Partners list showing existing partners plus the pending states:
///       - "Awaiting approval"  (partner_add — first partner hasn't approved)
///       - "Invite sent"        (partner_invite — invitee hasn't accepted)
///       - "Removal pending"    (partner_remove)
///     add/remove wired to the two-stage flow in LocalApiService.
///   * A close (X) affordance (the AppBar back button here).
library;

import 'package:flutter/material.dart';

import '../models/pending_request.dart';
import '../services/local_api_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalApiService _api = LocalApiService.instance;

  final _gmailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _partnerController = TextEditingController();

  bool _gmailOpen = false;
  bool _obscurePassword = true;

  List<String> _partners = [];
  List<String> _pendingRemovals = [];
  List<String> _pendingAdds = [];
  List<String> _pendingInvites = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await _api.getSettings();
    final snap = await _api.status();
    final pending = snap.pendingRequests
        .where((r) => r.status == RequestStatus.pending)
        .toList();
    setState(() {
      _gmailController.text = cfg.gmailAddress;
      _passwordController.text = cfg.gmailAppPassword;
      _partners = cfg.approverEmails;
      _pendingRemovals = _detailsOf(pending, RequestType.partnerRemove);
      _pendingAdds = _detailsOf(pending, RequestType.partnerAdd);
      _pendingInvites = _detailsOf(pending, RequestType.partnerInvite);
      // Auto-expand the Gmail section when it isn't configured yet.
      _gmailOpen =
          cfg.gmailAddress.isEmpty || cfg.gmailAppPassword.isEmpty;
      _loading = false;
    });
  }

  List<String> _detailsOf(List<PendingRequest> reqs, RequestType type) =>
      reqs.where((r) => r.type == type).map((r) => r.detail).toList();

  @override
  void dispose() {
    _gmailController.dispose();
    _passwordController.dispose();
    _partnerController.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.red : AppColors.ink,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final res = await _api.saveSettings(
      gmailAddress: _gmailController.text,
      gmailAppPassword: _passwordController.text,
    );
    if (res.ok) {
      _toast('Settings saved');
      await _load();
    } else {
      setState(() => _error = res.error);
    }
  }

  Future<void> _addPartner() async {
    final email = _partnerController.text.trim();
    if (email.isEmpty) return;
    final res = await _api.partnersAdd(email);
    if (res.ok && res.immediate) {
      _partnerController.clear();
      _toast(res.added
          ? 'Added "$email" as a partner'
          : '"$email" is already a partner');
    } else if (res.ok && res.requestId != null) {
      _partnerController.clear();
      _toast('Request #${res.requestId} sent — needs the first '
          "partner's approval");
    } else {
      _toast(res.error ?? 'Could not add partner', error: true);
    }
    await _load();
  }

  Future<void> _removePartner(String email) async {
    final res = await _api.partnersRemove(email);
    if (res.ok) {
      _toast('Request #${res.requestId} sent — removing "$email" needs '
          "the first partner's approval");
    } else {
      _toast(res.error ?? 'Could not request removal', error: true);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.gray500),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Who BlockIT emails for approval.',
              style: TextStyle(fontSize: 14, color: AppColors.gray500)),
          const SizedBox(height: 16),
          _gmailSection(),
          const Divider(height: 40, color: AppColors.gray200),
          _partnerSection(),
        ],
      ),
    );
  }

  Widget _gmailSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _gmailOpen = !_gmailOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'GMAIL ACCOUNT BLOCKIT SENDS/CHECKS MAIL FROM',
                    style: AppTheme.sectionLabel(),
                  ),
                ),
                Icon(_gmailOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: AppColors.gray500),
              ],
            ),
          ),
        ),
        if (_gmailOpen) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _gmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'you@gmail.com'),
          ),
          const SizedBox(height: 12),
          Text('GMAIL APP PASSWORD', style: AppTheme.sectionLabel()),
          const SizedBox(height: 6),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: '16 characters, no spaces',
              suffixIcon: TextButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                child: Text(_obscurePassword ? 'Show' : 'Hide'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Not your normal Gmail password — generate one at '
            'myaccount.google.com/apppasswords (needs 2-Step Verification on '
            'first).',
            style: TextStyle(fontSize: 12, color: AppColors.gray500),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(fontSize: 13, color: AppColors.red)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              child: const Text('Save'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _partnerSection() {
    final rows = <Widget>[];
    for (final email in _partners) {
      final removalPending = _pendingRemovals.contains(email);
      rows.add(_partnerRow(
        email,
        trailing: removalPending
            ? _pendingLabel('Removal pending')
            : TextButton(
                onPressed: () => _removePartner(email),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.red,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('Remove',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
      ));
    }
    for (final email in _pendingAdds) {
      rows.add(_partnerRow(email,
          trailing: _pendingLabel('Awaiting approval')));
    }
    for (final email in _pendingInvites) {
      rows.add(_partnerRow(email, trailing: _pendingLabel('Invite sent')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('APPROVAL PARTNERS', style: AppTheme.sectionLabel()),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('No partners yet — add one below.',
                style: TextStyle(color: AppColors.gray500)),
          )
        else
          ...rows,
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _partnerController,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    const InputDecoration(hintText: "add a partner's email"),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _addPartner, child: const Text('Add')),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Any partner can approve an unlock or blocklist change — any one '
          'reply is enough. Adding or removing a partner is different: only '
          'the first approval partner can approve those, and there must always '
          'be at least one partner. Adding someone new is two steps — the '
          'first partner approves, then the new person gets their own invite '
          'email and has to accept it themselves. (The very first partner you '
          'add goes through instantly.)',
          style: TextStyle(
              fontSize: 12, color: AppColors.gray500, height: 1.5),
        ),
      ],
    );
  }

  Widget _partnerRow(String email, {required Widget trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: AppColors.gray200),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(email,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _pendingLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.amber));
}
