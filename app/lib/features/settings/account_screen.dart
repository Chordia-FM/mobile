import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../app/providers.dart';
import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/tokens.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import '../social/widgets/user_identity.dart';
import 'data/image_picking.dart';
import 'data/settings_api.dart';
import 'data/settings_messages.dart';
import 'data/settings_providers.dart';
import 'security_screen.dart';
import 'settings_screen.dart';
import 'widgets/settings_list.dart';

/// Who the account is, how it is reached, and how it ends.
///
/// Profile and email are edits with a server round trip and a confirmation step; the two at the
/// bottom leave the app entirely. They share a screen because they are the same question — "this
/// account" — but the destructive pair is kept in its own section so neither can be reached by a
/// mis-tap on a field above it.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final profile = ref.watch(myProfileProvider);
    final account = ref.watch(accountInfoProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.accountTitle),
      onRefresh: () async {
        ref
          ..invalidate(myProfileProvider)
          ..invalidate(accountInfoProvider);
        final handle = profile.value?.handle;
        if (handle != null) ref.invalidate(myPublicProfileProvider(handle));
      },
      children: [
        SettingsBody<UserProfile>(
          value: profile,
          onRetry: () => ref.invalidate(myProfileProvider),
          builder: (context, value) => _ProfileFields(profile: value),
        ),
        SettingsBody<AccountInfo>(
          value: account,
          onRetry: () => ref.invalidate(accountInfoProvider),
          builder: (context, value) => _EmailSection(account: value),
        ),
        SettingsSection(
          title: t(SettingsKeys.securityTitle),
          children: [
            SettingsDisclosureRow(
              icon: PhosphorIconsRegular.lock,
              label: t(SettingsKeys.securityPasswordTitle),
              description: t(SettingsKeys.sectionsSecurity),
              onTap: () => openSettingsScreen(context, const SecurityScreen()),
            ),
          ],
        ),
        _DangerSection(handle: profile.value?.handle),
      ],
    );
  }
}

/// The identity read, joined to the public read that carries the rest of the profile.
///
/// Two endpoints, one editor. `/v1/me` has no bio, banner or links at all, so the account's own
/// **public** profile is the only place those can be read from — and it is a second request, which
/// lands later. The name and handle are editable the whole time regardless: a public read that
/// fails (or a Hub still answering) must not take the fields above it down with it.
class _ProfileFields extends ConsumerWidget {
  const _ProfileFields({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final public = ref.watch(myPublicProfileProvider(profile.handle)).value;
    return _ProfileSection(
      // Keyed by what the fields are seeded FROM, so a refresh that brings back an edit made on
      // another device re-seeds them instead of leaving stale text in place — and so the bio and
      // link editors seed themselves the moment the public read lands. The avatar and banner are
      // deliberately absent: those apply on their own, and rebuilding for one would throw away a
      // bio somebody was halfway through typing.
      key: ValueKey(
        '${profile.id}:${profile.handle}:${profile.displayName}:'
        '${public == null ? '' : 'p'}${public?.bio ?? ''}:'
        '${(public?.links ?? const <ProfileLink>[]).map((l) => '${l.kind}=${l.url}').join(',')}',
      ),
      profile: profile,
      public: public,
    );
  }
}

/// The bio cap, in CHARACTERS — mirrors `MAX_BIO_CHARS` in backend/src/api/v1/users.rs.
const _maxBioChars = 500;

/// The link cap — mirrors `MAX_LINKS`. One URL per platform is already forced by the
/// `(user_id, kind)` primary key.
const _maxLinks = 8;

/// The 14 platforms a profile link may point at.
///
/// The SLUGS are the contract: they must stay identical to `LINK_KINDS` in
/// backend/src/api/v1/users.rs, which rejects anything else. The labels are brand names, which are
/// never translated — there is nothing here for the catalogs to hold.
const _linkKinds = <(String, String)>[
  ('website', 'Website'),
  ('spotify', 'Spotify'),
  ('apple_music', 'Apple Music'),
  ('youtube_music', 'YouTube Music'),
  ('youtube', 'YouTube'),
  ('soundcloud', 'SoundCloud'),
  ('bandcamp', 'Bandcamp'),
  ('tidal', 'Tidal'),
  ('deezer', 'Deezer'),
  ('instagram', 'Instagram'),
  ('twitter', 'X'),
  ('tiktok', 'TikTok'),
  ('facebook', 'Facebook'),
  ('wikipedia', 'Wikipedia'),
];

/// The server's link rule, restated on the client: `https://` and a host.
///
/// Not belt-and-braces. Bio, name, handle and links all ride in ONE `PATCH /v1/me`, so a single
/// malformed row fails the whole save and loses the rest of the edit. Marking the row and holding
/// Save says which field is wrong; a snack bar after the fact does not.
bool validLinkUrl(String url) {
  final parsed = Uri.tryParse(url.trim());
  return parsed != null && parsed.scheme == 'https' && parsed.host.isNotEmpty;
}

/// Everything a profile shows about its owner: photo, banner, name, handle, bio and links.
///
/// Two reads feed it. `UserProfile` — what `/v1/me` and `PATCH /v1/me` answer with — carries the
/// name, handle and avatar; it has no bio, banner or links at all, so those come from the account's
/// own **public** profile, which is the only endpoint that returns them.
///
/// The photo and the banner apply on their own, unlike every field below them: picking one is
/// already a deliberate, confirmed act with a visible result, and making it wait behind Save reads
/// as "nothing happened". Everything else is one PATCH, because the Hub takes one.
class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection({
    required this.profile,
    required this.public,
    super.key,
  });

  final UserProfile profile;

  /// The public half, or null while it is still loading or after it failed. Null hides the bio,
  /// banner and link editors rather than showing empty ones — an empty bio field over a bio the
  /// screen has not read yet is an offer to erase it.
  final PublicProfile? public;

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  late final _handle = TextEditingController(text: widget.profile.handle);
  late final _displayName = TextEditingController(
    text: widget.profile.displayName,
  );
  late final _bio = TextEditingController(text: widget.public?.bio ?? '');
  late List<ProfileLink> _links = [...?widget.public?.links];

  bool _busy = false;
  bool _photoBusy = false;
  bool _bannerBusy = false;

  @override
  void initState() {
    super.initState();
    // Save's enablement is a function of every field, so each keystroke has to reach it.
    for (final field in [_handle, _displayName, _bio]) {
      field.addListener(_onEdited);
    }
  }

  void _onEdited() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _handle.dispose();
    _displayName.dispose();
    _bio.dispose();
    super.dispose();
  }

  String get _serverBio => widget.public?.bio ?? '';

  List<ProfileLink> get _serverLinks => widget.public?.links ?? const [];

  bool get _linksDirty =>
      _links.length != _serverLinks.length ||
      _links.indexed.any(
        (e) =>
            e.$2.kind != _serverLinks[e.$1].kind ||
            e.$2.url != _serverLinks[e.$1].url,
      );

  bool get _canSave {
    final name = _displayName.text.trim();
    final handle = _handle.text.trim();
    final bioDirty = widget.public != null && _bio.text != _serverBio;
    final dirty =
        name != widget.profile.displayName ||
        handle != widget.profile.handle ||
        bioDirty ||
        _linksDirty;
    // Display name and handle are COALESCE-preserved server-side, so an empty one is not "clear
    // it" — it is a no-op the Hub still reports as success, leaving the field dirty forever and
    // Save repeating the lie on every tap. The bio has no such problem: "" is its documented
    // clear encoding.
    return dirty &&
        !_busy &&
        name.isNotEmpty &&
        handle.isNotEmpty &&
        _bio.text.runes.length <= _maxBioChars &&
        _links.every((link) => validLinkUrl(link.url));
  }

  /// Only the fields that actually moved are sent: `UpdateProfile` treats an omitted field as
  /// "leave it", and sending an unchanged handle makes the Hub run its uniqueness check — and fail
  /// it against the account's own current handle on some paths.
  Future<void> _save() async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    final handle = _handle.text.trim();
    final displayName = _displayName.text.trim();
    final changes = UpdateProfile(
      handle: handle == widget.profile.handle ? null : handle,
      displayName: displayName == widget.profile.displayName
          ? null
          : displayName,
      // Read back rather than trimmed away: "" is how the wire says "clear the bio", and only a
      // profile that has actually been read may claim to know what the bio currently is.
      bio: widget.public == null || _bio.text == _serverBio ? null : _bio.text,
      // Replace-all: an omitted `links` leaves the stored rows alone, `[]` deletes every one. Only
      // sent when changed, so saving a renamed display name can never drop somebody's links.
      links: _linksDirty
          ? [
              for (final link in _links)
                ProfileLink(kind: link.kind, url: link.url.trim()),
            ]
          : null,
    );
    if (changes.toJson().isEmpty) return;

    setState(() => _busy = true);
    final t = ref.read(translationsProvider).call;
    try {
      await api.updateProfile(changes);
      if (!mounted) return;
      _refresh(handle);
      showSettingsMessage(context, t(CommonKeys.statusSaved));
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Re-reads both halves after a write. The handle may have just changed, so the public read is
  /// invalidated under both keys — the old one to drop it, the new one because that is the family
  /// member the rebuilt screen will ask for.
  void _refresh(String handle) {
    ref
      ..invalidate(myProfileProvider)
      ..invalidate(myPublicProfileProvider(widget.profile.handle))
      ..invalidate(myPublicProfileProvider(handle));
  }

  /// Whether this account may keep an avatar that moves.
  ///
  /// A missing `entitlements` block is a Hub older than the field, and `billingEnabled == false`
  /// is a Hub with no payment provider at all — both unlock everything, so neither may produce a
  /// lock (`Entitlements.billingEnabled`).
  bool get _canAnimate {
    final entitlements = widget.profile.entitlements;
    if (entitlements == null || entitlements.billingEnabled == false) {
      return true;
    }
    return entitlements.features?.contains(Feature.animatedAvatar) ?? false;
  }

  /// Picks an image, uploads it, and points the named field at the hash that comes back.
  ///
  /// [apply] receives the hash because the two fields spell it differently: a banner takes the
  /// bare hash and an avatar takes the `/v1/images/{hash}` path it resolves to. Sending the wrong
  /// one is a silent no-op server-side, which is exactly the failure a caller cannot see.
  Future<void> _pickAndApply({
    required int maxWidth,
    required UpdateProfile Function(String hash) apply,
    required void Function(bool busy) setBusy,
    bool allowAnimated = false,
  }) async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    final PickedImage? picked;
    try {
      picked = await ref.read(imagePickerProvider)(
        maxWidth: maxWidth,
        allowAnimated: allowAnimated,
      );
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => setBusy(true));
    try {
      final hash = await api.uploadImage(
        picked.bytes,
        contentType: picked.contentType,
      );
      await api.updateProfile(apply(hash));
      if (!mounted) return;
      _refresh(widget.profile.handle);
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => setBusy(false));
    }
  }

  /// Clears one image. `""` is the wire encoding for "none" — omitting the field
  /// COALESCE-preserves what is stored, so there is no other way to say it.
  Future<void> _clear({
    required UpdateProfile changes,
    required void Function(bool busy) setBusy,
  }) async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    setState(() => setBusy(true));
    try {
      await api.updateProfile(changes);
      if (!mounted) return;
      _refresh(widget.profile.handle);
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => setBusy(false));
    }
  }

  void _addLink() {
    // The first platform not already taken, so the new row is valid the instant it appears —
    // `(user_id, kind)` is a primary key and a duplicate would silently overwrite.
    final used = _links.map((link) => link.kind).toSet();
    final next = _linkKinds
        .where((kind) => !used.contains(kind.$1))
        .map((kind) => kind.$1)
        .firstOrNull;
    if (next == null) return;
    setState(() => _links = [..._links, ProfileLink(kind: next, url: '')]);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final public = widget.public;
    return SettingsSection(
      title: t(SettingsKeys.profileTitle),
      description: t(SettingsKeys.profileDesc),
      children: [
        _PhotoRow(
          avatarUrl: widget.profile.avatarUrl,
          displayName: widget.profile.displayName,
          busy: _photoBusy,
          onChange: () => _pickAndApply(
            maxWidth: 512,
            // The animated-avatar entitlement, honoured on the way IN rather than trusted after
            // the fact: the picker's own resize flattens a GIF to its first frame before the
            // bytes ever reach Dart, so a subscriber's animated avatar was being destroyed on
            // this device no matter what the Hub was willing to store. The server enforces the
            // entitlement either way — a wrong answer here costs a needless re-encode, never a
            // bypass. A Hub with no payment provider unlocks everything.
            allowAnimated: _canAnimate,
            apply: (hash) => UpdateProfile(avatarUrl: '/v1/images/$hash'),
            setBusy: (busy) => _photoBusy = busy,
          ),
          onRemove: widget.profile.avatarUrl == null
              ? null
              : () => _clear(
                  changes: const UpdateProfile(avatarUrl: ''),
                  setBusy: (busy) => _photoBusy = busy,
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _displayName,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: t(SettingsKeys.accountDisplayName),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _handle,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _canSave ? _save() : null,
                decoration: InputDecoration(
                  labelText: t(SettingsKeys.accountHandle),
                  hintText: t(SettingsKeys.accountHandlePlaceholder),
                  helperText: t(SettingsKeys.accountHandleHint),
                  helperMaxLines: 2,
                  prefixText: '@',
                ),
              ),
              if (public != null) ...[
                const SizedBox(height: 16),
                _BioField(controller: _bio, enabled: !_busy),
              ],
            ],
          ),
        ),
        if (public != null) ...[
          _BannerRow(
            bannerUrl: public.bannerUrl,
            busy: _bannerBusy,
            onChange: () => _pickAndApply(
              // A banner is 3:1, so it is downscaled rather than square-cropped: cropping to a
              // square throws away the sides, which on a banner are the picture.
              maxWidth: 1600,
              apply: (hash) => UpdateProfile(bannerHash: hash),
              setBusy: (busy) => _bannerBusy = busy,
            ),
            onRemove: public.bannerUrl == null
                ? null
                : () => _clear(
                    changes: const UpdateProfile(bannerHash: ''),
                    setBusy: (busy) => _bannerBusy = busy,
                  ),
          ),
          _LinksEditor(
            links: _links,
            enabled: !_busy,
            onChanged: (links) => setState(() => _links = links),
            onAdd: _links.length >= _maxLinks ? null : _addLink,
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _canSave ? _save : null,
            child: Text(
              t(
                _busy
                    ? CommonKeys.statesSaving
                    : SettingsKeys.accountSaveProfile,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The account photo, beside the two things that can be done to it.
class _PhotoRow extends ConsumerWidget {
  const _PhotoRow({
    required this.avatarUrl,
    required this.displayName,
    required this.busy,
    required this.onChange,
    this.onRemove,
  });

  final String? avatarUrl;
  final String displayName;
  final bool busy;
  final VoidCallback onChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          UserAvatar(
            user: PublicUser(
              displayName: displayName,
              handle: '',
              id: '',
              avatarUrl: avatarUrl,
            ),
            size: 72,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : onChange,
                  child: Text(t(SettingsKeys.accountChangePhoto)),
                ),
                if (onRemove != null)
                  TextButton(
                    onPressed: busy ? null : onRemove,
                    child: Text(t(SettingsKeys.accountRemovePhoto)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bio, and the only warning of its limit.
///
/// The counter has to be visible **before** Save: the Hub rejects the whole PATCH — bio, name,
/// handle and links together — so a bio one character over loses the rest of the edit with it.
class _BioField extends ConsumerWidget {
  const _BioField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    // Code points, not UTF-16 units: the Hub counts Rust `chars()`, so `length` would call a bio
    // of 480 emoji over the limit and refuse a save the Hub would have accepted.
    final used = controller.text.runes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: 4,
          minLines: 2,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: t(SettingsKeys.profileBio),
            hintText: t(SettingsKeys.profileBioPlaceholder),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t(SettingsKeys.profileBioCounter, {'count': used}),
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            color: used > _maxBioChars
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The banner, previewed at the aspect the profile header uses so what is framed here is what
/// lands there.
class _BannerRow extends ConsumerWidget {
  const _BannerRow({
    required this.bannerUrl,
    required this.busy,
    required this.onChange,
    this.onRemove,
  });

  final String? bannerUrl;
  final bool busy;
  final VoidCallback onChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final hash = artHashOf(bannerUrl);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(SettingsKeys.profileBanner),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 3,
            child: hash == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: ChordiaRadius.lgAll,
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                  )
                : CoverArt(
                    sha256: hash,
                    size: MediaQuery.sizeOf(context).width,
                    borderRadius: ChordiaRadius.lgAll,
                    fallbackIcon: PhosphorIconsRegular.image,
                  ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : onChange,
                child: Text(t(SettingsKeys.profileChooseBanner)),
              ),
              if (onRemove != null)
                TextButton(
                  onPressed: busy ? null : onRemove,
                  child: Text(t(SettingsKeys.profileRemoveBanner)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t(SettingsKeys.profileBannerHint),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Up to eight links, one per platform.
class _LinksEditor extends ConsumerWidget {
  const _LinksEditor({
    required this.links,
    required this.enabled,
    required this.onChanged,
    this.onAdd,
  });

  final List<ProfileLink> links;
  final bool enabled;
  final ValueChanged<List<ProfileLink>> onChanged;

  /// Null once the cap is reached, which is what disables Add.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    final used = links.map((link) => link.kind).toSet();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(SettingsKeys.profileLinks),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final (index, link) in links.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          // Keyed by the kind it currently holds: a form field reads its initial
                          // value once, so without this a platform change would redraw the old
                          // label over the new value.
                          key: ValueKey('link-kind-${link.kind}'),
                          initialValue: link.kind,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t(SettingsKeys.profileLinkKind),
                          ),
                          items: [
                            for (final (kind, label) in _linkKinds)
                              DropdownMenuItem(
                                value: kind,
                                enabled:
                                    kind == link.kind || !used.contains(kind),
                                child: Text(label),
                              ),
                          ],
                          onChanged: !enabled
                              ? null
                              : (kind) {
                                  if (kind == null) return;
                                  onChanged([
                                    for (final (i, l) in links.indexed)
                                      if (i == index)
                                        ProfileLink(kind: kind, url: l.url)
                                      else
                                        l,
                                  ]);
                                },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(PhosphorIconsRegular.trash),
                        tooltip: t(SettingsKeys.profileRemoveLink),
                        onPressed: !enabled
                            ? null
                            : () => onChanged([
                                for (final (i, l) in links.indexed)
                                  if (i != index) l,
                              ]),
                      ),
                    ],
                  ),
                  TextFormField(
                    key: ValueKey('link-url-${link.kind}'),
                    initialValue: link.url,
                    enabled: enabled,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: t(SettingsKeys.profileLinkUrl),
                      hintText: 'https://',
                      // Empty counts as invalid even though it says nothing: it is what holds
                      // Save, and holding Save without marking anything is the one shape this
                      // section's own rationale says to avoid.
                      errorText: validLinkUrl(link.url)
                          ? null
                          : t(SettingsKeys.profileLinksHint),
                    ),
                    onChanged: (url) => onChanged([
                      for (final (i, l) in links.indexed)
                        if (i == index)
                          ProfileLink(kind: l.kind, url: url)
                        else
                          l,
                    ]),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: enabled ? onAdd : null,
            icon: const Icon(PhosphorIconsRegular.plus),
            label: Text(t(SettingsKeys.profileAddLink)),
          ),
          const SizedBox(height: 4),
          Text(
            t(SettingsKeys.profileLinksHint),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailSection extends ConsumerStatefulWidget {
  const _EmailSection({required this.account});

  final AccountInfo account;

  @override
  ConsumerState<_EmailSection> createState() => _EmailSectionState();
}

class _EmailSectionState extends ConsumerState<_EmailSection> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(AccountApi api) call,
    String done,
  ) async {
    final api = ref.read(accountApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    final t = ref.read(translationsProvider).call;
    try {
      await call(api);
      if (!mounted) return;
      showSettingsMessage(context, t(done));
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The new address is asked for in a dialog rather than an inline field, because this is not an
  /// edit: nothing changes until the link sent to the new inbox is followed, and a field that
  /// looks like the other two on this screen implies it is.
  Future<void> _changeEmail() async {
    final t = ref.read(translationsProvider).call;
    final controller = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(SettingsKeys.accountChangeEmailTitle)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(SettingsKeys.accountChangeEmailBody)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t(AuthKeys.fieldsEmail),
                hintText: t(SettingsKeys.accountNewEmailPlaceholder),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(t(SettingsKeys.accountSendConfirmation)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (address == null || address.isEmpty) return;
    await _run(
      (api) => api.requestEmailChange(address),
      SettingsKeys.accountEmailChangeSent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final account = widget.account;
    final verified = account.emailVerified;
    return SettingsSection(
      title: t(SettingsKeys.accountEmailTitle),
      children: [
        ListRow(
          gutter: 0,
          title: Text(account.email ?? t(SettingsKeys.accountNoEmail)),
          subtitle: Text(
            t(
              verified
                  ? SettingsKeys.accountVerified
                  : SettingsKeys.accountUnverified,
            ),
          ),
          trailing: Icon(
            verified
                ? PhosphorIconsFill.checkCircle
                : PhosphorIconsRegular.warningCircle,
            color: verified
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
        ),
        if (!verified)
          SettingsDisclosureRow(
            label: t(SettingsKeys.accountResendVerification),
            onTap: _busy
                ? null
                : () => _run(
                    (api) => api.requestEmailVerification(),
                    SettingsKeys.accountVerificationSent,
                  ),
          ),
        SettingsDisclosureRow(
          label: t(SettingsKeys.accountChangeEmail),
          onTap: _busy ? null : _changeEmail,
        ),
      ],
    );
  }
}

class _DangerSection extends ConsumerWidget {
  const _DangerSection({required this.handle});

  /// Null while the profile is still loading, which is also what keeps the delete row unreachable
  /// until there is a handle to type into the confirmation.
  final String? handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final hub = ref.watch(activeHubProvider);
    return SettingsSection(
      title: t(SettingsKeys.accountLeaveTitle),
      description: t(SettingsKeys.accountLeaveDesc),
      children: [
        SettingsDisclosureRow(
          icon: PhosphorIconsRegular.signOut,
          label: t(CommonKeys.actionsSignOut),
          onTap: () => _signOut(context, ref, hub?.name ?? ''),
        ),
        SettingsDisclosureRow(
          icon: PhosphorIconsRegular.trash,
          label: t(SettingsKeys.dataDeleteAccountTitle),
          destructive: true,
          onTap: handle == null
              ? null
              : () => _deleteAccount(context, ref, handle!),
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref, String hub) async {
    final t = ref.read(translationsProvider).call;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t(CommonKeys.actionsSignOut)),
        content: Text(t(SettingsKeys.accountSignOutConfirm, {'hub': hub})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t(CommonKeys.actionsCancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t(CommonKeys.actionsSignOut)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The router's redirect is what leaves this screen: it watches sign-in state, so nothing here
    // has to navigate — and nothing here can, since this screen is about to stop existing.
    await ref.read(authControllerProvider.notifier).signOut();
  }

  /// Deleting is irreversible and the Hub asks nothing further, so the confirmation is entirely
  /// this client's job. Typing the handle is the point: a destructive button behind a second
  /// button is still one mis-tap away, and this is the one action in the app that cannot be undone
  /// by any means at all.
  Future<void> _deleteAccount(
    BuildContext context,
    WidgetRef ref,
    String handle,
  ) async {
    final t = ref.read(translationsProvider).call;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DeleteAccountDialog(handle: handle),
    );
    if (confirmed != true) return;

    final api = ref.read(accountApiProvider);
    if (api == null) return;
    try {
      await api.deleteAccount();
    } on Object catch (error) {
      if (!context.mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
      return;
    }
    // The account is gone, so the session that was signing into it is worthless. Signing out
    // locally is what puts the app back on its sign-in screen.
    await ref.read(authControllerProvider.notifier).signOut();
  }
}

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog({required this.handle});

  final String handle;

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final matches = _typed.text.trim() == widget.handle;
    return AlertDialog(
      title: Text(t(SettingsKeys.dataDeleteAccountTitle)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t(SettingsKeys.dataDeleteAccountConfirm)),
          const SizedBox(height: 16),
          TextField(
            controller: _typed,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: t(SettingsKeys.accountDeleteTypeHandle, {
                'handle': widget.handle,
              }),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t(CommonKeys.actionsCancel)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(t(SettingsKeys.dataDeleteForever)),
        ),
      ],
    );
  }
}
