import 'package:meta/meta.dart';

/// Decides when a play has counted.
///
/// The rule is Last.fm's, and the one `contracts/docs/ARCHITECTURE.md` §4 states for Chordia:
/// **half the track, or four minutes, whichever comes first**. It fires at most once per queue
/// entry, because `listening_events` is append-only — a second fire is a play the user never made
/// and no later correction can subtract it from a rollup.
///
/// The class holds no timer and reads no clock. It is driven by playhead samples, so the whole of
/// its behaviour — a pause, a scrub, a track change — is expressible as a scripted list of
/// positions in a test, and the engine's tick source stays the engine's business.
class ScrobbleLatch {
  ScrobbleLatch({this.seekToleranceMs = defaultSeekToleranceMs});

  /// The absolute arm of the threshold: four minutes of a long track is a play, however small a
  /// fraction of it that is.
  static const fullPlayCeilingMs = 4 * 60 * 1000;

  /// The largest forward jump between two samples that is still believed to be playback.
  ///
  /// Anything bigger is treated as a seek and credits nothing. The engine samples about once a
  /// second, so two seconds absorbs a late or coalesced tick; a genuinely delayed sample therefore
  /// under-credits rather than over-credits, which is the only safe direction — a scrobble that
  /// arrives a few seconds late is invisible, one the user did not earn is permanent.
  static const defaultSeekToleranceMs = 2000;

  final int seekToleranceMs;

  String? _qid;
  int _durationMs = 0;
  int _thresholdMs = fullPlayCeilingMs;
  int _accruedMs = 0;
  int _lastPositionMs = 0;
  bool _fired = false;

  /// The entry currently being measured, or null when nothing is loaded.
  String? get qid => _qid;

  /// Milliseconds of audio actually heard on this entry: pauses excluded, replayed stretches
  /// counted once, skipped-over stretches not counted at all.
  int get msPlayed => _accruedMs;

  /// Where [msPlayed] has to reach for this entry to count.
  int get thresholdMs => _thresholdMs;

  /// Whether this entry has already produced its one scrobble.
  bool get hasFired => _fired;

  /// Arms the latch for a queue entry, discarding whatever the previous one had accrued.
  ///
  /// Always resets, even when [qid] repeats: repeat-one replays the same entry, and each replay is
  /// a separate play that has to be able to scrobble again.
  ///
  /// [positionMs] is the playhead the entry starts at, which is not always zero — a resumed
  /// session restores one — and audio before it was never heard in this play.
  void start({
    required String qid,
    required int durationMs,
    int positionMs = 0,
  }) {
    _qid = qid;
    _durationMs = durationMs;
    _thresholdMs = thresholdFor(durationMs);
    _accruedMs = 0;
    _lastPositionMs = positionMs;
    _fired = false;
  }

  /// Forgets the current entry, so samples that arrive after playback stops accrue nothing.
  void clear() {
    _qid = null;
    _durationMs = 0;
    _thresholdMs = fullPlayCeilingMs;
    _accruedMs = 0;
    _lastPositionMs = 0;
    _fired = false;
  }

  /// Feeds one playhead sample.
  ///
  /// Returns the entry's `qid` on the single sample that crosses the threshold, and null on every
  /// other sample — including later ones for an entry that has already fired. Returning the id
  /// rather than invoking a callback keeps the caller in charge of ordering, and means a sample
  /// that arrives after the queue moved on cannot be mistaken for the new entry's scrobble.
  ///
  /// [playing] false covers a pause or a buffering stall: the position is still tracked, so a
  /// scrub performed while paused does not turn into credit when playback resumes, but nothing is
  /// accrued for time the user did not hear.
  String? sample(int positionMs, {bool playing = true}) {
    final qid = _qid;
    if (qid == null) return null;

    final advance = positionMs - _lastPositionMs;
    _lastPositionMs = positionMs;

    // A backwards jump is a rewind: the audio between the two positions was already credited on
    // the way past, and crediting it again is how a single listen becomes two scrobbles.
    if (playing && advance > 0 && advance <= seekToleranceMs) {
      _accruedMs += advance;
    }

    if (_fired || _accruedMs < _thresholdMs) return null;
    _fired = true;
    return qid;
  }

  /// The listening threshold for a track of [durationMs].
  ///
  /// A duration of zero or less means the catalog length is unknown, and the fraction arm cannot
  /// be evaluated at all; the four-minute arm still can, so it stands alone rather than letting an
  /// unknown length either scrobble instantly or never.
  @visibleForTesting
  static int thresholdFor(int durationMs) {
    if (durationMs <= 0) return fullPlayCeilingMs;
    final half = durationMs ~/ 2;
    return half < fullPlayCeilingMs ? half : fullPlayCeilingMs;
  }

  /// The catalog length of the entry being measured, kept so a caller building the event does not
  /// have to hold the track alongside the latch.
  int get durationMs => _durationMs;
}
