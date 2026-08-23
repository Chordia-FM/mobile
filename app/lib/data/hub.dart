import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// One Chordia Hub this installation knows about.
///
/// [name], [frontendUrl] and [discordOauth] come from the Hub's own `GET /v1/instance`, captured
/// when it was added rather than asked for on every launch: the picker has to render before any
/// network call could answer, and a Hub that is temporarily down must still be selectable.
@immutable
class Hub {
  const Hub({
    required this.id,
    required this.url,
    required this.name,
    required this.addedAt,
    this.frontendUrl,
    this.discordOauth = false,
  });

  /// Builds an entry for a hub that has just been probed.
  factory Hub.discovered({
    required Uri url,
    required InstanceInfo info,
    required int addedAt,
  }) => Hub(
    id: idFor(url),
    url: url,
    name: info.name,
    addedAt: addedAt,
    frontendUrl: Uri.tryParse(info.frontendUrl),
    discordOauth: info.discordOauth,
  );

  /// A stable, opaque id for a hub, derived from its API origin.
  ///
  /// Derived rather than random for two reasons. Adding the same server twice has to land on the
  /// same entry, or the registry grows duplicates that each hold a separate session under a
  /// separate key. And the id is part of a keystore key: a raw URL there would put `://` and dots
  /// into a key whose legal character set varies by platform.
  static String idFor(Uri url) =>
      sha256.convert(utf8.encode(url.toString())).toString().substring(0, 16);

  final String id;

  /// The API base that actually answered — not always what the user typed. See `probeHub`.
  final Uri url;

  /// Operator-facing name. Self-hosters run several, and "Hub" three times is not a picker.
  final String name;

  /// Epoch **milliseconds**, like every other timestamp on this API.
  final int addedAt;

  /// The Hub's canonical web frontend, where the browser sign-in handoff is hosted. Null when the
  /// instance reported something unparseable.
  final Uri? frontendUrl;

  /// Whether "Continue with Discord" will work here. A button that leads to a 500 is worse than no
  /// button.
  final bool discordOauth;

  Map<String, Object?> toJson() => {
    'id': id,
    'url': url.toString(),
    'name': name,
    'added_at': addedAt,
    if (frontendUrl != null) 'frontend_url': frontendUrl.toString(),
    'discord_oauth': discordOauth,
  };

  /// Reads one entry, returning null for anything malformed.
  ///
  /// A single unreadable entry must not take the whole registry — and with it every other hub the
  /// user added — down with it.
  static Hub? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final url = json['url'];
    final name = json['name'];
    final addedAt = json['added_at'];
    if (id is! String || url is! String || name is! String) return null;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasAuthority) return null;
    final frontend = json['frontend_url'];
    return Hub(
      id: id,
      url: parsed,
      name: name,
      addedAt: addedAt is int ? addedAt : 0,
      frontendUrl: frontend is String ? Uri.tryParse(frontend) : null,
      discordOauth: json['discord_oauth'] == true,
    );
  }

  @override
  bool operator ==(Object other) => other is Hub && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The whole registry as one value: every hub, and which one the app is currently pointed at.
@immutable
class HubRegistrySnapshot {
  const HubRegistrySnapshot({required this.hubs, this.activeId});

  static const empty = HubRegistrySnapshot(hubs: []);

  final List<Hub> hubs;
  final String? activeId;

  /// The hub in use, or null when there is none — which is what a first launch looks like, and
  /// what the sign-in screen renders its "choose a server" state from.
  Hub? get active {
    for (final hub in hubs) {
      if (hub.id == activeId) return hub;
    }
    return null;
  }

  bool get isEmpty => hubs.isEmpty;
}
