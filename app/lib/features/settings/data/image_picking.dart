import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// One image the account holder chose off their device.
@immutable
class PickedImage {
  const PickedImage({required this.bytes, required this.contentType});

  final Uint8List bytes;

  /// What the picker says the bytes are. A hint only — the Hub derives the stored mime from its
  /// own decoder — but sending it is what lets an animated GIF stay animated for an account
  /// entitled to one.
  final String contentType;
}

/// Picks one image, or null when the sheet was dismissed without choosing.
///
/// A function type rather than a class so a widget test can hand the screen a picked file without
/// a plugin: the test binding answers every platform channel with an error, and a real
/// `ImagePicker` call inside a test would fail on the channel rather than on anything under test.
typedef PickImage = Future<PickedImage?> Function({required int maxWidth});

/// The device's own gallery picker, resizing before the bytes reach Dart.
///
/// `maxWidth` is not a nicety: `POST /v1/images` refuses anything over 8 MB and a modern phone
/// photo is routinely well past that, so an unresized upload fails for the one reason the user can
/// do nothing about. The resize happens natively, so the full-size original is never decoded here.
///
/// Gallery only, never the camera: a camera source needs an `NSCameraUsageDescription` in the iOS
/// bundle to so much as launch, and choosing a picture is the thing people actually do here.
Future<PickedImage?> pickGalleryImage({required int maxWidth}) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: maxWidth.toDouble(),
    imageQuality: 90,
  );
  if (file == null) return null;
  return PickedImage(
    bytes: await file.readAsBytes(),
    // `imageQuality` re-encodes, so the picked file's own type can be stale; JPEG is what that
    // re-encode produces on both platforms and the Hub re-derives it regardless.
    contentType: file.mimeType ?? 'image/jpeg',
  );
}

/// How images get off this device. Overridden with a fake in tests.
final imagePickerProvider = Provider<PickImage>((ref) => pickGalleryImage);
