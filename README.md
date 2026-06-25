# mobile - Chordia

> The mobile client, with custom native audio modules for bit-perfect and spatial output.
> Foundational scaffold, built out post-MVP.

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-orange)](./LICENSE)

## Overview

Flutter UI over native audio engines. The shared Flutter layer handles auth, browsing, social,
and rooms; the platform-native modules (Kotlin/ExoPlayer, Swift/AVAudioEngine) own the
bit-perfect output path and Dolby Atmos passthrough that a pure-Flutter player can't guarantee.
It uses the same control plane (Hub) and direct-streaming data plane as the web client. See the
[topology](https://github.com/chordia-fm/contracts/blob/main/docs/ARCHITECTURE.md#1-topology).

## Architecture

- **Stack:** Flutter (Dart), Riverpod, Dio, Drift (local SQLite), plus native Kotlin/Swift audio.
- **Native bridge:** `fm.chordia/native_audio` MethodChannel to `lib/audio/native_audio.dart`.
- **Local store:** offline scrobble queue and own-copy index (Drift), mirroring the web client.

## Project layout

```
lib/
  main.dart
  core/        config, DI, contracts binding
  features/    auth, catalog, streaming, rooms, insights
  audio/       MethodChannel facade
android/app/src/main/kotlin/fm/chordia/mobile/  native module (ExoPlayer, bit-perfect, Atmos)
ios/Runner/                                      native module (AVAudioEngine, spatial)
```

## Getting started

```bash
flutter create .          # generates the platform projects around this lib/ + native sources
flutter pub get
flutter run
```

## License

AGPL-3.0, see [LICENSE](./LICENSE).
