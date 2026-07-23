/// CountdownText — a self-ticking countdown label for an unlocked item, the
/// Flutter equivalent of the web dashboard's ".countdown-value" spans that each
/// carry their own target time and tick every second (see tickCountdowns() in
/// index.html). Formats like fmtCountdown(): "m:ss" or "h:mm:ss".
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CountdownText extends StatefulWidget {
  final DateTime until;

  /// Called once when the countdown crosses zero, so the parent can re-check
  /// with the engine (the item should be re-locked server-side any moment).
  final VoidCallback? onExpired;

  const CountdownText({super.key, required this.until, this.onExpired});

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _timer;
  bool _firedExpired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_firedExpired && _remaining().isNegative) {
        _firedExpired = true;
        widget.onExpired?.call();
      }
    });
  }

  Duration _remaining() => widget.until.difference(DateTime.now());

  static String format(Duration d) {
    if (d.isNegative || d == Duration.zero) return '0:00';
    final totalSec = (d.inMilliseconds / 1000).ceil();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      format(_remaining()),
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
        color: AppColors.green,
      ),
    );
  }
}
