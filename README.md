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
host, and its version name carries a `-dev` suffix. Point it somewhere else by editing
`env/dev.json`.

The prod flavour talks to the public Hub in `env/prod.json`:

```bash
flutter run --flavor prod -t app/lib/main_prod.dart --dart-define-from-file=env/prod.json
```

Build an installable APK by swapping `run` for `build apk --release`. Every flavour argument is
required every time — a `flutter run` with no `--dart-define-from-file` compiles fine and then has
no Hub to talk to.

## Gates

```bash
bash tool/test_all.sh             # every suite in the workspace, one line each
flutter analyze                   # must report no issues
dart format .                     # must leave nothing changed
dart tool/sync_i18n.dart --check  # locale assets match the shared catalogs
dart tool/gen_api.dart --check    # API models match the vendored OpenAPI schema
```

`tool/test_all.sh` is the quick way; the suites underneath it are `dart test` in each
`packages/*` and `flutter test` in `app`, and either can be run alone (`flutter test
test/update_test.dart`).

## Signing

Release builds need a keystore, and it is never in the repository. Copy
`app/android/key.properties.example` to `app/android/key.properties` and fill it in; that file and
`*.jks` are both gitignored. The example carries the `keytool` invocation that makes the keystore.

Without `key.properties`, a release build falls back to the debug key — enough to try a build on
your own phone, not enough for anything anyone else installs, because Android refuses to update an
app whose signing certificate has changed. With a `key.properties` that is present but incomplete,
the build fails rather than falling back; a silent fallback in CI would publish a debug-signed APK
and break every existing install's upgrade path.

CI builds from four repository secrets: `ANDROID_KEYSTORE_BASE64` (`base64 -w0 chordia-release.jks`),
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.

## Cutting a release

Tag it. The `release` job in `.github/workflows/ci.yml` runs on any `v*` tag, after the analyze,
test and drift gates have passed on that same commit:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

It builds a signed universal APK plus per-ABI builds for `arm64-v8a` and `armeabi-v7a`, writes
`SHA256SUMS` over them, and publishes the lot to a GitHub release with notes generated from the
commits since the previous tag. The version name comes from the tag, so `v0.2.0` produces an app
that reports `0.2.0`; a tag with a suffix (`v0.3.0-rc.1`) is marked as a pre-release and stays out
of `/releases/latest`.

Nothing in the repository needs its version bumped first — `pubspec.yaml`'s `version:` is the
development default, and the release build overrides both the name and the build number.

## Updates in the app

There is no Play Store listing, so the app checks for itself. On launch, and at most once a day, it
asks its Hub for `GET /v1/mobile/latest` — which republishes this repo's GitHub release, because
GitHub serves release assets with no CORS headers and the filenames carry the version. If the
release is newer than the running build, a sheet offers the release notes and the universal APK,
which downloads in the browser; Android then asks the user to confirm the install. The app does not
install it itself: that needs `REQUEST_INSTALL_PACKAGES`, which is a permission prompt nobody wants
to meet on first run.

A version that has been dismissed stays dismissed until a newer one exists. The comparison is
semantic-version precedence, so `0.2.0` is an update for somebody on `0.2.0-dev` and build metadata
never prompts anybody.

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
