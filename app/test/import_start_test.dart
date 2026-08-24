import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/theme.dart';
import 'package:chordia_mobile/features/settings/data/settings_providers.dart';
import 'package:chordia_mobile/features/settings/data_screen.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Starting a listening-history import from the phone.
///
/// The screen could show somebody else's job and not begin one, which is the least useful half of
/// the feature. These press the action end to end with a stand-in picker, so the wiring is proven
/// before the picker package that will feed it lands.
late Translations translations;

/// What reached the Hub.
typedef Started = ({Uint8List bytes, ImportSource? source});

UserProfile _profile() => const UserProfile(
  createdAt: 0,
  displayName: 'Kanin',
  handle: 'kanin',
  id: 'u-1',
  entitlements: Entitlements(
    tier: PlanTier.superSonic,
    features: [Feature.historyImport],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  /// Pumps the Data screen with a picker that answers [bytes], recording what gets uploaded.
  Future<List<Started>> pumpData(
    WidgetTester tester, {
    Uint8List? bytes,
    List<ImportJob> jobs = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final started = <Started>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          translationsProvider.overrideWithValue(translations),
          myProfileProvider.overrideWith((ref) async => _profile()),
          importJobsProvider.overrideWith((ref) async => jobs),
          if (bytes != null)
            importFilePickerProvider.overrideWithValue(
              () async => PickedImport(bytes: bytes),
            ),
          importStarterProvider.overrideWithValue((bytes, source) async {
            started.add((bytes: bytes, source: source));
          }),
        ],
        child: MaterialApp(
          theme: buildChordiaTheme(),
          home: const DataScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    return started;
  }

  testWidgets('choosing a file uploads it and refreshes the job list', (
    tester,
  ) async {
    final started = await pumpData(
      tester,
      bytes: Uint8List.fromList('[{"ts":"2024-01-01"}]'.codeUnits),
    );

    await tester.tap(find.text(translations(SettingsKeys.importChooseFile)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(started, hasLength(1));
    expect(started.single.bytes, isNotEmpty);
    // Null is `auto`. The Hub sniffs the content either way and a stated source that contradicts
    // the bytes is a 400, so naming none is the only choice that is never wrong.
    expect(started.single.source, isNull);
  });

  testWidgets('a file over the Hub ceiling never reaches the socket', (
    tester,
  ) async {
    final started = await pumpData(
      tester,
      // One byte past what `POST /v1/me/imports` accepts. Uploading it would spend the whole
      // transfer to be told 413, on a connection the reader is paying for.
      bytes: Uint8List(ImportEndpoints.maxUploadBytes + 1),
    );

    await tester.tap(find.text(translations(SettingsKeys.importChooseFile)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(started, isEmpty);
    expect(find.text(translations(SettingsKeys.importTooLarge)), findsOne);
  });

  testWidgets('with no picker the screen says so instead of offering one', (
    tester,
  ) async {
    // The state this build actually ships in. A "Choose file" row that opened nothing would be a
    // worse answer than the sentence pointing at the browser.
    await pumpData(tester);

    expect(
      find.text(translations(SettingsKeys.importChooseFile)),
      findsNothing,
    );
    expect(
      find.text(translations(SettingsKeys.importStartInBrowser)),
      findsOne,
    );
  });
}
