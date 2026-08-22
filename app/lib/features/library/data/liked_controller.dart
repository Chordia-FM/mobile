import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart';

import 'library_api.dart';
import 'optimistic.dart';

/// The liked-songs list, and the unlike that is the only edit it offers.
///
/// Unlike is optimistic for the reason every list-removal is: the heart is a toggle, and a row
/// that lingers until a round trip lands reads as a tap that did not register — which is exactly
/// when people tap it a second time and put the song back.
class LikedController extends ChangeNotifier {
  LikedController({
    required LikedApi api,
    required void Function(Object error) onFailure,
  }) : _api = api,
       _onFailure = onFailure;

  final LikedApi _api;
  final void Function(Object error) _onFailure;

  List<BrowseTrack> _tracks = const [];
  Object? _error;
  bool _loading = true;
  bool _disposed = false;

  List<BrowseTrack> get tracks => _tracks;
  Object? get error => _error;
  bool get loading => _loading;

  /// Sum of what is on screen, so the header count and the rows can never disagree.
  int get durationMs => _tracks.fold(0, (sum, track) => sum + track.durationMs);

  Future<void> load() async {
    _loading = true;
    _notify();
    try {
      final loaded = await _api.tracks();
      if (_disposed) return;
      _tracks = loaded;
      _error = null;
    } on Object catch (error) {
      if (_disposed) return;
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<bool> unlike(BrowseTrack track) {
    final snapshot = _tracks;
    return optimistic(
      apply: () => _apply([
        for (final other in snapshot)
          if (other.id != track.id) other,
      ]),
      revert: () => _apply(snapshot),
      server: () => _api.unlike(track.id),
      onFailure: _onFailure,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _apply(List<BrowseTrack> tracks) {
    _tracks = tracks;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
