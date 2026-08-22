import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'playlists_api.dart';

/// The Hub-backed editing calls, or null while there is no signed-in hub.
///
/// Every playlist EDITING surface reads this one provider rather than reaching for `hubClient`, so
/// a test can override it with a fake and drive a sheet without a transport.
final playlistsEditApiProvider = Provider<PlaylistsApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubPlaylistsApi(hub);
});

final smartPlaylistsApiProvider = Provider<SmartPlaylistsApi?>((ref) {
  final hub = ref.watch(hubClientProvider);
  return hub == null ? null : HubSmartPlaylistsApi(hub);
});

/// A photo chosen from the device, for a playlist cover.
///
/// The bytes, not a path: the upload posts them straight to `POST /v1/images`, and a path would
/// make this port different on each platform for no gain.
class CoverPhoto {
  const CoverPhoto({required this.bytes, this.name});

  final Uint8List bytes;

  /// The original file name, shown while the upload is in flight. Null when the platform does not
  /// give one.
  final String? name;
}

/// How this feature asks the platform for a picture.
///
/// Declared as a port for the same reason `libraryHandoffProvider` is: choosing a photo needs a
/// gallery plugin, the app does not carry one yet, and the honest state is a cover sheet that
/// offers what it can actually do rather than a button that fails when pressed. Overriding this
/// with a real picker turns the "Upload a photo" row on — nothing else changes.
typedef CoverPhotoPicker = Future<CoverPhoto?> Function();

/// Null until the app is built with a gallery picker.
final coverPhotoPickerProvider = Provider<CoverPhotoPicker?>((ref) => null);
