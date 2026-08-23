import 'dart:ui' as ui;

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
typedef PickImage =
    Future<PickedImage?> Function({required int maxWidth, bool allowAnimated});

/// Image types that carry an animation. Everything else is a still.
///
/// The web keeps the same set (`ProfileSection.tsx:109`), and for the same reason: these are the
/// three the Hub stores frame-for-frame.
const _animatedTypes = {'image/gif', 'image/webp', 'image/apng'};

/// The device's own gallery picker.
///
/// `maxWidth` is not a nicety: `POST /v1/images` refuses anything over 8 MB and a modern phone
/// photo is routinely well past that, so an unresized upload fails for the one reason the user can
/// do nothing about.
///
/// Gallery only, never the camera: a camera source needs an `NSCameraUsageDescription` in the iOS
/// bundle to so much as launch, and choosing a picture is the thing people actually do here.
///
/// [allowAnimated] is the animated-avatar entitlement, and it changes HOW the bound is applied.
/// `ImagePicker`'s own `maxWidth`/`imageQuality` resize happens natively by decoding a bitmap and
/// re-encoding it, which draws exactly one frame — that plugin-side round trip was flattening
/// every GIF anybody set from the phone, the same way the web's canvas round trip used to flatten
/// its own (`ProfileSection.tsx:220-221`). So an entitled pick goes through untouched and the
/// still it usually is gets bounded here instead.
Future<PickedImage?> pickGalleryImage({
  required int maxWidth,
  bool allowAnimated = false,
}) async {
  final picker = ImagePicker();
  if (!allowAnimated) {
    final file = await picker.pickImage(
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

  final file = await picker.pickImage(source: ImageSource.gallery);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final type = file.mimeType ?? _typeFromName(file.name);
  // The whole point of the entitlement: the original bytes, frames and all. The EXIF argument for
  // re-encoding does not apply here — GIF and animated WebP carry no GPS block — and the Hub
  // decodes and bounds the file before it stores anything.
  if (_animatedTypes.contains(type)) {
    return PickedImage(bytes: bytes, contentType: type!);
  }
  return _boundedStill(bytes, maxWidth: maxWidth, contentType: type);
}

/// A still, scaled to fit [maxWidth], since the picker was not asked to do it.
///
/// Decoded through [ui.ImageDescriptor] so the scale happens in Skia at decode time rather than by
/// allocating the full-size bitmap first — a 12-megapixel photo decoded at full size and then
/// resampled is 48 MB of heap on a device that may not have it to spare.
///
/// Every failure path answers with the ORIGINAL bytes rather than throwing. A format Skia cannot
/// decode (an iPhone HEIC is the case that happens) is still something the Hub may well accept,
/// and "please try again" is advice that can never work; letting the upload proceed at least
/// reaches an endpoint whose refusal names the actual problem.
Future<PickedImage> _boundedStill(
  Uint8List bytes, {
  required int maxWidth,
  required String? contentType,
}) async {
  final original = PickedImage(
    bytes: bytes,
    contentType: contentType ?? 'application/octet-stream',
  );
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(
      await ui.ImmutableBuffer.fromUint8List(bytes),
    );
    if (descriptor.width <= maxWidth) return original;

    final codec = await descriptor.instantiateCodec(targetWidth: maxWidth);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (png == null) return original;
    // PNG because it is the one format `Image.toByteData` encodes. Lossless at this size costs a
    // few hundred kilobytes against the 8 MB ceiling, which is not a budget worth defending.
    return PickedImage(
      bytes: png.buffer.asUint8List(),
      contentType: 'image/png',
    );
  } on Object {
    return original;
  } finally {
    descriptor?.dispose();
  }
}

/// The type a file extension implies, for the platforms whose picker reports no mime.
///
/// Only the animated three are worth naming: everything else takes the still path regardless of
/// what it is called, and guessing wrong there costs nothing.
String? _typeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.apng')) return 'image/apng';
  return null;
}

/// How images get off this device. Overridden with a fake in tests.
final imagePickerProvider = Provider<PickImage>((ref) => pickGalleryImage);
