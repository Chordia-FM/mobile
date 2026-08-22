# Chordia mobile

The Flutter client for [Chordia](https://github.com/chordia-fm), a self-hosted music streaming and
social platform. Android is the current target; the code is cross-platform throughout and iOS is a
matter of bringing up the platform project, not a rewrite.

## How it fits the architecture

Chordia has two planes and the client speaks to both:

- **Control plane — the Hub.** Identity, social graph, catalog, playlists, insights, the server
  directory and the realtime socket. Reached with a bearer session token.
- **Data plane — a library server.** The audio itself, over HTTPS Range, straight from a machine the
  user controls. Reached with a short-lived capability token the Hub mints. **Audio never passes
  through the Hub.**

Library servers usually present a self-signed certificate, so they are validated by the SHA-256
fingerprint the Hub directory advertises rather than against the system trust store. That single
fact shapes the networking layer: ExoPlayer and AVPlayer do TLS in the platform stack, where Dart's
certificate callback cannot reach, so audio cannot be handed to them as a URL. Instead every byte is
fetched by Dart over a pinned connection and served to the player through a loopback proxy. The same
path gives us disk caching, offline resolution and per-request capability tokens for free.

## Layout

This is a Dart pub workspace. One resolution, one lockfile, and a dependency direction the package
boundaries enforce: `net ← api ← (db, sync) ← player ← app`.

| Package | What lives there |
|---|---|
| `packages/chordia_net` | The pinned `HttpClient` factory and certificate fingerprints. The only place a socket is opened. |
| `packages/chordia_api` | Hub and library clients, the capability-grant cache, error mapping. |
| `packages/chordia_db` | drift schema: durable scrobble queue, download index, hub registry, response cache. |
| `packages/chordia_sync` | The cross-device player mesh, ported wire-exact from the web client, plus shared playback types. |
| `packages/chordia_player` | Playback engine, queue, crossfade, adaptive quality, and the media session behind the notification and lock screen. |
| `app` | The Flutter application: screens, routing, theme, localisation. |

The first four are pure Dart, so their tests — pinning, protocol, queue semantics, the scrobble
latch — run on the VM without an emulator.

## Running it

```bash
flutter pub get
flutter run --flavor dev -t app/lib/main_dev.dart --dart-define-from-file=env/dev.json
```

`dev` and `prod` install side by side (`fm.chordia.mobile.dev` and `fm.chordia.mobile`). The dev
flavour points at `10.0.2.2:8080`, which is how an Android emulator reaches a Hub running on the
host. Point it somewhere else by editing `env/dev.json`.

## Gates

```bash
flutter analyze
flutter test                      # app widget + integration tests
dart test                         # inside any packages/* directory
dart tool/sync_i18n.dart --check  # locale assets match the shared catalogs
```

## Localisation

Strings come from the shared [`i18n`](https://github.com/chordia-fm/i18n) repo, the same catalogs
the web client uses, so the two clients say the same things. `dart tool/sync_i18n.dart` copies them
into `app/assets/i18n` (one bundle per locale) and generates `app/lib/i18n/keys.g.dart`, which turns
every key into a constant — a string deleted or renamed upstream becomes a compile error rather than
a raw key rendered to a user. Check out the `i18n` repo beside this one, or pass `--source`.

Regional catalogs carry only their overrides; lookup falls through to the base language and then to
`en`, which is the complete source.

## Platform projects

`app/android` and `app/ios` are committed, not generated on demand. They carry real configuration —
the media-playback foreground service, the media browser service for Android Auto, the deep-link
scheme for browser sign-in, the loopback cleartext exemption the audio proxy needs — none of which
survives a `flutter create`.
