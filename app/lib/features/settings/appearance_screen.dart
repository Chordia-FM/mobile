import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../data/accent/accent_palette.dart' show parseHexColor;
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import 'data/settings_controller.dart';
import 'data/settings_patch.dart';
import 'data/settings_providers.dart';
import 'data/settings_values.dart';
import 'widgets/settings_list.dart';

/// The colour the account wears, and the language it is read in.
///
/// There is no light/dark choice here because there is no light theme: the app draws its own dark
/// palette and following the system into light would render half its surfaces unreadable. When one
/// exists it belongs at the top of this screen.
///
/// The accent is an account setting rather than a device one — it is what other people see on this
/// user's profile and beside their name — which is why it is saved to the Hub like everything else
/// on these screens.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final settings = ref.watch(settingsControllerProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.appearanceTitle),
      onRefresh: () => ref.read(settingsControllerProvider.notifier).reload(),
      children: [
        SettingsBody<UserSettings>(
          value: settings,
          onRetry: () => ref.invalidate(settingsControllerProvider),
          builder: (context, value) => _AppearanceControls(settings: value),
        ),
      ],
    );
  }
}

/// The palette a mode is seeded with when somebody switches into it having chosen nothing.
///
/// The web's `PALETTE_SEED` (`components/settings/AppearanceSection.tsx:220`), value for value, so
/// an account that turns Fade on from a phone and then opens the browser is looking at the same two
/// colours. Deliberately far apart in hue: the seed before this one was violet-to-pink, adjacent
/// enough that the result looked like a flat colour, and the first thing anybody saw of the feature
/// was an apparently broken one.
const _paletteSeed = ['#7c5cff', '#22d3ee'];

/// Modes that READ the palette, so the editor only appears where it would do something.
const _paletteModes = {AccentMode.fade, AccentMode.gradient};

/// Modes that move on a timer, and are therefore the only ones a speed means anything for.
///
/// Gradient and Artwork both change colour — one across space, one per track — but neither ticks,
/// so offering them a speed would be a control that does nothing.
const _timedModes = {AccentMode.fade, AccentMode.chroma};

/// Entering a palette mode with nothing to travel between seeds it.
///
/// Without this, choosing Fade or Gradient wrote the mode and left `accent_palette` empty. The
/// engine degrades a palette of fewer than two stops back to the static accent, so the colour did
/// not move and the mode read as broken rather than as unconfigured — and the palette editor that
/// appeared underneath was empty, which says "there is nothing here" rather than "pick something".
/// The web seeds at the same moment, for the same reason (`AppearanceSection.tsx:280-284`).
SettingsPatch accentModeChange(AccentMode picked, List<String> palette) =>
    _paletteModes.contains(picked) && palette.length < 2
    ? SettingsPatch(accentMode: picked, accentPalette: _paletteSeed)
    : SettingsPatch(accentMode: picked);

class _AppearanceControls extends ConsumerWidget {
  const _AppearanceControls({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final entitlements = ref.watch(myProfileProvider).value?.entitlements;
    final features = entitlements?.features ?? const <Feature>[];
    // A Hub with no payment provider unlocks everything, and its users must never meet a lock.
    final unmetered = entitlements?.billingEnabled == false;
    bool has(Feature feature) => unmetered || features.contains(feature);

    final mode = settings.accentMode ?? AccentMode.staticValue;
    final palette = settings.accentPalette ?? const <String>[];

    Future<void> write(SettingsPatch change) =>
        applySettingsPatch(context, ref, change);

    return Column(
      children: [
        SettingsSection(
          title: t(SettingsKeys.appearanceAccentColour),
          description: t(SettingsKeys.appearanceAccentProfileHint),
          children: [
            _AccentSwatches(
              selected: settings.accent ?? followInstanceAccent,
              onPicked: (accent) => write(SettingsPatch(accent: accent)),
            ),
          ],
        ),
        SettingsSection(
          title: t(SettingsKeys.appearanceModeTitle),
          description: t(SettingsKeys.appearanceModeHint),
          children: [
            SettingsRadioGroup<AccentMode>(
              value: mode,
              options: [
                for (final option in accentModes)
                  (option.$1, t(option.$2), t(option.$3)),
              ],
              // Every mode but Steady is a paid capability. The Hub serves `static` to an account
              // that has lost it rather than rewriting the stored choice, so the whole control is
              // locked rather than individual rows: an unentitled account has one legal value.
              onChanged: has(Feature.dynamicAccent)
                  ? (picked) => write(accentModeChange(picked, palette))
                  : null,
            ),
            if (!has(Feature.dynamicAccent))
              SettingsNote(t(BillingKeys.featuresDynamicAccentLocked)),
            // Each control appears only under the modes it changes something for, which is the
            // web's split (`PALETTE_MODES` / `TIMED_MODES`). Showing both under every dynamic mode
            // put a speed on Gradient, which does not tick, and a palette on Artwork and Chroma,
            // which do not read one.
            if (_timedModes.contains(mode))
              SettingsChoiceRow<AccentSpeed>(
                label: t(SettingsKeys.appearanceSpeedTitle),
                description: t(SettingsKeys.appearanceSpeedHint),
                value: settings.accentSpeed ?? AccentSpeed.relaxed,
                options: [
                  for (final speed in accentSpeeds) (speed.$1, t(speed.$2)),
                ],
                onChanged: (speed) => write(SettingsPatch(accentSpeed: speed)),
              ),
            if (_paletteModes.contains(mode))
              _PaletteEditor(
                palette: palette,
                onChanged: (stops) =>
                    write(SettingsPatch(accentPalette: stops)),
              ),
          ],
        ),
        SettingsSection(
          title: t(SettingsKeys.profileTitle),
          children: [
            SettingsSwitchRow(
              label: t(SettingsKeys.appearanceNameAccent),
              description: t(SettingsKeys.appearanceNameAccentHint),
              value: settings.nameAccent ?? true,
              onChanged: has(Feature.nameAccent)
                  ? (on) => write(SettingsPatch(nameAccent: on))
                  : null,
            ),
            if (!has(Feature.nameAccent))
              SettingsNote(t(BillingKeys.featuresNameAccentLocked)),
            SettingsSwitchRow(
              label: t(SettingsKeys.appearanceShowProfileAccents),
              description: t(SettingsKeys.appearanceShowProfileAccentsHint),
              value: settings.showProfileAccents ?? true,
              onChanged: (on) => write(SettingsPatch(showProfileAccents: on)),
            ),
          ],
        ),
        _LanguageSection(locale: settings.locale ?? ''),
        SettingsSection(
          title: t(SettingsKeys.startupTitle),
          description: t(SettingsKeys.startupDesc),
          children: [
            SettingsChoiceRow<String>(
              label: t(SettingsKeys.startupTitle),
              value: settings.defaultSurface ?? 'app',
              options: [
                for (final surface in defaultSurfaces)
                  (surface.$1, t(surface.$2)),
              ],
              onChanged: (surface) =>
                  write(SettingsPatch(defaultSurface: surface)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The preset colours, all of them at once.
///
/// A row of swatches rather than a picker sheet: there are twelve, they are the whole point, and a
/// colour you have to open something to see is one nobody browses.
class _AccentSwatches extends ConsumerWidget {
  const _AccentSwatches({required this.selected, required this.onPicked});

  final String selected;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final preset in accentPresets)
            Semantics(
              label: t(preset.$3),
              selected: preset.$1 == selected,
              button: true,
              child: Tooltip(
                message: t(preset.$3),
                child: InkWell(
                  onTap: () => onPicked(preset.$1),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: preset.$2,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: preset.$1 == selected
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    // The default follows the operator's colour rather than naming one, so it is
                    // marked instead of being a twelfth indistinguishable circle.
                    child: preset.$1 == followInstanceAccent
                        ? const Icon(
                            PhosphorIconsBold.house,
                            size: 18,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The two-to-six colours a moving accent travels between.
class _PaletteEditor extends ConsumerWidget {
  const _PaletteEditor({required this.palette, required this.onChanged});

  final List<String> palette;
  final ValueChanged<List<String>> onChanged;

  /// The contract's bounds. Below two there is nothing to move between; above six the steps are
  /// too small to tell apart on a phone-sized surface.
  static const _minStops = 2;
  static const _maxStops = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(SettingsKeys.appearancePalette),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          Text(
            t(SettingsKeys.appearancePaletteHint),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var index = 0; index < palette.length; index++)
                _Stop(
                  // A stop is a preset name when this phone wrote it and a `#rrggbb` when the web
                  // or the seed did, and both have to draw: the seed IS hex, so resolving names
                  // alone would open the editor on two unreadable circles.
                  colour:
                      accentSwatch(palette[index]) ??
                      parseHexColor(palette[index]),
                  label: t(SettingsKeys.appearancePaletteStopAria, {
                    'index': index + 1,
                  }),
                  onRemove: palette.length > _minStops
                      ? () => onChanged([
                          for (var i = 0; i < palette.length; i++)
                            if (i != index) palette[i],
                        ])
                      : null,
                  onTap: () => _pick(
                    context,
                    ref,
                    (accent) => onChanged([
                      for (var i = 0; i < palette.length; i++)
                        if (i == index) accent else palette[i],
                    ]),
                  ),
                ),
              if (palette.length < _maxStops)
                OutlinedButton.icon(
                  onPressed: () => _pick(
                    context,
                    ref,
                    (accent) => onChanged([...palette, accent]),
                  ),
                  icon: const Icon(PhosphorIconsRegular.plus),
                  label: Text(t(SettingsKeys.appearancePaletteAdd)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    ValueChanged<String> onPicked,
  ) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: _AccentSwatches(
          selected: '',
          onPicked: (accent) => Navigator.of(sheetContext).pop(accent),
        ),
      ),
    );
    // The instance-following default is not a colour, so it cannot be a stop in a gradient.
    if (chosen != null && chosen != followInstanceAccent) onPicked(chosen);
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    required this.colour,
    required this.label,
    required this.onTap,
    required this.onRemove,
  });

  /// Null for a colour this build cannot name — a `#rrggbb` set from the web's custom picker.
  final Color? colour;

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colour ?? theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: colour == null
                  ? const Icon(PhosphorIconsRegular.question, size: 18)
                  : null,
            ),
          ),
          if (onRemove != null)
            Positioned(
              right: -6,
              top: -6,
              child: IconButton.filledTonal(
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: onRemove,
                icon: const Icon(PhosphorIconsRegular.x),
              ),
            ),
        ],
      ),
    );
  }
}

class _LanguageSection extends ConsumerWidget {
  const _LanguageSection({required this.locale});

  /// The saved choice. Empty means "follow whatever language the request arrives in", which is
  /// what a new account has.
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final available = ref.watch(availableLocalesProvider).value;
    return SettingsSection(
      title: t(CommonKeys.languageLabel),
      description: t(SettingsKeys.appearanceLanguageHint),
      children: [
        SettingsChoiceRow<String>(
          label: t(CommonKeys.languageLabel),
          description: t(CommonKeys.languageDescription),
          value: locale.isEmpty
              ? ref.watch(translationsProvider).locale
              : locale,
          options: [
            for (final tag in available ?? const <String>[])
              (tag, localeName(tag)),
          ],
          // Disabled until the manifest is read: a picker with no options is a row that opens an
          // empty sheet.
          onChanged: available == null
              ? null
              : (tag) => applySettingsPatch(
                  context,
                  ref,
                  SettingsPatch(locale: tag),
                ),
        ),
      ],
    );
  }
}
