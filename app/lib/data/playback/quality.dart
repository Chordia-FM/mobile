import 'package:chordia_api/chordia_api.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// The quality ladder, best first. Index order is the whole point: "lower" means further down the
/// list, and every comparison here is an index comparison rather than a hand-written table.
const List<QualityProfile> qualityLadder = [
  QualityProfile.original,
  QualityProfile.high,
  QualityProfile.normal,
  QualityProfile.dataSaver,
];

/// What kind of link the device is on right now.
///
/// A port of the web client's `readNetwork`, with one difference that matters: a browser reports a
/// latency bucket (`effectiveType`) that the web client deliberately refuses to trust for a
/// bandwidth decision, while `connectivity_plus` reports the *interface*, which is exactly the
/// signal wanted. There is no OS-level Data Saver flag in `connectivity_plus`, so the `saveData`
/// arm of the web rule has no counterpart here.
@immutable
class NetworkStatus {
  const NetworkStatus({required this.online, required this.metered});

  /// The state to assume when the platform has not answered yet.
  ///
  /// Optimistic on both axes on purpose. Guessing "offline" would refuse to stream on a device
  /// that is perfectly connected, and guessing "metered" would silently cap the tier somebody
  /// chose — the ceiling is a safety net for the cases the OS can actually confirm, never the
  /// primary quality control.
  static const unknown = NetworkStatus(online: true, metered: false);

  static const offline = NetworkStatus(online: false, metered: false);

  /// Reads the interface list `connectivity_plus` reports.
  factory NetworkStatus.from(List<ConnectivityResult> results) {
    if (results.isEmpty) return unknown;
    if (!results.any((r) => r != ConnectivityResult.none)) return offline;

    // Both can be present at once — Android keeps cellular up while Wi-Fi associates, and a VPN
    // reports its transport alongside itself. An unmetered link being available is what decides
    // it, because that is the one the OS will route over.
    final unmetered = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
    final metered = results.any(
      (r) =>
          r == ConnectivityResult.mobile || r == ConnectivityResult.satellite,
    );
    return NetworkStatus(online: true, metered: metered && !unmetered);
  }

  final bool online;

  /// Cellular or satellite, with no unmetered link to fall back on.
  final bool metered;

  @override
  bool operator ==(Object other) =>
      other is NetworkStatus &&
      other.online == online &&
      other.metered == metered;

  @override
  int get hashCode => Object.hash(online, metered);

  @override
  String toString() =>
      'NetworkStatus(${online ? 'online' : 'offline'}${metered ? ', metered' : ''})';
}

/// The more constrained of two tiers.
QualityProfile lowerQuality(QualityProfile a, QualityProfile b) =>
    qualityLadder.indexOf(a) >= qualityLadder.indexOf(b) ? a : b;

/// The ceiling a network class permits, given the tier the listener chose.
///
/// Only ever lowers. Somebody already on `data_saver` is left alone, and on an unmetered link
/// their choice comes back untouched — this is a cap for constrained networks, not a second
/// opinion about what they want on Wi-Fi. On cellular the cap is `high`: it is the top lossy tier,
/// and it is the most that can be justified against somebody's data plan without them asking.
QualityProfile networkCeiling(QualityProfile chosen, NetworkStatus network) {
  if (!network.metered) return chosen;
  return chosen == QualityProfile.original ? QualityProfile.high : chosen;
}

/// The tier a stream should actually be requested at.
QualityProfile effectiveQuality({
  required QualityProfile chosen,
  required NetworkStatus network,
}) => lowerQuality(chosen, networkCeiling(chosen, network));
