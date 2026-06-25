import 'package:flutter/services.dart';

/// Dart facade over the platform-native audio engines via a [MethodChannel].
///
/// The native modules (Kotlin/ExoPlayer on Android, Swift/AVAudioEngine on iOS) own the
/// bit-perfect output path and spatial-audio (Dolby Atmos) passthrough that Flutter alone can't
/// guarantee. Built out post-MVP.
class NativeAudio {
  static const _channel = MethodChannel('fm.chordia/native_audio');

  /// Play a streamable URL (own-copy or relay-served) at the given quality profile.
  Future<void> play(String streamUrl, {String profile = 'original'}) {
    return _channel.invokeMethod('play', {'url': streamUrl, 'profile': profile});
  }

  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> resume() => _channel.invokeMethod('resume');

  /// Whether the current output route can render the source losslessly / spatially (drives the
  /// UI's bit-perfect + Atmos indicators).
  Future<bool> supportsBitPerfect() async {
    final result = await _channel.invokeMethod<bool>('supportsBitPerfect');
    return result ?? false;
  }
}
