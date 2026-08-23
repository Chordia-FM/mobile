/// The Hub's HTTP surface, as Dart methods.
///
/// Every group is an extension on `HubClient` rather than a client object of its own, so there is
/// still exactly one thing holding the base URL, the session and the TLS policy. Adding a screen
/// adds a method, not another object to wire up and keep in sync.
///
/// The split into files follows the OpenAPI tags, so a route in the served spec and the Dart method
/// that calls it are findable from each other. Method names are unique across the whole surface:
/// extensions on one type cannot disambiguate by receiver, so two groups declaring `search` would
/// make every call to it ambiguous.
///
/// **Not covered here**, and why:
///
/// * the `admin` tag — a later milestone;
/// * `POST /v1/directory/grant` — owned by `GrantManager`, which caches what it mints;
/// * `GET /v1/images/{sha256}` — not a fetch; `HubClient.imageUrl` builds the URL, snapped to the
///   width ladder the Hub actually derives;
/// * the routes a **library server** calls with its own API key rather than a user session:
///   `catalog/sync`, `catalog/prune`, `catalog/identify`, `directory/heartbeat`,
///   `scrobbles:ingest`, `libraries/pair`;
/// * `POST /v1/me/imports` — an `application/octet-stream` upload, which the JSON transport has no
///   way to send.
library;

export 'auth.dart';
export 'billing.dart';
export 'catalog.dart';
export 'desktop.dart';
export 'directory.dart';
export 'discovery.dart';
export 'imports.dart';
export 'insights.dart';
export 'libraries.dart';
export 'lyrics.dart';
export 'manager.dart';
export 'overrides.dart';
export 'pins.dart';
export 'playlists.dart';
export 'scrobbles.dart';
export 'smart.dart';
export 'social.dart';
export 'user.dart';
