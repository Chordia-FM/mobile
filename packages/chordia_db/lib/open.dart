/// The Flutter half of [ChordiaDatabase]: opening the file on a real device.
///
/// Separate from `package:chordia_db/chordia_db.dart` because importing it pulls in Flutter, and
/// the package's own tests — plus every other pure-Dart package in this workspace — run on the
/// plain Dart VM where `dart:ui` does not exist.
library;

import 'package:drift_flutter/drift_flutter.dart';

import 'chordia_db.dart';

export 'chordia_db.dart';

/// Opens the on-device database, creating it on first launch.
///
/// [name] becomes the file name inside the platform's application-support directory — the one
/// place an OS backup includes and a cache sweep does not, which is what a queue of undelivered
/// scrobbles needs.
ChordiaDatabase openChordiaDatabase({String name = 'chordia'}) =>
    ChordiaDatabase(driftDatabase(name: name));
