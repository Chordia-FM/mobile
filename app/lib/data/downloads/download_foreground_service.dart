import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps a long download batch alive while the screen is off, and shows what it is doing.
///
/// Android kills background work within seconds of the screen locking unless a foreground service
/// is running, and a user who queues an album and pockets their phone expects to come back to an
/// album. The `FOREGROUND_SERVICE_DATA_SYNC` type is exactly this case, and the notification is not
/// a nicety — the platform requires one, and the user is entitled to see that their battery and
/// data are being spent.
///
/// **Nothing here is load-bearing for correctness.** The queue is a table on disk and every task
/// resumes from a byte offset, so a device that refuses the service, an OS that kills the process
/// anyway, or a platform with no such concept at all all reach the same place: the batch continues
/// on next launch. That is why every call below is allowed to fail silently.
abstract interface class DownloadForegroundService {
  /// Raises the service and shows [done] of [total] finished. Idempotent — called on every
  /// progress change, not only on the first.
  Future<void> update({required int done, required int total});

  /// Drops the service and its notification. Called when the queue drains, however it drained.
  Future<void> stop();
}

/// The service on a platform that has none. Used on iOS, on desktop and in tests.
class NoDownloadForegroundService implements DownloadForegroundService {
  const NoDownloadForegroundService();

  @override
  Future<void> update({required int done, required int total}) async {}

  @override
  Future<void> stop() async {}
}

/// Drives the Android side over a method channel.
///
/// Deliberately tolerant of a missing handler: an app built without the native half still
/// downloads, it simply stops when Android decides it has been in the background too long. Turning
/// that into a thrown exception would take the whole queue down over a notification.
class AndroidDownloadForegroundService implements DownloadForegroundService {
  const AndroidDownloadForegroundService({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  /// The channel the native `DownloadService` listens on. See the wiring note in the class doc of
  /// `DownloadManager`.
  static const channelName = 'fm.chordia.mobile/downloads';

  final MethodChannel _channel;

  @override
  Future<void> update({required int done, required int total}) =>
      _invoke('start', {'done': done, 'total': total});

  @override
  Future<void> stop() => _invoke('stop', const {});

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // The service was refused — notifications denied, or a background-start restriction.
    } on MissingPluginException {
      // No native handler in this build.
    }
  }
}

/// The right service for the platform the app is running on.
DownloadForegroundService defaultForegroundService() => Platform.isAndroid
    ? const AndroidDownloadForegroundService()
    : const NoDownloadForegroundService();
