/// PinService — hashing helper for the in-person PIN feature.
///
/// The PIN itself is never written to disk — only a salted SHA-256 hash
/// (config.json's "in_person_pin_hash") plus the random salt used to compute
/// it ("in_person_pin_salt"). A fresh random salt is generated every time the
/// PIN is set/changed, so the same PIN never produces the same on-disk hash
/// twice, and the hash can't be reversed via a precomputed table.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class PinService {
  PinService._();

  /// A random hex-encoded salt, regenerated every time the PIN is (re)set.
  static String generateSalt({int bytes = 16}) {
    final rand = Random.secure();
    final values = List<int>.generate(bytes, (_) => rand.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Salted SHA-256 hash of [pin], hex-encoded.
  static String hashPin(String pin, String salt) {
    final digest = sha256.convert(utf8.encode('$salt:$pin'));
    return digest.toString();
  }
}
