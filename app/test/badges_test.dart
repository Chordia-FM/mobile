import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/social/widgets/badge_art.dart';
import 'package:chordia_mobile/features/social/widgets/user_identity.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The badges a profile wears: their order, their art, and what a tap on one says.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting();
    translations = await Translations.load('en', bundle: rootBundle);
  });

  testWidgets('the row settles into one order, whatever the Hub sent', (
    tester,
  ) async {
    // Deliberately backwards on the wire. Identity before status: who someone IS on this instance
    // reads before what they have done, and the tier badges come last because they are the only
    // ones that can change every month.
    await tester.pumpWidget(
      _app(const [
        ProfileBadgeSonic(since: 0, streakMonths: 2),
        ProfileBadgeEarlyBird(joinedAt: 0, position: 41),
        ProfileBadgeStaff(role: StaffRole.moderator),
      ]),
    );
    await tester.pump();

    expect(
      tester
          .widgetList<BadgeArt>(find.byType(BadgeArt))
          .map((a) => a.badge.kind),
      ['staff', 'early_bird', 'sonic'],
    );
  });

  testWidgets('a badge answers a tap with what it means', (tester) async {
    await tester.pumpWidget(
      _app(const [ProfileBadgeSuperSonic(since: 0, streakMonths: 7)]),
    );
    await tester.pump();

    await tester.tap(find.byType(BadgeArt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The stage the streak has reached — seven unbroken months is Nova, the third.
    expect(
      find.text('3. ${translations(SocialKeys.badgesStageNova)}'),
      findsOneWidget,
    );
    // And why this person has it, which is the question a badge on a stranger's profile raises and
    // the one the chip this replaced could not answer at all.
    expect(
      find.text(translations(SocialKeys.badgesAboutSuperSonic)),
      findsOneWidget,
    );
  });

  group('the Super-Sonic streak', () {
    test('reaches a stage at the month it is earned, not before', () {
      expect(stageFor(0).stage, 1);
      expect(stageFor(2).stage, 1);
      expect(stageFor(3).stage, 2);
      expect(stageFor(5).stage, 2);
      expect(stageFor(6).stage, 3);
      expect(stageFor(11).stage, 3);
      expect(stageFor(12).stage, 4);
      // Stages accumulate rather than cycling, so a long streak stays at the top one.
      expect(stageFor(120).stage, 4);
    });
  });
}

Widget _app(List<ProfileBadge> badges) => ProviderScope(
  overrides: [translationsProvider.overrideWithValue(translations)],
  child: MaterialApp(
    theme: buildChordiaTheme(),
    home: Scaffold(
      body: Center(child: BadgeRow(badges: badges)),
    ),
  ),
);
