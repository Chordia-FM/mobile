import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// A SHA-256 fingerprint of a TLS leaf certificate, as advertised by the Hub directory.
///
/// The Hub stores it as lowercase hex, but operators paste fingerprints from `openssl` and browser
/// certificate viewers too, which use uppercase and colon separators. Parsing normalises all three
/// so a comparison never fails on formatting.
@immutable
class CertFingerprint {
  const CertFingerprint._(this.hex);

  /// Parses an advertised fingerprint, accepting hex with or without `:` / whitespace separators.
  ///
  /// Returns null for the empty string, which the directory uses to mean "this server terminates
  /// TLS at an edge proxy with a publicly trusted certificate — validate it normally".
  static CertFingerprint? tryParse(String? advertised) {
    if (advertised == null) return null;
    final cleaned = advertised.replaceAll(RegExp(r'[\s:]'), '').toLowerCase();
    if (cleaned.isEmpty) return null;
    if (cleaned.length != 64 || !_isHex(cleaned)) return null;
    return CertFingerprint._(cleaned);
  }

  /// Computes the fingerprint of a DER-encoded certificate.
  factory CertFingerprint.ofDer(List<int> der) =>
      CertFingerprint._(_hex(sha256.convert(der).bytes));

  /// Lowercase, separator-free hex.
  final String hex;

  bool matchesDer(List<int> der) {
    final other = _hex(sha256.convert(der).bytes);
    // Fixed length and not secret-dependent on our side, but constant-time anyway: a fingerprint
    // comparison is exactly the shape of check that should never leak position information.
    if (other.length != hex.length) return false;
    var diff = 0;
    for (var i = 0; i < hex.length; i++) {
      diff |= hex.codeUnitAt(i) ^ other.codeUnitAt(i);
    }
    return diff == 0;
  }

  static bool _isHex(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39;
      final isLower = c >= 0x61 && c <= 0x66;
      if (!isDigit && !isLower) return false;
    }
    return true;
  }

  static String _hex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Renders the grouped uppercase form people see in certificate viewers.
  String toDisplayString() {
    final pairs = <String>[];
    for (var i = 0; i < hex.length; i += 2) {
      pairs.add(hex.substring(i, i + 2).toUpperCase());
    }
    return pairs.join(':');
  }

  @override
  bool operator ==(Object other) =>
      other is CertFingerprint && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => 'CertFingerprint(${hex.substring(0, 16)}…)';
}

/// Base64 of a DER certificate, for the rare case a fingerprint has to cross an isolate boundary.
String encodeDer(List<int> der) => base64Encode(der);
