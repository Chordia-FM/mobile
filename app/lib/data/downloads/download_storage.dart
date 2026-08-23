import 'package:chordia_db/chordia_db.dart';
import 'package:flutter/foundation.dart';

/// How much of the device downloads are allowed to take, and how much they currently do.
@immutable
class DownloadStorage {
  const DownloadStorage({
    required this.usedBytes,
    required this.trackCount,
    required this.capBytes,
  });

  final int usedBytes;
  final int trackCount;

  /// Zero means no limit — the state the app ships in, because guessing a number for somebody
  /// else's phone is how a music app silently stops downloading.
  final int capBytes;

  bool get hasCap => capBytes > 0;

  /// How full the allowance is, 0…1. One when there is no cap and nothing is stored, so the meter
  /// has something defined to draw; callers that care about "no limit" ask [hasCap] first.
  double get fraction =>
      hasCap ? (usedBytes / capBytes).clamp(0.0, 1.0).toDouble() : 0;

  bool get isFull => hasCap && usedBytes >= capBytes;
}

/// The storage limit, as a stored preference.
///
/// Kept in the key/value scratch rather than a column of its own: it is one integer that no server
/// owns, which is exactly what that table is for.
class DownloadBudget {
  const DownloadBudget(this._kv);

  static const _key = 'downloads.cap_bytes';

  /// The sizes the settings row offers. Zero is "no limit" and is the default.
  ///
  /// Powers of 1024 rather than round decimal gigabytes, so the number the picker shows is the
  /// number the storage line counts down from.
  static const choices = <int>[
    0,
    1 * 1024 * 1024 * 1024,
    2 * 1024 * 1024 * 1024,
    5 * 1024 * 1024 * 1024,
    10 * 1024 * 1024 * 1024,
    25 * 1024 * 1024 * 1024,
  ];

  final KvDao _kv;

  Future<int> read() async {
    final stored = await _kv.read(_key);
    // A value written by a build that offered different choices is honoured as-is; only garbage
    // falls back to "no limit", which never refuses a download the user asked for.
    return stored == null ? 0 : (int.tryParse(stored) ?? 0);
  }

  Stream<int> watch() => _kv
      .watch(_key)
      .map((value) => value == null ? 0 : (int.tryParse(value) ?? 0));

  Future<void> write(int capBytes) =>
      _kv.write(_key, '${capBytes < 0 ? 0 : capBytes}');
}
