import 'dart:ui' show Color;

import 'package:chordia_api/chordia_api.dart';

import '../../../i18n/keys.g.dart';

/// A bound `ref.t`, so the pure helpers here can localise without a `WidgetRef`.
typedef Translate = String Function(String key, [Map<String, Object?> args]);

/// Longest overlap the contract allows between two tracks, in seconds.
///
/// `chordia_contracts::user::UserSettings::crossfade_seconds` documents `0..=12` and is clamped
/// **client-side** — the Hub stores whatever it is sent. That makes the clamp part of the write
/// path rather than a nicety of the slider: a value that only the slider bounds is one that any
/// other caller, or a settings blob written by an older build, can put out of range.
const maxCrossfadeSeconds = 12;

/// Most upcoming tracks the app will prefetch.
///
/// The contract says "clamped client-side" without naming a number, so this one is ours: five is
/// where the web client's control stops, and each slot is a whole track held in the stream cache.
const maxPreloadCount = 5;

/// Seconds of crossfade, brought inside the contract's range. `0` is off.
int clampCrossfadeSeconds(int seconds) =>
    seconds.clamp(0, maxCrossfadeSeconds).toInt();

/// Tracks to prefetch, brought inside the supported range. `0` disables prefetch.
int clampPreloadCount(int count) => count.clamp(0, maxPreloadCount).toInt();

/// The quality tiers, best first, each with the label and the sentence the picker shows.
const qualityTiers = <(QualityProfile, String, String)>[
  (
    QualityProfile.original,
    SettingsKeys.playbackQualityOriginalLabel,
    SettingsKeys.playbackQualityOriginalDesc,
  ),
  (
    QualityProfile.high,
    SettingsKeys.playbackQualityHighLabel,
    SettingsKeys.playbackQualityHighDesc,
  ),
  (
    QualityProfile.normal,
    SettingsKeys.playbackQualityNormalLabel,
    SettingsKeys.playbackQualityNormalDesc,
  ),
  (
    QualityProfile.dataSaver,
    SettingsKeys.playbackQualityDataSaverLabel,
    SettingsKeys.playbackQualityDataSaverDesc,
  ),
];

/// Who a visibility choice can be opened to, widest last.
///
/// Ordered narrow-to-wide so a picker reads as a dial that only ever loosens as it moves down,
/// which is the mental model these settings need to support.
const audienceChoices = <(Audience, String)>[
  (Audience.private, SettingsKeys.privacyVisibilityPrivate),
  (Audience.friends, SettingsKeys.privacyVisibilityFriends),
  (Audience.followers, SettingsKeys.privacyVisibilityFollowers),
  (Audience.public, SettingsKeys.privacyVisibilityPublic),
];

/// Who may see listening activity. Its own enum on the wire, so its own list.
const scrobblePrivacyChoices = <(ScrobblePrivacy, String)>[
  (ScrobblePrivacy.private, SettingsKeys.privacyVisibilityPrivate),
  (ScrobblePrivacy.friends, SettingsKeys.privacyVisibilityFriends),
  (ScrobblePrivacy.public, SettingsKeys.privacyVisibilityPublic),
];

/// How a non-static accent behaves over time, with the sentence describing each.
const accentModes = <(AccentMode, String, String)>[
  (
    AccentMode.staticValue,
    SettingsKeys.appearanceModeStatic,
    SettingsKeys.appearanceModeStaticHint,
  ),
  (
    AccentMode.fade,
    SettingsKeys.appearanceModeFade,
    SettingsKeys.appearanceModeFadeHint,
  ),
  (
    AccentMode.gradient,
    SettingsKeys.appearanceModeGradient,
    SettingsKeys.appearanceModeGradientHint,
  ),
  (
    AccentMode.artwork,
    SettingsKeys.appearanceModeArtwork,
    SettingsKeys.appearanceModeArtworkHint,
  ),
  (
    AccentMode.chroma,
    SettingsKeys.appearanceModeChroma,
    SettingsKeys.appearanceModeChromaHint,
  ),
];

const accentSpeeds = <(AccentSpeed, String)>[
  (AccentSpeed.relaxed, SettingsKeys.appearanceSpeedRelaxed),
  (AccentSpeed.steady, SettingsKeys.appearanceSpeedSteady),
  (AccentSpeed.brisk, SettingsKeys.appearanceSpeedBrisk),
];

/// The value `accent` takes when the listener has chosen no colour of their own.
///
/// Not a colour: it means "follow whatever this deployment's operator picked", so it keeps
/// tracking that choice if the operator changes it.
const followInstanceAccent = 'default';

/// An accent preset: the name stored in `UserSettings.accent`, its swatch, and its label.
typedef AccentPreset = (String name, Color swatch, String labelKey);

/// The presets, hue-ordered, mirroring `frontend/src/lib/settings/store.ts`.
///
/// The web authors these in OKLCH; these are the sRGB values those resolve to, the same
/// translation `app/theme.dart` already makes for the palette. `pink` is the built-in default and
/// is byte-identical to `ChordiaColors.accent` — if that stops being true, one of the two moved.
///
/// **Append-only, and a name may only change its colour, never its spelling.** An unrecognised
/// `accent` is used verbatim as a CSS colour by the web client, and `pink`/`blue`/`green`/`purple`
/// are all real CSS colour names — so renaming one silently repaints those accounts rather than
/// falling back to the default.
const accentPresets = <AccentPreset>[
  (
    followInstanceAccent,
    Color(0xFFCD00AE),
    SettingsKeys.appearanceAccentsDefault,
  ),
  ('crimson', Color(0xFFF52E44), SettingsKeys.appearanceAccentsCrimson),
  ('ember', Color(0xFFFB6C2B), SettingsKeys.appearanceAccentsEmber),
  ('amber', Color(0xFFE6AD00), SettingsKeys.appearanceAccentsAmber),
  ('lime', Color(0xFF9AD335), SettingsKeys.appearanceAccentsLime),
  ('green', Color(0xFF00C66D), SettingsKeys.appearanceAccentsGreen),
  ('teal', Color(0xFF00C2A5), SettingsKeys.appearanceAccentsTeal),
  ('blue', Color(0xFF00B5F5), SettingsKeys.appearanceAccentsBlue),
  ('indigo', Color(0xFF5E61FF), SettingsKeys.appearanceAccentsIndigo),
  ('purple', Color(0xFF963BF9), SettingsKeys.appearanceAccentsPurple),
  ('magenta', Color(0xFFF147C6), SettingsKeys.appearanceAccentsMagenta),
  ('pink', Color(0xFFCD00AE), SettingsKeys.appearanceAccentsPink),
];

/// The swatch to paint for a stored accent value, or null when it is a colour this build does not
/// know — a `#rrggbb` from the web's custom picker, say, which the phone shows as chosen without
/// pretending to be able to name it.
Color? accentSwatch(String? accent) {
  for (final preset in accentPresets) {
    if (preset.$1 == accent) return preset.$2;
  }
  return null;
}

/// Where the app opens. `UserSettings.default_surface` is a free string on the wire; these are the
/// two values the Hub documents.
const defaultSurfaces = <(String, String)>[
  ('app', SettingsKeys.startupHome),
  ('library', SettingsKeys.startupLibrary),
];

/// Each language in its own language, mirroring `LOCALE_NAMES` in `i18n/index.ts`.
///
/// Not catalog strings: a picker has to read to somebody who cannot read the language the app is
/// currently in, so every entry is written in itself and none of them is ever translated. Curated
/// rather than derived, because a derived name turns `de-DE` into "Deutsch (Deutschland)", which
/// is not what a German speaker calls their language.
const localeNames = <String, String>{
  'en': 'English',
  'de-DE': 'Deutsch',
  'en-GB': 'English (UK)',
  'es-ES': 'Español',
  'fr-FR': 'Français',
  'ja-JP': '日本語',
  'ko-KR': '한국어',
  'pt-BR': 'Português (Brasil)',
  'en-x-pirate': 'Pirate Speak',
  'en-x-piglatin': 'Igpay Atinlay',
};

/// A language's name, falling back to the raw tag so a catalog that arrives from Crowdin before
/// anyone adds a name here still appears in the picker.
String localeName(String tag) => localeNames[tag] ?? tag;

/// The catalog key naming a plan capability.
///
/// A `switch` rather than a map so a capability added to the contract is a compile error here,
/// which is the only place that would otherwise silently print nothing beside a feature the user
/// is paying for.
String featureNameKey(Feature feature) => switch (feature) {
  Feature.customAccent => BillingKeys.featuresCustomAccentName,
  Feature.dynamicAccent => BillingKeys.featuresDynamicAccentName,
  Feature.nameAccent => BillingKeys.featuresNameAccentName,
  Feature.profileAccent => BillingKeys.featuresProfileAccentName,
  Feature.animatedAvatar => BillingKeys.featuresAnimatedAvatarName,
  Feature.smartPlaylists => BillingKeys.featuresSmartPlaylistsName,
  Feature.tasteMatchSummary => BillingKeys.featuresTasteMatchSummaryName,
  Feature.deepAnalytics => BillingKeys.featuresDeepAnalyticsName,
  Feature.csvExport => BillingKeys.featuresCsvExportName,
  Feature.scrobbleEditing => BillingKeys.featuresScrobbleEditingName,
  Feature.historyImport => SettingsKeys.importTitle,
};

/// A plan's marketing name. Proper nouns, so untranslated — exactly as `tierName` on the web.
String tierName(PlanTier tier) => switch (tier) {
  PlanTier.free => 'Free',
  PlanTier.sonic => 'Sonic',
  PlanTier.superSonic => 'Super-Sonic',
};

/// The status of an import job, as a sentence.
String importStatusLabel(ImportJobStatus status) => switch (status) {
  ImportJobStatus.pending => SettingsKeys.importStatusPending,
  ImportJobStatus.running => SettingsKeys.importStatusRunning,
  ImportJobStatus.done => SettingsKeys.importStatusDone,
  ImportJobStatus.failed => SettingsKeys.importStatusFailed,
};

/// The Hub's stable failure code for an import, localised. An unknown code falls back to the
/// generic message rather than printing a slug at somebody.
String importErrorKey(String? code) => switch (code) {
  'malformed' => SettingsKeys.importErrorsMalformed,
  'unrecognized' => SettingsKeys.importErrorsUnrecognized,
  'interrupted' => SettingsKeys.importErrorsInterrupted,
  _ => SettingsKeys.importErrorsInternal,
};
