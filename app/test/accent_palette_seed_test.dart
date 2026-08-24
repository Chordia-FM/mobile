import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/data/accent/accent_palette.dart'
    show parseHexColor;
import 'package:chordia_mobile/features/settings/appearance_screen.dart';
import 'package:chordia_mobile/features/settings/data/settings_values.dart'
    show accentSwatch;
import 'package:flutter_test/flutter_test.dart';

/// What entering a moving accent mode writes.
///
/// The bug this pins is a silent one: choosing Fade wrote the mode and nothing else, the engine
/// degrades a palette of under two stops back to the static accent, and so the colour did not
/// move. Nothing failed, nothing said anything, and the feature read as broken.
void main() {
  group('entering a palette mode', () {
    test('seeds a palette when there is nothing to travel between', () {
      final patch = accentModeChange(AccentMode.fade, const []);

      expect(patch.accentMode, AccentMode.fade);
      expect(
        patch.accentPalette,
        hasLength(greaterThanOrEqualTo(2)),
        reason: 'under two stops is what the engine refuses to animate',
      );
    });

    test('a single leftover stop is still not a palette', () {
      // One stop is the state a palette gets to by removal, and it fades exactly as badly as none.
      expect(
        accentModeChange(AccentMode.gradient, const ['teal']).accentPalette,
        isNotNull,
      );
    });

    test('leaves a palette the listener already chose alone', () {
      expect(
        accentModeChange(AccentMode.fade, const [
          'crimson',
          'blue',
        ]).accentPalette,
        isNull,
        reason: 'seeding over a real choice would overwrite it',
      );
    });

    test('a mode that does not read a palette never writes one', () {
      for (final mode in [
        AccentMode.staticValue,
        AccentMode.artwork,
        AccentMode.chroma,
      ]) {
        expect(
          accentModeChange(mode, const []).accentPalette,
          isNull,
          reason: '$mode does not read the palette',
        );
      }
    });

    test('every seeded stop is a colour this client can draw', () {
      // The seed is hex, matching the web value for value, while the phone's own picker stores
      // preset NAMES. Both have to resolve or the editor opens on question marks — which is the
      // same "it does nothing" impression the empty palette gave.
      final seeded = accentModeChange(AccentMode.fade, const []).accentPalette!;
      for (final stop in seeded) {
        expect(
          accentSwatch(stop) ?? parseHexColor(stop),
          isNotNull,
          reason: 'the palette editor draws $stop with exactly this resolution',
        );
      }
      // Distinct, because two stops of the same colour animate into a flat colour and read, once
      // again, as a feature that does nothing.
      expect(seeded.toSet(), hasLength(seeded.length));
    });
  });
}
