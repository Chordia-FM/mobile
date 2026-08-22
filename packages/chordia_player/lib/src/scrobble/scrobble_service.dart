import 'dart:async';
import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_db/chordia_db.dart';
import 'package:chordia_sync/chordia_sync.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'fingerprint.dart';

/// Delivers one batch to `POST /v1/scrobbles:batch`.
///
/// A function rather than a `HubClient` so the service can be exercised without a live Hub, and so
/// the app decides which Hub a play belongs to — the client is per-hub and the queue is not.
typedef ScrobbleBatchSender =
    Future<ScrobbleBatchResponse> Function(List<ListeningEvent> events);

/// Delivers one `POST /v1/me/now-playing`.
typedef NowPlayingSender = Future<void> Function(NowPlayingReport report);

/// How a flush ended.
enum ScrobbleFlushOutcome {
  /// Nothing was queued.
  idle,

  /// Everything that was queued when the flush began has been acknowledged and removed.
  delivered,

  /// Skipped without touching the network, because the previous failure's backoff has not
  /// elapsed. This is what stops a burst of triggers — foreground, connectivity, track change —
  /// from turning one outage into a request per second.
  deferred,

  /// The send failed. Everything stays queued.
  failed,
}

/// What one [ScrobbleService.flush] did, for logging and diagnostics.
@immutable
class ScrobbleFlush {
  const ScrobbleFlush({
    required this.outcome,
    this.sent = 0,
    this.accepted = 0,
    this.duplicates = 0,
    this.rejected = 0,
    this.remaining = 0,
    this.error,
  });

  final ScrobbleFlushOutcome outcome;

  /// Events handed to the sender.
  final int sent;

  /// Events the Hub stored.
  final int accepted;

  /// Events the Hub had already stored under the same `event_id`. Expected and harmless: it is
  /// what makes a retry of a batch whose response was lost cost nothing.
  final int duplicates;

  /// Events that were dropped without ever being stored — rejected by the Hub as malformed, or
  /// unreadable by this build. Tracked separately from [duplicates] because a non-zero count here
  /// is listening history that is gone, which is exactly the thing worth an alert.
  final int rejected;

  /// Events still queued afterwards.
  final int remaining;

  /// The failure behind [ScrobbleFlushOutcome.failed].
  final Object? error;
}

/// The durable half of the listening pipeline: it writes plays down, then tries to deliver them.
///
/// The ordering is the point, and it is not negotiable. An event is persisted **before** any
/// network attempt, so a process death between the two still scrobbles on the next launch, and a
/// process death after a successful send costs nothing because the Hub dedupes on the UUIDv7
/// `event_id` this class mints. Delivery is therefore at-least-once, and the duplicate is absorbed
/// server-side — the opposite arrangement loses plays, which nothing can recover.
///
/// Flush triggers (connectivity regained, app foregrounded, track change, a periodic timer) are
/// deliberately not wired here. This class owns durability and the retry policy; when to try is
/// the app's, and testing a policy is far easier than testing a policy tangled up with a timer.
class ScrobbleService {
  ScrobbleService({
    required ScrobbleQueueDao queue,
    required ScrobbleBatchSender send,
    NowPlayingSender? reportNowPlayingWith,
    String? deviceId,
    String? deviceLabel,
    int Function()? clock,
    String Function()? newEventId,
    int batchSize = 100,
  }) : _queue = queue,
       _send = send,
       _nowPlaying = reportNowPlayingWith,
       _deviceId = deviceId,
       _deviceLabel = deviceLabel,
       _clock = clock ?? _wallClock,
       _newEventId = newEventId ?? _uuidV7,
       _batchSize = batchSize;

  /// Backoff after consecutive failures, indexed by how many have happened in a row.
  ///
  /// It starts at half a minute because the common failure is a phone between cells and the
  /// events are not urgent, and it stops at a quarter of an hour because a queue that is days old
  /// is no worse for waiting a few more minutes.
  static const retryBackoffMs = <int>[30000, 60000, 300000, 900000];

  /// The wait after a 4xx that is not 401.
  ///
  /// A malformed or refused batch will be refused identically however soon it is retried, so the
  /// only useful response is to stop trying for a while. The events are kept rather than dropped:
  /// the class of 4xx that reaches here is usually a server-side deploy skew, and the batch that
  /// is unacceptable to today's Hub is often fine for tomorrow's.
  static const permanentFailureBackoffMs = 900000;

  final ScrobbleQueueDao _queue;
  final ScrobbleBatchSender _send;
  final NowPlayingSender? _nowPlaying;
  final String? _deviceId;
  final String? _deviceLabel;
  final int Function() _clock;
  final String Function() _newEventId;
  final int _batchSize;

  Future<ScrobbleFlush>? _inFlight;
  int _consecutiveFailures = 0;
  int _nextAttemptAt = 0;

  /// Epoch millis before which [flush] declines to touch the network. Zero when nothing has
  /// failed.
  int get nextAttemptAt => _nextAttemptAt;

  /// Writes one play to the durable queue.
  ///
  /// Returns the event as it was persisted, so a caller can log the `event_id` it will later see
  /// acknowledged. It does not flush: the app decides whether this play is worth a request now or
  /// should ride along with the next trigger.
  ///
  /// [msPlayed] defaults to the track's catalog duration. Crossing the threshold counts as a full
  /// play, and the catalog duration is the only trustworthy length — the duration measured off a
  /// streamed transcode reads short, which is precisely what undercounted long tracks in the web
  /// client. Pass an explicit value only when the real figure is known to be better.
  Future<ListeningEvent> record({
    required PlayerTrack track,
    required int startedAt,
    int? msPlayed,
    PlayContext? context,
    PlaybackSource source = PlaybackSource.ownLibrary,
  }) async {
    final event = ListeningEvent(
      eventId: _newEventId(),
      clientType: ClientType.mobile,
      fingerprint: fingerprintOf(track),
      startedAt: startedAt,
      msPlayed: msPlayed ?? track.durationMs,
      durationMs: track.durationMs,
      source: source,
      // Which library the audio actually came from. This is what powers per-library share stats,
      // e.g. "what has this friend played out of my collection".
      libraryId: track.libraryId,
      playlistId: playlistIdOf(context),
      artist: track.artist,
      title: track.title,
    );

    await _queue.enqueue(
      eventId: event.eventId,
      payloadJson: jsonEncode(event.toJson()),
      createdAt: _clock(),
    );
    // Bound the queue here rather than at flush time: the device that needs the cap is the one
    // that never reaches a Hub, and on that device a flush is exactly what never runs.
    await _queue.prune();
    return event;
  }

  /// Sends queued events to the Hub in batches and removes what the Hub has finished with.
  ///
  /// Concurrent calls share one attempt — several triggers can fire at once (foregrounding a phone
  /// commonly regains connectivity in the same frame), and two flushes racing would send the same
  /// batch twice and delete rows out from under each other.
  ///
  /// [force] ignores the backoff window; use it for a trigger that is itself evidence the world
  /// changed, such as connectivity returning.
  Future<ScrobbleFlush> flush({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;

    if (!force && _clock() < _nextAttemptAt) {
      return _queue.count().then(
        (remaining) => ScrobbleFlush(
          outcome: ScrobbleFlushOutcome.deferred,
          remaining: remaining,
        ),
      );
    }

    final attempt = _flush();
    _inFlight = attempt;
    return attempt.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<ScrobbleFlush> _flush() async {
    var sent = 0;
    var accepted = 0;
    var duplicates = 0;
    var rejected = 0;

    while (true) {
      final batch = await _queue.takeBatch(limit: _batchSize);
      if (batch.isEmpty) break;

      final events = <ListeningEvent>[];
      final unreadable = <String>[];
      for (final row in batch) {
        final event = _decode(row);
        if (event == null) {
          unreadable.add(row.eventId);
        } else {
          events.add(event);
        }
      }
      // A payload this build cannot read is dropped for the reason the Hub would drop it: no
      // amount of retrying makes it sendable, and left in place it is a poison pill that blocks
      // every younger event behind it forever.
      if (unreadable.isNotEmpty) {
        rejected += unreadable.length;
        await _queue.deleteByIds(unreadable);
      }
      if (events.isEmpty) continue;

      final ScrobbleBatchResponse response;
      try {
        response = await _send(events);
      } catch (error) {
        _backOff(error);
        return ScrobbleFlush(
          outcome: ScrobbleFlushOutcome.failed,
          sent: sent,
          accepted: accepted,
          duplicates: duplicates,
          rejected: rejected,
          remaining: await _queue.count(),
          error: error,
        );
      }

      _consecutiveFailures = 0;
      _nextAttemptAt = 0;
      sent += events.length;
      accepted += response.accepted;
      duplicates += response.duplicates;

      // Delete exactly what was sent, plus anything the Hub named as rejected. Accepted and
      // duplicate events are indistinguishable in the response (they come back as counts, not
      // ids) and both are finished with. Rejected ids will never succeed, so keeping them would
      // resend them on every future flush; they are counted apart from the rest because losing a
      // play is the one outcome here worth noticing. The web client instead clears the whole store
      // on success, which also discards events enqueued while the request was in the air.
      final done = {...events.map((e) => e.eventId), ...?response.rejected};
      rejected += response.rejected?.length ?? 0;
      await _queue.deleteByIds(done.toList());

      if (batch.length < _batchSize) break;
    }

    final remaining = await _queue.count();
    return ScrobbleFlush(
      outcome: sent == 0 && rejected == 0
          ? ScrobbleFlushOutcome.idle
          : ScrobbleFlushOutcome.delivered,
      sent: sent,
      accepted: accepted,
      duplicates: duplicates,
      rejected: rejected,
      remaining: remaining,
    );
  }

  ListeningEvent? _decode(QueuedScrobble row) {
    try {
      final json = jsonDecode(row.payloadJson);
      if (json is! Map<String, Object?>) return null;
      return ListeningEvent.fromJson(json);
    } on Object {
      return null;
    }
  }

  void _backOff(Object error) {
    if (error is ApiException && _isUnretryable(error)) {
      // Do not climb the ladder for these: the ladder exists to space out retries of something
      // that might work, and this will not.
      _nextAttemptAt = _clock() + permanentFailureBackoffMs;
      return;
    }
    final step = _consecutiveFailures < retryBackoffMs.length
        ? _consecutiveFailures
        : retryBackoffMs.length - 1;
    _consecutiveFailures++;
    _nextAttemptAt = _clock() + retryBackoffMs[step];
  }

  /// A 4xx the client cannot fix by waiting.
  ///
  /// 401 is excluded because it is fixable: the session refreshes and the same batch goes through.
  /// A transport failure carries status 0, which is the most retryable case there is.
  static bool _isUnretryable(ApiException error) =>
      error.status >= 400 && error.status < 500 && error.status != 401;

  /// Tells the Hub what this device just started playing.
  ///
  /// Presence, not history: the Hub holds it in memory for the friends feed and for the user's own
  /// other devices, which is how a desktop window learns a phone started something. It returns
  /// nothing and swallows every failure by design — a play must never wait on, or be disturbed by,
  /// a report that is stale within seconds anyway.
  void reportNowPlaying(PlayerTrack track) {
    final send = _nowPlaying;
    if (send == null) return;
    unawaited(
      send(
        NowPlayingReport(
          artist: track.artist,
          title: track.title,
          album: track.album,
          imageUrl: track.coverUrl,
          trackId: track.id,
          deviceId: _deviceId,
          deviceLabel: _deviceLabel,
        ),
      ).catchError((Object _) {}),
    );
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  static String _uuidV7() => const Uuid().v7();
}

/// The playlist a play originated in, or null.
///
/// Only a real [PlaylistContext] qualifies. A smart playlist's id belongs to a different table,
/// and `listening_events.playlist_id` has no foreign key to reject it — a smart id written here is
/// an append-only mis-attribution, indistinguishable ever after from a deleted playlist. That is a
/// bug the web client shipped and had to fix; it is not worth repeating.
String? playlistIdOf(PlayContext? context) =>
    context is PlaylistContext ? context.id : null;
