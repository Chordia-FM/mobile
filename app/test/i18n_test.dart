import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveChain', () {
    const available = ['en', 'en-GB', 'de-DE', 'pt-BR', 'ja-JP'];

    test('a regional locale falls back to its base language, then English', () {
      expect(Translations.resolveChain('en-GB', available), ['en-GB', 'en']);
    });

    test('a base language with only regional catalogs still reaches English', () {
      // `de` has no catalog of its own; `de-DE` is not a fallback for it, so English is the answer.
      expect(Translations.resolveChain('de', available), ['en']);
    });

    test('matching ignores case and underscore separators', () {
      // System locales arrive as `en_gb` on some platforms.
      expect(Translations.resolveChain('en_gb', available), ['en-GB', 'en']);
      expect(Translations.resolveChain('PT-br', available), ['pt-BR', 'en']);
    });

    test('an unknown locale resolves to English rather than failing', () {
      expect(Translations.resolveChain('xx-YY', available), ['en']);
    });

    test('English never appears twice', () {
      expect(Translations.resolveChain('en', available), ['en']);
    });
  });

  group('Translations', () {
    test('reads a real key from the shipped catalogs', () async {
      final t = await Translations.load('en', bundle: rootBundle);
      expect(t.locale, 'en');
      expect(t.has('player:controls.play'), isTrue);
      expect(t('player:controls.play'), 'Play');
    });

    test('a regional catalog overrides only what it defines', () async {
      final en = await Translations.load('en', bundle: rootBundle);
      final gb = await Translations.load('en-GB', bundle: rootBundle);
      expect(gb.locale, 'en-GB');
      // en-GB ships exactly one override today; it must win…
      expect(gb('common:userMenu.stats'), 'Statistics');
      expect(en('common:userMenu.stats'), isNot('Statistics'));
      // …while everything it does not define still resolves through en.
      expect(gb('player:controls.play'), 'Play');
    });

    test(
      'a missing key returns the key, so it is visible rather than blank',
      () async {
        final t = await Translations.load('en', bundle: rootBundle);
        expect(t('nosuch:key.at.all'), 'nosuch:key.at.all');
      },
    );

    test('applies ICU plurals against the resolved locale', () async {
      final t = await Translations.load('en', bundle: rootBundle);
      // A real catalog string rather than an invented one, so this tracks the actual patterns.
      const key = AdminKeys
          .backupsPaneArchives; // "{count, plural, one {# archive} other {# archives}}"
      expect(t.has(key), isTrue);
      expect(t(key, {'count': 1}), '1 archive');
      expect(t(key, {'count': 5}), '5 archives');
    });

    test('leaves apostrophes in ordinary prose alone', () async {
      // ICU treats ' as quoting. Literal strings must bypass the formatter entirely or French
      // copy like "d'écoute" loses characters.
      final t = await Translations.load('fr-FR', bundle: rootBundle);
      final line = t('library:shareManager.statsLine', {
        'plays': 3,
        'time': '1h',
      });
      expect(line, isNot(contains('écoute"')));
      expect(line, contains('3'));
    });
  });
}
