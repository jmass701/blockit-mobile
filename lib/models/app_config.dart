/// AppConfig — Dart equivalent of the Windows app's config.json.
///
/// Mirrors blocker_common.py's CONFIG_DEFAULTS / load_config() / config_is_valid().
/// Holds the Gmail account used for the SMTP/IMAP approval-email workflow, the
/// list of approval partners (approver_emails), and the two fixed tuning values
/// (check interval, request cooldown) that the Windows app deliberately does NOT
/// expose in Settings.
library;

/// Values that count as "not really filled in yet" — ported from
/// blocker_common.PLACEHOLDER_VALUES so config_is_valid matches the Windows app.
const Set<String> kPlaceholderValues = {
  'you@gmail.com',
  'PASTE_16_CHAR_APP_PASSWORD_HERE',
  'approver@example.com',
  '',
};

class AppConfig {
  String gmailAddress;
  String gmailAppPassword;
  List<String> approverEmails;

  /// Carrier email-to-SMS gateway addresses (e.g. "5551234567@vtext.com") that
  /// tamper alerts (uninstall attempt / accessibility disabled / VPN revoked)
  /// also get sent to, in addition to approverEmails. Optional — purely a
  /// convenience so the approver gets a text, not just an email.
  List<String> tamperAlertSmsGateways;

  /// "Strict" adult-content filter — when true, the on-device DNS filter
  /// (BlockVpnService.kt) forwards allowed queries to a content-filtering
  /// resolver (CleanBrowsing Family Filter) instead of a plain resolver,
  /// automatically blocking porn/adult sites without maintaining a manual
  /// domain list. Follows the same "tighten = immediate, loosen = needs
  /// partner approval" rule as the rest of the app: turning it ON applies
  /// right away, turning it OFF goes through the approval-request flow.
  bool adultContentFilterEnabled;

  /// Fixed at 10s, mirroring CONFIG_DEFAULTS["check_interval_seconds"] — the
  /// engine re-checks locks and polls IMAP on this cadence. Not user-editable.
  final int checkIntervalSeconds;

  /// Backstop default duration for unlock requests fired without a duration
  /// picker (e.g. an app auto-requesting when it gets blocked). Minutes.
  final int unlockDurationDefault;

  /// Per-item cooldown so a repeatedly-relaunched app doesn't spam a new
  /// approval email every check. Mirrors
  /// CONFIG_DEFAULTS["cooldown_between_unlock_requests_minutes"].
  final int cooldownBetweenUnlockRequestsMinutes;

  AppConfig({
    this.gmailAddress = '',
    this.gmailAppPassword = '',
    List<String>? approverEmails,
    List<String>? tamperAlertSmsGateways,
    this.adultContentFilterEnabled = false,
    this.checkIntervalSeconds = 10,
    this.unlockDurationDefault = 30,
    this.cooldownBetweenUnlockRequestsMinutes = 10,
  })  : approverEmails = approverEmails ?? <String>[],
        tamperAlertSmsGateways = tamperAlertSmsGateways ?? <String>[];

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    // Support the legacy single "approver_email" field the same way load_config
    // migrates it into the approver_emails list.
    List<String> approvers;
    if (json['approver_emails'] is List) {
      approvers = (json['approver_emails'] as List)
          .map((e) => e.toString())
          .toList();
    } else {
      final legacy = json['approver_email'];
      approvers = (legacy != null && !kPlaceholderValues.contains(legacy))
          ? <String>[legacy.toString()]
          : <String>[];
    }
    final smsGateways = (json['tamper_alert_sms_gateways'] is List)
        ? (json['tamper_alert_sms_gateways'] as List)
            .map((e) => e.toString())
            .toList()
        : <String>[];
    return AppConfig(
      gmailAddress: (json['gmail_address'] ?? '').toString(),
      gmailAppPassword: (json['gmail_app_password'] ?? '').toString(),
      approverEmails: approvers,
      tamperAlertSmsGateways: smsGateways,
      adultContentFilterEnabled:
          (json['adult_content_filter_enabled'] as bool?) ?? false,
      // check_interval_seconds and cooldown are FORCED to their defaults on
      // every load in the Windows app (see _FORCED_KEYS) — do the same here so
      // a stale saved value can't override them.
      checkIntervalSeconds: 10,
      unlockDurationDefault: (json['unlock_duration_minutes'] as num?)?.toInt() ?? 30,
      cooldownBetweenUnlockRequestsMinutes: 10,
    );
  }

  Map<String, dynamic> toJson() => {
        'gmail_address': gmailAddress,
        'gmail_app_password': gmailAppPassword,
        'approver_emails': approverEmails,
        'tamper_alert_sms_gateways': tamperAlertSmsGateways,
        'adult_content_filter_enabled': adultContentFilterEnabled,
        'unlock_duration_minutes': unlockDurationDefault,
        'check_interval_seconds': checkIntervalSeconds,
        'cooldown_between_unlock_requests_minutes':
            cooldownBetweenUnlockRequestsMinutes,
      };

  /// True if the required fields have real (non-placeholder) values.
  /// Ported from blocker_common.config_is_valid().
  bool get isValid {
    for (final v in [gmailAddress, gmailAppPassword]) {
      if (v.isEmpty || kPlaceholderValues.contains(v)) return false;
    }
    if (approverEmails.isEmpty) return false;
    if (approverEmails.any((e) => e.isEmpty || kPlaceholderValues.contains(e))) {
      return false;
    }
    return true;
  }

  AppConfig copyWith({
    String? gmailAddress,
    String? gmailAppPassword,
    List<String>? approverEmails,
    List<String>? tamperAlertSmsGateways,
    bool? adultContentFilterEnabled,
  }) =>
      AppConfig(
        gmailAddress: gmailAddress ?? this.gmailAddress,
        gmailAppPassword: gmailAppPassword ?? this.gmailAppPassword,
        approverEmails: approverEmails ?? List<String>.from(this.approverEmails),
        tamperAlertSmsGateways: tamperAlertSmsGateways ??
            List<String>.from(this.tamperAlertSmsGateways),
        adultContentFilterEnabled:
            adultContentFilterEnabled ?? this.adultContentFilterEnabled,
        checkIntervalSeconds: checkIntervalSeconds,
        unlockDurationDefault: unlockDurationDefault,
        cooldownBetweenUnlockRequestsMinutes:
            cooldownBetweenUnlockRequestsMinutes,
      );
}
