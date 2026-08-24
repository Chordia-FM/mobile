import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/social/widgets/badge_art.dart';
import 'package:chordia_mobile/features/social/widgets/badge_directory.dart';
import 'package:chordia_mobile/features/social/widgets/user_identity.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The badge directory, and the way in from a badge somebody is wearing.
///
/// A chip that explains itself and stops there is where this was: the phone had every name, every
/// explanation and every stroke of the art, and no page that put them together.
late Translations translations;

BadgeCatalogEntry _entry(
  String kind, {
  int holders = 3,
  bool obtainable = true,
  int? remaining,
  List<BadgeCountPoint>? history,
}) => BadgeCatalogEntry(
  holders: holders,
  kind: kind,
  obtainable: obtainable,
  remaining: remaining,
  history: history,
);

Widget _app(List<BadgeCatalogEntry> entries, {required Widget home}) =>
    ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(translations),
        badgeCatalogProvider.overrideWith((ref) async => entries),
      ],
      child: MaterialApp(theme: buildChordiaTheme(), home: home),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting();
    translations = await Translations.load('en', bundle: rootBundle);
  });

  testWidgets('a worn badge leads to the directory, opened at itself', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        [_entry('early_bird'), _entry('sonic')],
        home: const Scaffold(
          body: BadgeRow(badges: [ProfileBadgeEarlyBird(joinedAt: 0)]),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(BadgeArt));
    await tester.pumpAndSettle();

    // The sheet first: the rank, the streak and the date belong to the person whose profile this
    // is, and a catalogue of badges in general can never say them.
    expect(find.text(translations(SocialKeys.badgesAboutEarlyBird)), findsOne);

    await tester.tap(find.text(translations(SocialKeys.badgesDirectoryTitle)));
    await tester.pumpAndSettle();

    // And out to the whole set, with the badge that was tapped named on it.
    expect(
      find.text(translations(SocialKeys.badgesDirectoryNameEarlyBird)),
      findsOne,
    );
    // One paragraph, not a field: the label and the instruction are two spans of one line, so this
    // matches the sentence they make together.
    expect(
      find.text(
        '${translations(SocialKeys.badgesDirectoryHowTo)} '
        '${translations(SocialKeys.badgesDirectoryEarnEarlyBird)}',
      ),
      findsOne,
      reason: 'how to get one is the question a profile cannot answer',
    );
    expect(
      find.text(translations(SocialKeys.badgesDirectoryNameSonic)),
      findsOne,
      reason: 'and the badges the reader does not have, which is the point',
    );
  });

  testWidgets('a badge this build has never heard of is left out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Every string and every stroke describing a badge lives in a local table, so a newer Hub's
    // badge would otherwise render as three raw i18n keys under an empty square.
    await tester.pumpWidget(
      _app([
        _entry('sonic'),
        _entry('chart_topper'),
      ], home: const BadgeDirectoryScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(BadgeArt), findsOneWidget);
    expect(find.textContaining('chart_topper'), findsNothing);
  });

  testWidgets('a badge running out says how many are left', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app([
        _entry('early_supporter', holders: 97, obtainable: true, remaining: 3),
      ], home: const BadgeDirectoryScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // Both halves on one line, joined the way the web joins them. "97 holders" alone does not say
    // that the badge is nearly gone, which is the fact worth reading.
    expect(
      find.text(
        '${translations(SocialKeys.badgesDirectoryHolders, {'count': 97})} · '
        '${translations(SocialKeys.badgesDirectoryRemaining, {'count': 3})}',
      ),
      findsOne,
    );
  });

  test('the directory covers every badge that can be worn', () {
    // The failure nobody notices: a badge that exists and is missing from the page that explains
    // the badges. Both sides are keyed by the same wire strings precisely so this can be checked.
    const worn = [
      ProfileBadgeDeveloper(title: 'Dev'),
      ProfileBadgeStaff(role: StaffRole.admin),
      ProfileBadgeTranslator(),
      ProfileBadgeEarlyBird(joinedAt: 0),
      ProfileBadgeEarlySupporter(rank: 1, since: 0),
      ProfileBadgeSonic(since: 0, streakMonths: 0),
      ProfileBadgeSuperSonic(since: 0, streakMonths: 0),
    ];
    for (final badge in worn) {
      expect(
        representativeBadge(badge.kind)?.kind,
        badge.kind,
        reason:
            '${badge.kind} is worn on profiles but absent from the directory',
      );
    }
  });
}
