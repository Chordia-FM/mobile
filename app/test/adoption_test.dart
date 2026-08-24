import 'dart:io';

import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/catalog/widgets/list_row.dart';
import 'package:chordia_mobile/features/library/widgets/collection_header.dart';
import 'package:chordia_mobile/features/settings/widgets/settings_list.dart';
import 'package:chordia_mobile/widgets/surface.dart';
import 'package:chordia_mobile/widgets/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The design system was shipped a wave before anything ADOPTED it.
///
/// `identity_test.dart` already guards the primitives themselves, and `typography_test.dart`
/// guards the theme that feeds them — but every one of those gates stops at `lib/widgets`, which
/// is the one directory that was never the problem. The 49 `ListTile`s, the 40 hand-typed corner
/// radii and the flat `surfaceContainer` fills all lived in `lib/features`, where nothing looked.
///
/// So these rules point at the feature tree. Each one fails on a specific, silent regression: a
/// new screen reaching for `ListTile` because it is what Flutter documents, a `BorderRadius`
/// typed as a number because the token was one import away, a page title left on `headline*`
/// because it renders perfectly legible sans.
void main() {
  final features = Directory('lib/features')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  String rel(File file) => file.path.replaceAll(r'\', '/');

  /// A file's code with its comments removed.
  ///
  /// Taken from `identity_test.dart` for the same reason it exists there: several of the files
  /// below explain in prose why they do NOT use the thing being banned, and a grep over raw
  /// source cannot tell a prohibition from a use.
  String codeOf(File file) => file
      .readAsLinesSync()
      .map((line) {
        final comment = line.indexOf('//');
        return comment == -1 ? line : line.substring(0, comment);
      })
      .join('\n');

  setUpAll(() {
    // Without this every rule below passes vacuously if the directory is ever moved.
    expect(features.length, greaterThan(100));
  });

  group('the ported row is the row', () {
    /// `ListTile`, `SwitchListTile` and `CheckboxListTile`, but NOT `RadioListTile` — the
    /// lookbehind is what separates them, and the two remaining radio groups are named below.
    /// The trailing class also has to admit `.adaptive`, which is how the two switch rows in this
    /// tree were actually written — a rule that only knew `ListTile(` would have read the file
    /// they were in and reported it clean.
    final tile = RegExp(r'(?<![A-Za-z])(Switch|Checkbox)?ListTile\s*[(<.]');

    /// Where Material's own row is still the honest answer.
    ///
    /// `settings_list.dart` holds two `RadioListTile`s. A radio is not a list row: it belongs to a
    /// `RadioGroup` that owns the selection and the keyboard traversal for the whole set, and the
    /// web draws that set as bordered option CARDS (`settings/PlaybackSection.tsx:47-72`), not as
    /// rows at all. Porting it is a shape change, not a row swap, so it is left whole rather than
    /// half-converted into a row that lies about what it is.
    bool exempt(String path) =>
        path.endsWith('/features/settings/widgets/settings_list.dart');

    test('no feature screen builds a Material list row', () {
      final offenders = <String>[];
      for (final file in features) {
        if (exempt(rel(file))) continue;
        final lines = codeOf(file).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (tile.hasMatch(lines[i])) {
            offenders.add('${rel(file)}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'use ListRow (features/catalog/widgets/list_row.dart) — a ListTile '
            'brings Material heights, insets, type scale and ink',
      );
    });

    test('the rule catches a tile and spares a radio', () {
      // The lookbehind is the whole subtlety here: without it this rule would fire on the
      // `RadioListTile`s it deliberately allows, and the only way to get it green again would be
      // to exempt the file wholesale and lose the check.
      expect(tile.hasMatch('      return ListTile('), isTrue);
      expect(tile.hasMatch('  SwitchListTile.adaptive('), isTrue);
      expect(tile.hasMatch('        CheckboxListTile('), isTrue);
      expect(tile.hasMatch('          RadioListTile<T>(value: v),'), isFalse);
    });
  });

  group('corners come from the scale', () {
    // `identity_test.dart` runs this over `lib/widgets`. Every one of the 40 offenders was in
    // `lib/features`, which that gate never reads — including a 14, a 6 and three 4s, corners the
    // web has nowhere.
    final literal = RegExp(r'Radius\.circular\(\s*[\d.]');

    /// `badge_art.dart` draws the badge illustrations as vector paths, where a `Radius` is an
    /// ARC's radius rather than a box corner. `ChordiaRadius` has nothing to say about it.
    bool exempt(String path) =>
        path.endsWith('/features/social/widgets/badge_art.dart');

    test('no feature file types a corner as a number', () {
      final offenders = <String>[];
      for (final file in features) {
        if (exempt(rel(file))) continue;
        final lines = codeOf(file).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (literal.hasMatch(lines[i])) {
            offenders.add('${rel(file)}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'use ChordiaRadius — see lib/widgets/tokens.dart',
      );
    });

    test('the rule would actually catch a violation', () {
      expect(
        literal.hasMatch('  borderRadius: BorderRadius.circular(14),'),
        isTrue,
      );
      expect(
        literal.hasMatch(
          '  borderRadius: const BorderRadius.all(Radius.circular(3)),',
        ),
        isTrue,
      );
      expect(literal.hasMatch('  borderRadius: ChordiaRadius.xlAll,'), isFalse);
    });
  });

  group('a page title is set in the serif', () {
    // `.display-title` is on 19 elements in the web client and all 19 are page H1s, so the phone's
    // page titles belong on the `display*` slots. This is a widget test rather than a grep because
    // the failure is a slot name — `headlineLarge` instead of `displayLarge` — which renders
    // perfectly good sans text at a plausible size and looks like nothing is wrong.
    testWidgets('a collection header is Fraunces, not Manrope', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildChordiaTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: CollectionHeader(
                eyebrow: 'Playlist',
                title: 'Late Night',
                meta: '12 songs',
                artwork: SizedBox.square(dimension: 96),
              ),
            ),
          ),
        ),
      );

      final heading = tester.widget<Text>(find.text('Late Night'));
      expect(
        heading.style?.fontFamily,
        ChordiaType.display,
        reason: 'the web puts .display-title on this H1',
      );
      // `text-3xl`, which is what the class resolves to at phone width. Pinned because the slot
      // and the size are two different mistakes: a serif at `displaySmall` would pass a family
      // check while drawing a 24px title where the web draws 30.
      expect(heading.style?.fontSize, 30);
    });
  });

  group('content sits on the panel material', () {
    testWidgets('a settings group is an IslandPanel, not a flat fill', (
      tester,
    ) async {
      // `settings/Section.tsx:15` is `island-shell rounded-2xl p-3`. A `surfaceContainer` fill at
      // the same corner is the right SHAPE with none of the material — no accent hairline, no
      // gradient — which is precisely the "looks like a different app" complaint at card scale.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildChordiaTheme(),
          home: const Scaffold(
            body: SettingsSection(
              title: 'Playback',
              children: [ListRow(title: Text('Crossfade'))],
            ),
          ),
        ),
      );

      expect(find.byType(IslandPanel), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(IslandPanel),
          matching: find.byType(ListRow),
        ),
        findsOneWidget,
      );
    });

    /// The insights reports were the largest remaining case of this: the web wraps every chart in
    /// `Panel` (`insights/primitives.tsx:132`) and the phone had the heading without the panel, so
    /// six tabs of charts scrolled past as one flat column with labels floating between them.
    ///
    /// The regression this catches is the exact shape the flat column had — a `ReportHeading`
    /// with a chart under it, where a `ReportPanel` was the answer.
    group('a chart sits on the panel material', () {
      final charts = RegExp(
        r'(?<![A-Za-z])(BarChart|GenreFlow|FingerprintRadar|MusicRatioRings'
        r'|ClockGridHeatmap|CalendarHeatmap)\s*\(',
      );

      /// How far below a heading a chart still reads as belonging to it. Six covers a heading
      /// wrapped over an `if`, a spread and a `Column` opener.
      const reach = 6;

      final reports = features
          .where((file) => rel(file).contains('/features/insights/'))
          .toList(growable: false);

      setUpAll(() {
        // Without this the scan below passes by reading nothing at all.
        expect(reports.length, greaterThan(5));
      });

      test('no report puts a chart under a bare heading', () {
        final offenders = <String>[];
        for (final file in reports) {
          final lines = codeOf(file).split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (!lines[i].contains('ReportHeading(')) continue;
            final end = (i + reach).clamp(0, lines.length - 1);
            for (var j = i + 1; j <= end; j++) {
              if (charts.hasMatch(lines[j])) {
                offenders.add('${rel(file)}:${j + 1}  ${lines[j].trim()}');
                break;
              }
            }
          }
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'use ReportPanel — a chart under a floating label is the flat '
              'column the web draws as an island-shell section',
        );
      });

      test('the rule would actually catch a violation', () {
        expect(charts.hasMatch('          BarChart(bars: bars),'), isTrue);
        expect(charts.hasMatch('        ClockGridHeatmap(grid: g),'), isTrue);
        // The panel's own name must not read as a chart, or the rule would fire on the fix.
        expect(charts.hasMatch('        ReportPanel(title: x),'), isFalse);
      });
    });
  });

  group('a sheet wears the theme, not a panel', () {
    // The decision recorded on `bottomSheetTheme`: Flutter's `BottomSheet` already owns the
    // Material a sheet is drawn on, so the modal material lives on the theme and the content
    // inside stays plain. Both halves are pinned here, because either one alone is a regression —
    // a flat pane colour loses the material, and a missing side loses the accent hairline that
    // separates the sheet from the dimmed page behind it.
    test('the sheet pane IS the modal material', () {
      final theme = buildChordiaTheme();
      final scheme = theme.colorScheme;

      expect(
        theme.bottomSheetTheme.backgroundColor,
        Color.lerp(scheme.modalTop, scheme.modalBottom, 0.5),
        reason: 'a sheet is `island-shell island-shell-modal` on the web',
      );
      // A dialog is the same element on the web, so it cannot be a different colour here.
      expect(
        theme.dialogTheme.backgroundColor,
        theme.bottomSheetTheme.backgroundColor,
      );

      final shape = theme.bottomSheetTheme.shape;
      expect(shape, isA<RoundedRectangleBorder>());
      final box = shape! as RoundedRectangleBorder;
      expect(
        box.side.color,
        scheme.panelBorder,
        reason: '`.island-shell` is a border as much as it is a fill',
      );
      expect(box.borderRadius, ChordiaRadius.sheetTop);
    });
  });
}
