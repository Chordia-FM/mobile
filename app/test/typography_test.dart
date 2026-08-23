import 'dart:io';

import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/data/accent/accent_palette.dart';
import 'package:chordia_mobile/data/accent/oklab.dart';
import 'package:chordia_mobile/widgets/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The face, the scale and the press feedback — the three things that made the phone read as a
/// different product from the web client even when the colours were right.
///
/// None of these fail loudly in the app. A missing font falls back to Roboto and renders perfectly
/// legible text; a re-introduced ripple looks like a deliberate Material choice; a hairline mixed
/// twice is just slightly brighter than the web's. They only show up side by side with the browser,
/// which is exactly the comparison nobody makes during a refactor.
void main() {
  final theme = buildChordiaTheme();
  final text = theme.textTheme;

  group('the app is set in the web client\'s faces', () {
    test('the pubspec declares every font file it names, and they exist', () {
      // A `fonts:` entry pointing at a missing asset is not a build error — Flutter warns and the
      // family silently resolves to the platform default, which is the exact bug this closes.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final assets = RegExp(
        r'asset:\s*(assets/fonts/[^\s]+)',
      ).allMatches(pubspec).map((m) => m.group(1)!).toList();

      expect(
        assets,
        containsAll([
          'assets/fonts/Manrope-Regular.ttf',
          'assets/fonts/Manrope-Medium.ttf',
          'assets/fonts/Manrope-SemiBold.ttf',
          'assets/fonts/Manrope-Bold.ttf',
          'assets/fonts/Fraunces-SemiBold.ttf',
          'assets/fonts/Fraunces-Bold.ttf',
        ]),
        reason: 'the weights the web uses: 400/500/600/700 sans, 600/700 serif',
      );
      for (final asset in assets) {
        expect(File(asset).existsSync(), isTrue, reason: '$asset is missing');
      }
    });

    test('body copy is Manrope and page titles are Fraunces', () {
      for (final style in [
        text.bodyLarge,
        text.bodyMedium,
        text.bodySmall,
        text.titleMedium,
        text.headlineSmall,
        text.labelLarge,
      ]) {
        expect(style!.fontFamily, ChordiaType.sans);
      }
      for (final style in [
        text.displayLarge,
        text.displayMedium,
        text.displaySmall,
      ]) {
        expect(style!.fontFamily, ChordiaType.display);
      }
    });

    test('the serif stays on display*, which is where .display-title is', () {
      // `headline*` is the phone's slot for stat values and the now-playing title, neither of
      // which is an `<h1>` on the web. Serif-ing the whole heading range would be a new design.
      for (final style in [
        text.headlineLarge,
        text.headlineMedium,
        text.headlineSmall,
      ]) {
        expect(style!.fontFamily, isNot(ChordiaType.display));
      }
    });

    test('a size and a line height came from the web, not from Material', () {
      // Material's `bodyMedium` is 14/20 too, so this pins the pairing that differs: the default
      // body size is `text-sm`, and `labelSmall` does NOT drop to Material's 11px.
      expect(text.bodyMedium!.fontSize, 14);
      expect(text.bodyMedium!.height, 20 / 14);
      expect(text.labelSmall!.fontSize, 12);
      expect(text.displayMedium!.fontSize, 30);
      expect(text.displayMedium!.fontWeight, ChordiaType.bold);
    });

    test('nothing inherits Material tracking', () {
      // `TextTheme.merge` keeps any null field, so an unset `letterSpacing` silently picks up
      // Roboto's (0.25 on bodyMedium). Tailwind's normal tracking is 0.
      final slots = <TextStyle?>[
        text.displayLarge,
        text.displayMedium,
        text.displaySmall,
        text.headlineLarge,
        text.headlineMedium,
        text.headlineSmall,
        text.titleLarge,
        text.titleMedium,
        text.titleSmall,
        text.bodyLarge,
        text.bodyMedium,
        text.bodySmall,
        text.labelLarge,
        text.labelMedium,
        text.labelSmall,
      ];
      for (final style in slots) {
        expect(style!.letterSpacing, 0);
      }
    });
  });

  group('no ripple unless a widget asks for one', () {
    test('the theme turns the splash off', () {
      expect(theme.splashFactory, NoSplash.splashFactory);
    });

    test('the press highlight is the web row fill, not Material grey', () {
      // With no splash the highlight is the entire feedback, so it has to be visible and on
      // palette. Material's default is a light grey that reads as dust on these panes.
      expect(theme.highlightColor, theme.colorScheme.rowHighlight);
    });
  });

  group('controls are on the web scale', () {
    Size minSize(ButtonStyle? style) =>
        style!.minimumSize!.resolve(const <WidgetState>{})!;
    OutlinedBorder shape(ButtonStyle? style) =>
        style!.shape!.resolve(const <WidgetState>{})!;

    test('every button family is themed, not just the filled one', () {
      final styles = {
        'filled': theme.filledButtonTheme.style,
        'text': theme.textButtonTheme.style,
        'outlined': theme.outlinedButtonTheme.style,
        'icon': theme.iconButtonTheme.style,
      };
      for (final entry in styles.entries) {
        // A `StadiumBorder` here means the family fell back to Material 3 and renders as a pill.
        expect(
          shape(entry.value),
          isA<RoundedRectangleBorder>().having(
            (b) => b.borderRadius,
            'radius',
            ChordiaRadius.mdAll,
          ),
          reason: '${entry.key} is off the corner scale',
        );
        expect(
          minSize(entry.value).height,
          greaterThanOrEqualTo(44),
          reason: '${entry.key} is below the coarse-pointer target floor',
        );
      }
    });

    test('an icon button is a 48pt square, not Flutter\'s 40', () {
      expect(minSize(theme.iconButtonTheme.style), const Size.square(48));
    });
  });

  group('there is one colour derivation', () {
    final scheme = theme.colorScheme;
    final surfaces = ChordiaSurfaces.of(builtinAccent);

    test('the hairline is not mixed with the accent a second time', () {
      // `scheme.line` used to be `Color.lerp(outline, primary, 0.16)`, and `outline` is already
      // `--border`, which carries a 16% mix. The phone drew #4e124d where the web draws #36163a.
      expect(scheme.line, surfaces.border);
      expect(scheme.line, const Color(0xFF36163A));
    });

    test('--border and --line are two different tokens', () {
      // They are: `--border` is a near-black mixed 16% toward the accent, `--line` is the accent
      // itself at 18% alpha. Mobile carries both under the name `line`, on two different objects.
      expect(scheme.line, isNot(surfaces.line));
      expect(surfaces.line.a, closeTo(0.18, 0.01));
    });

    test('the island gradient uses its own bases, not nearby surface roles', () {
      // Pinned by value, the way `accent_test.dart` pins `ChordiaColors`: the panel stops are the
      // colours a browser computes for `.island-shell` on the default accent, so a drift in the
      // maths fails here instead of shipping a slightly-off product.
      //
      // The failure this was written for: deriving the stops from `--pane-raised` and
      // `--background` by an sRGB lerp instead of from the rule's own bases in OKLab. That gave
      // #15041a -> #0a000b, a panel bottom at roughly half the web's lightness and far more
      // purple, on a base the stylesheet itself calls the wrong blue-violet.
      expect(scheme.panelTop, const Color(0xFF120B13));
      expect(scheme.panelBottom, const Color(0xFF090409));
      expect(scheme.modalTop, const Color(0xFF221423));
      expect(scheme.modalBottom, const Color(0xFF100811));
      // And the relationship those numbers exist to produce: a dialog is elevated above a panel,
      // which is elevated above the page.
      expect(
        relativeLuminance(scheme.modalTop),
        greaterThan(relativeLuminance(scheme.panelTop)),
      );
      expect(
        relativeLuminance(scheme.panelBottom),
        greaterThan(relativeLuminance(surfaces.background)),
      );
    });

    test('the panels follow the account accent', () {
      final amber = const Color(0xFFFFB020);
      final other = buildChordiaTheme(ChordiaSurfaces.of(amber)).colorScheme;
      expect(other.panelTop, isNot(scheme.panelTop));
      expect(other.line, isNot(scheme.line));
    });

    test('a card fills with --accent, the lightest shadcn surface', () {
      // `hover:bg-accent/40`. Tailwind's `accent` is `--accent` = `paneElevated`, NOT `--card`.
      expect(
        scheme.cardHighlight,
        surfaces.paneElevated.withValues(alpha: 0.4),
      );
      expect(scheme.rowHighlight, surfaces.paneElevated.withValues(alpha: 0.5));
    });
  });
}
