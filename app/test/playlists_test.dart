import 'dart:async';
import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/features/catalog/data/catalog_providers.dart';
import 'package:chordia_mobile/features/downloads/downloads_api.dart';
import 'package:chordia_mobile/features/downloads/data/downloads_providers.dart';
import 'package:chordia_mobile/features/library/data/library_api.dart';
import 'package:chordia_mobile/features/library/widgets/collection_header.dart';
import 'package:chordia_mobile/features/library/data/library_providers.dart';
import 'package:chordia_mobile/features/library/playlist_detail_screen.dart';
import 'package:chordia_mobile/features/library/playlists_screen.dart';
import 'package:chordia_mobile/features/library/smart_playlist_screen.dart';
import 'package:chordia_mobile/features/playlists/data/collaborators_controller.dart';
import 'package:chordia_mobile/features/playlists/data/playlists_api.dart';
import 'package:chordia_mobile/features/playlists/data/playlists_providers.dart';
import 'package:chordia_mobile/features/playlists/data/smart_model.dart';
import 'package:chordia_mobile/features/playlists/smart_rules_screen.dart';
import 'package:chordia_mobile/i18n/keys.g.dart';
import 'package:chordia_mobile/i18n/translations.dart';
import 'package:chordia_mobile/i18n/translations_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loaded once, in real async: `testWidgets` runs inside a fake-async zone where an asset read
/// never completes, so the catalogs have to be in hand before the first pump.
late Translations translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    translations = await Translations.load('en', bundle: rootBundle);
  });

  group('the rule builder only offers combinations the Hub accepts', () {
    test(
      'every field has at least one operator, and its first is its default',
      () {
        for (final field in allSmartFields) {
          final ops = opsFor(field);
          expect(ops, isNotEmpty, reason: '$field has no operators');
          expect(conditionFor(field).op, ops.first, reason: '$field');
        }
      },
    );

    test('a boolean field offers only "is"', () {
      // Anything else would compile to a LIKE against "true", which matches nothing and looks like
      // a bug in the library rather than in the rule.
      expect(opsFor(SmartField.liked), [SmartOp.isValue]);
      expect(opsFor(SmartField.explicit), [SmartOp.isValue]);
    });

    test('a text field never offers a numeric or date operator', () {
      const numericOrDate = {
        SmartOp.gte,
        SmartOp.lte,
        SmartOp.before,
        SmartOp.after,
        SmartOp.inLast,
        SmartOp.notInLast,
        SmartOp.between,
      };
      for (final field in [
        SmartField.artist,
        SmartField.title,
        SmartField.album,
        SmartField.genre,
        SmartField.label,
      ]) {
        expect(
          opsFor(field).toSet().intersection(numericOrDate),
          isEmpty,
          reason: '$field',
        );
      }
    });

    test('a date field never offers a text operator', () {
      const textOnly = {
        SmartOp.contains,
        SmartOp.notContains,
        SmartOp.equals,
        SmartOp.notEquals,
      };
      for (final field in [
        SmartField.addedAt,
        SmartField.lastPlayed,
        SmartField.firstPlayed,
        SmartField.releaseDate,
      ]) {
        expect(
          opsFor(field).toSet().intersection(textOnly),
          isEmpty,
          reason: '$field',
        );
      }
    });

    test('switching field lands on an operator the new field accepts', () {
      // The pair is what the Hub validates, so this is the whole invariant: there must be no route
      // through the editor that leaves a field beside an operator it does not support.
      for (final from in allSmartFields) {
        for (final op in opsFor(from)) {
          final start = retargetOp(conditionFor(from), op);
          for (final to in allSmartFields) {
            final moved = retargetField(start, to);
            expect(moved.field, to);
            expect(
              opsFor(moved.field),
              contains(moved.op),
              reason: '$from/$op → $to produced ${moved.op}',
            );
          }
        }
      }
    });

    test('a rule set written by a newer client is snapped to a legal operator', () {
      // `SmartOp.fromWire` falls back rather than throwing, so a rule can arrive holding an
      // operator this field no longer accepts. Opening it must not produce a form that fails on
      // save with an error about something the person never chose.
      final rules = const SmartRules(
        conditions: [
          SmartCondition(
            field: SmartField.liked,
            op: SmartOp.between,
            value: 'true',
          ),
        ],
      );
      final rows = rowsFrom(rules);
      expect(rows.single.condition.op, SmartOp.isValue);
    });

    test('the value kind follows the pair, not the field alone', () {
      expect(valueKindOf(SmartField.addedAt, SmartOp.inLast), ValueKind.days);
      expect(valueKindOf(SmartField.addedAt, SmartOp.before), ValueKind.date);
      expect(valueKindOf(SmartField.duration, SmartOp.gte), ValueKind.duration);
      expect(
        valueKindOf(SmartField.versionType, SmartOp.notEquals),
        ValueKind.variant,
      );
    });

    test('changing the operator drops an upper bound the new one cannot use', () {
      const between = SmartCondition(
        field: SmartField.year,
        op: SmartOp.between,
        value: '1990',
        value2: '1999',
      );
      // Left behind, it would send a bound the person can no longer see and did not ask for.
      expect(retargetOp(between, SmartOp.gte).value2, isNull);
      expect(retargetOp(between, SmartOp.between).value2, '1999');
    });

    test(
      'switching to a field of a different kind does not keep the old value',
      () {
        const artist = SmartCondition(
          field: SmartField.artist,
          op: SmartOp.contains,
          value: 'Radiohead',
          valuesValue: ['Radiohead', 'Blur'],
        );
        // Artist → Album is the same kind, so the typed list survives.
        final album = retargetField(artist, SmartField.album);
        expect(album.value, 'Radiohead');
        expect(album.valuesValue, ['Radiohead', 'Blur']);

        // Artist → Liked is not, and a boolean has nowhere to put two band names.
        final liked = retargetField(artist, SmartField.liked);
        expect(liked.value, 'true');
        expect(liked.valuesValue, isNull);
      },
    );

    test('an unfinished rule is dropped rather than sent', () {
      const blank = SmartCondition(
        field: SmartField.artist,
        op: SmartOp.contains,
        value: '   ',
      );
      const halfRange = SmartCondition(
        field: SmartField.year,
        op: SmartOp.between,
        value: '1990',
      );
      expect(isComplete(blank), isFalse);
      expect(isComplete(halfRange), isFalse);
      // A boolean is never absent: its value is a choice between two.
      expect(
        isComplete(
          const SmartCondition(
            field: SmartField.liked,
            op: SmartOp.isValue,
            value: 'false',
          ),
        ),
        isTrue,
      );

      final rules = rulesFrom(
        matchMode: SmartMatch.all,
        rows: [
          RuleRow(blank),
          RuleRow(halfRange),
          RuleRow(conditionFor(SmartField.liked)),
        ],
        sort: SmartSort.title,
      );
      expect(rules.conditions, hasLength(1));
      expect(rules.conditions!.single.field, SmartField.liked);
    });

    test('a value list keeps `value` in step with its first entry', () {
      // The Hub falls back to `value` for rules written before lists existed, so a reader that
      // only understands it must still resolve the rule to something rather than to nothing.
      final one = normalizeCondition(
        const SmartCondition(
          field: SmartField.artist,
          op: SmartOp.equals,
          value: '',
          valuesValue: ['  Blur  '],
        ),
      );
      expect(one.value, 'Blur');
      // A one-item list and a plain value are the same rule; storing both spellings would mean
      // every comparison of two rule sets had to know that.
      expect(one.valuesValue, isNull);

      final many = normalizeCondition(
        const SmartCondition(
          field: SmartField.artist,
          op: SmartOp.equals,
          value: '',
          valuesValue: ['Blur', '', 'Pulp'],
        ),
      );
      expect(many.value, 'Blur');
      expect(many.valuesValue, ['Blur', 'Pulp']);
    });

    test('a window survives only on the field that has one', () {
      const period = SmartPeriodRolling(days: 30);
      final scoped = normalizeCondition(
        const SmartCondition(
          field: SmartField.myPlays,
          op: SmartOp.gte,
          value: '3',
          period: period,
        ),
      );
      expect(scoped.period, isA<SmartPeriodRolling>());

      // A window on a field the Hub does not scope is a field it would have to decide how to
      // ignore, so it never leaves here.
      final unscoped = normalizeCondition(
        const SmartCondition(
          field: SmartField.plays,
          op: SmartOp.gte,
          value: '3',
          period: period,
        ),
      );
      expect(unscoped.period, isNull);
    });

    test('a sort window is sent only for the sort that reads one', () {
      final withWindow = rulesFrom(
        matchMode: SmartMatch.all,
        rows: const [],
        sort: SmartSort.myPlaysInPeriod,
      );
      // Defaulted rather than omitted: the sort is meaningless without one.
      expect(withWindow.sortPeriod, isA<SmartPeriodRolling>());

      final without = rulesFrom(
        matchMode: SmartMatch.all,
        rows: const [],
        sort: SmartSort.title,
        sortPeriod: const SmartPeriodYear(year: 2025),
      );
      expect(without.sortPeriod, isNull);
    });

    test('a rule set round-trips through the contract types unchanged', () {
      final original = const SmartRules(
        conditions: [
          SmartCondition(
            field: SmartField.artist,
            op: SmartOp.equals,
            value: 'Blur',
            valuesValue: ['Blur', 'Pulp'],
          ),
          SmartCondition(
            field: SmartField.year,
            op: SmartOp.between,
            value: '1990',
            value2: '1999',
          ),
          SmartCondition(
            field: SmartField.myPlays,
            op: SmartOp.gte,
            value: '3',
            period: SmartPeriodMonth(month: '2026-08'),
          ),
          SmartCondition(
            field: SmartField.liked,
            op: SmartOp.isValue,
            value: 'true',
          ),
        ],
        limit: 50,
        matchMode: SmartMatch.any,
        sort: SmartSort.myPlaysInPeriod,
        sortDir: SmartSortDir.desc,
        sortPeriod: SmartPeriodRolling(days: 30),
      );

      // Wire → editor → wire. Anything the editor cannot represent would be lost here, and losing
      // part of somebody's rules on the way through an editor they only opened to read is the
      // failure this test exists to prevent.
      final decoded = SmartRules.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );
      final rebuilt = rulesFrom(
        matchMode: decoded.matchMode!,
        rows: rowsFrom(decoded),
        sort: decoded.sort!,
        sortDir: decoded.sortDir,
        sortPeriod: decoded.sortPeriod,
        limit: decoded.limit,
      );

      expect(jsonEncode(rebuilt.toJson()), jsonEncode(original.toJson()));
    });

    test('every preset builds rules the editor can reopen unchanged', () {
      final now = DateTime(2026, 8, 22);
      for (final preset in smartPresets) {
        final built = preset.build(now).rules;
        final rebuilt = rulesFrom(
          matchMode: built.matchMode!,
          rows: rowsFrom(built),
          sort: built.sort!,
          sortDir: built.sortDir,
          sortPeriod: built.sortPeriod,
          limit: built.limit,
        );
        expect(
          jsonEncode(rebuilt.toJson()),
          jsonEncode(built.toJson()),
          reason: preset.id,
        );
      }
    });

    test('a duration reads as m:ss and stores as milliseconds', () {
      expect(clockToMs('3:30'), '210000');
      expect(clockToMs('90'), '90000');
      expect(msToClock('210000'), '3:30');
      // A half-typed value is an incomplete rule the save path drops, not "longer than nothing".
      expect(clockToMs('3:'), '');
      expect(clockToMs(''), '');
      expect(msToClock('0'), '');
    });
  });

  group('collaborators change before the server answers', () {
    test('an invite shows as a pending row while it is in flight', () async {
      final api = _FakePlaylistsApi();
      final controller = _controller(api);

      api.blockAdd = true;
      final pending = controller.add('@dana');
      // The typed handle, immediately — the Hub is the only thing that can turn it into a profile,
      // and waiting two round trips for a name makes the invite look like it did nothing.
      expect(controller.people.map((p) => p.handle), ['dana']);
      expect(
        CollaboratorsController.isPending(controller.people.single),
        isTrue,
      );

      api
        ..roster = [_user('u9', 'dana', 'Dana')]
        ..completeAdd();
      expect(await pending, isTrue);
      // The reload is what replaces the placeholder with the real person.
      expect(controller.people.single.id, 'u9');
      expect(
        CollaboratorsController.isPending(controller.people.single),
        isFalse,
      );
      expect(api.added, ['dana']);
    });

    test('a refused invite takes its row back and reports it', () async {
      final api = _FakePlaylistsApi()..failAdd = true;
      final failures = <Object>[];
      final controller = _controller(api, onFailure: failures.add);

      expect(await controller.add('dana'), isFalse);
      expect(controller.people, isEmpty);
      expect(failures, hasLength(1));
      // A failed invite must not trigger the reload: there is nothing new to read, and doing it
      // anyway would hide the failure behind a refresh.
      expect(api.rosterReads, 0);
    });

    test(
      'the "@" people type is stripped, and a duplicate is not a second row',
      () async {
        final api = _FakePlaylistsApi()..roster = [_user('u9', 'dana', 'Dana')];
        final controller = _controller(api);
        await controller.load();

        expect(await controller.add('@Dana'), isTrue);
        expect(controller.people, hasLength(1));
        // The Hub treats re-adding an existing collaborator as success, so an optimistic duplicate
        // would survive on screen until the next reload.
        expect(api.added, isEmpty);
      },
    );

    test(
      'a removal drops the row without waiting, and comes back if refused',
      () async {
        final api = _FakePlaylistsApi()
          ..roster = [_user('u1', 'ada', 'Ada'), _user('u2', 'bo', 'Bo')];
        final controller = _controller(api);
        await controller.load();

        api.blockRemove = true;
        final pending = controller.remove('u1');
        expect(controller.people.map((p) => p.id), ['u2']);
        api.completeRemove();
        expect(await pending, isTrue);

        api
          ..blockRemove = false
          ..failRemove = true;
        expect(await controller.remove('u2'), isFalse);
        // Not merely "some roster": the exact one from before the tap.
        expect(controller.people.map((p) => p.id), ['u2']);
      },
    );

    test('leaving removes the signed-in user by their own id', () async {
      final api = _FakePlaylistsApi()
        ..roster = [_user('me', 'me', 'Me'), _user('u2', 'bo', 'Bo')]
        ..selfId = 'me';
      final controller = _controller(api);
      await controller.load();

      expect(await controller.leave(), isTrue);
      // The same call an owner uses to remove somebody else — which is why walking away does not
      // need the owner to be around to be asked.
      expect(api.removed, ['me']);
      expect(controller.people.map((p) => p.id), ['u2']);
    });
  });

  // Every one of these was built, tested at the controller level and never given a button. The
  // assertions here are all the same shape on purpose: press the thing a person would press, and
  // check the call it is supposed to make actually happens. That is the exact failure these
  // screens shipped with — a finished implementation nothing could reach.
  group('the playlist page can be managed from itself', () {
    testWidgets('its header opens the sheet that deletes it', (tester) async {
      final harness = await _pumpPlaylist(tester, _detail());

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Deleting a playlist had no route to it at all before this sheet was given a button.
      expect(find.text(_t(PlaylistsKeys.confirmDeleteTitle)), findsOneWidget);
      expect(find.text(_t(PlaylistsKeys.editTitle)), findsWidgets);
      // Also on the page underneath, hence `findsWidgets`.
      expect(find.text(_t(PlaylistsKeys.collaboratorsManage)), findsWidgets);
      expect(harness.edits.deleted, isEmpty);
    });

    testWidgets('deleting takes the page with it', (tester) async {
      final harness = await _pumpPlaylist(tester, _detail());

      await _openManageSheet(tester);
      await tester.tap(find.text(_t(PlaylistsKeys.confirmDeleteTitle)).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(CommonKeys.actionsDelete)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(harness.edits.deleted, ['p1']);
      // A deleted playlist has nothing left to reload, so the screen showing it has to go.
      expect(find.byType(PlaylistDetailScreen), findsNothing);
    });

    testWidgets('a collaborator is offered the way out, not delete', (
      tester,
    ) async {
      await _pumpPlaylist(tester, _detail(owned: false, canEdit: true));

      await _openManageSheet(tester);

      // `confirmLeavePlaylist` existed with no caller: somebody on a shared playlist could not get
      // off it from the phone at all.
      expect(find.text(_t(PlaylistsKeys.leaveTitle)), findsOneWidget);
      expect(find.text(_t(PlaylistsKeys.confirmDeleteTitle)), findsNothing);
    });

    testWidgets('the artwork opens the cover sheet that can upload', (
      tester,
    ) async {
      final harness = await _pumpPlaylist(tester, _detail());

      // The reachable editor could only pick a cover already inside the playlist; the sheet that
      // uploads a photo had no caller. Overriding the picker is what turns that row on, so its
      // presence here is the proof the good sheet is the one being opened.
      await tester.tap(find.byType(MosaicCover).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_t(PlaylistsKeys.editUploadPhoto)), findsOneWidget);

      await tester.tap(find.text(_t(PlaylistsKeys.editUploadPhoto)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The photo went up and the playlist was pointed at it: the whole path the reachable editor
      // could not walk, since `chordia_api`'s JSON transport cannot post bytes.
      expect(harness.edits.uploads, hasLength(1));
      expect(harness.edits.covers, ['uploaded-hash']);
    });
  });

  group('an empty playlist is not a dead end', () {
    testWidgets('it offers a way to put songs in it, and adding works', (
      tester,
    ) async {
      final harness = await _pumpPlaylist(tester, _detail(tracks: const []));

      await tester.tap(find.widgetWithIcon(FilledButton, Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Liked songs before anything is typed — the same thing the web client offers, and the
      // shortest route from an empty playlist to a full one.
      expect(find.text(_t(PlaylistsKeys.emptyStateFromLiked)), findsOneWidget);
      expect(find.text('Liked One'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.edits.addedTracks, [('p1', 'liked-1')]);
    });
  });

  group('track rows reach the menu every other row in the app has', () {
    testWidgets('a long press on a playlist row opens the full track menu', (
      tester,
    ) async {
      await _pumpPlaylist(tester, _detail());

      await tester.longPress(find.text('First'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Three items against the web client's fifteen was the gap. Queue and "add to playlist" are
      // the two that prove this is `showTrackMenu` and not the page's own three-item popup.
      expect(find.text(_t(PlayerKeys.queuePlayNext)), findsOneWidget);
      expect(find.text(_t(PlayerKeys.queueAdd)), findsOneWidget);
      expect(find.text(_t(CommonKeys.actionsGoToArtist)), findsOneWidget);
      expect(find.text(_t(CommonKeys.actionsGoToAlbum)), findsOneWidget);
      // Also the page's own button, hence `findsWidgets`.
      expect(find.text(_t(PlaylistsKeys.addToPlaylist)), findsWidgets);
    });
  });

  group('smart playlists can be created, edited and deleted', () {
    testWidgets('the list has a button that opens the rule builder', (
      tester,
    ) async {
      await _pumpApp(tester, const SmartPlaylistsScreen(), smart: _FakeSmart());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text(_t(PlaylistsKeys.smartNew)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // A ~2,000-line rule builder with a live preview, and nothing anywhere opened it.
      expect(find.byType(SmartRulesScreen), findsOneWidget);
      expect(find.text(_t(PlaylistsKeys.smartNewTitle)), findsOneWidget);
    });

    testWidgets('its own page opens the builder on its existing rules', (
      tester,
    ) async {
      final smart = _FakeSmart();
      await _pumpApp(
        tester,
        const SmartPlaylistScreen(playlistId: 's1'),
        smart: smart,
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(PlaylistsKeys.smartEditRules)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SmartRulesScreen), findsOneWidget);
      // Seeded from the playlist, not blank: opening the editor must not throw the rules away.
      expect(find.text(_t(PlaylistsKeys.smartEditTitle)), findsOneWidget);
    });

    testWidgets('and deletes one, taking the page with it', (tester) async {
      final smart = _FakeSmart();
      await _pumpApp(
        tester,
        const SmartPlaylistScreen(playlistId: 's1'),
        smart: smart,
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(PlaylistsKeys.smartDeleteTitle)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(_t(CommonKeys.actionsDelete)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(smart.deleted, ['s1']);
      expect(find.byType(SmartPlaylistScreen), findsNothing);
    });
  });

  group('a playlist can be made from nothing', () {
    testWidgets('the playlists list carries a create button', (tester) async {
      await _pumpApp(tester, const PlaylistsScreen());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text(_t(PlaylistsKeys.newKey)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // `showCreatePlaylistSheet` had no callers: the only route to a new playlist was filing a
      // track into one that did not exist yet, so an empty playlist could not be made at all.
      expect(find.text(_t(PlaylistsKeys.createSmart)), findsOneWidget);
      expect(find.text(_t(PlaylistsKeys.createNormal)), findsOneWidget);
    });
  });

  group('image uploads', () {
    test('the mime is read from the file, not from a name', () {
      expect(imageMimeOf(const [0x89, 0x50, 0x4E, 0x47, 0, 0]), 'image/png');
      expect(imageMimeOf(const [0xFF, 0xD8, 0xFF, 0, 0]), 'image/jpeg');
      expect(
        imageMimeOf(const [
          0x52, 0x49, 0x46, 0x46, // RIFF
          0, 0, 0, 0, //
          0x57, 0x45, 0x42, 0x50, // WEBP
          0,
        ]),
        'image/webp',
      );
      expect(imageMimeOf(const [1, 2, 3]), 'application/octet-stream');
    });
  });
}

CollaboratorsController _controller(
  _FakePlaylistsApi api, {
  void Function(Object error)? onFailure,
}) => CollaboratorsController(
  playlistId: 'p1',
  api: api,
  onFailure: onFailure ?? (_) {},
);

PublicUser _user(String id, String handle, String name) =>
    PublicUser(displayName: name, handle: handle, id: id);

class _FakePlaylistsApi implements PlaylistsApi {
  List<PublicUser> roster = [];
  String selfId = 'me';
  List<BrowseTrack> liked = const [];
  List<BrowseTrack> results = const [];

  final added = <String>[];
  final removed = <String>[];
  final deleted = <String>[];
  final covers = <String>[];
  final uploads = <List<int>>[];
  final addedTracks = <(String, String)>[];
  var rosterReads = 0;

  var failAdd = false;
  var failRemove = false;
  var blockAdd = false;
  var blockRemove = false;

  Completer<void>? _addGate;
  Completer<void>? _removeGate;

  void completeAdd() => _addGate?.complete();

  void completeRemove() => _removeGate?.complete();

  @override
  Future<List<PublicUser>> collaborators(String playlistId) async {
    rosterReads++;
    return List.of(roster);
  }

  @override
  Future<void> addCollaborator(String playlistId, String handle) async {
    if (blockAdd) {
      _addGate = Completer<void>();
      await _addGate!.future;
    }
    if (failAdd) throw StateError('refused');
    added.add(handle);
  }

  @override
  Future<void> removeCollaborator(String playlistId, String userId) async {
    if (blockRemove) {
      _removeGate = Completer<void>();
      await _removeGate!.future;
    }
    if (failRemove) throw StateError('refused');
    removed.add(userId);
    roster = [
      for (final person in roster)
        if (person.id != userId) person,
    ];
  }

  @override
  Future<String> myUserId() async => selfId;

  @override
  Future<void> addTrack(String playlistId, String trackId) async =>
      addedTracks.add((playlistId, trackId));

  @override
  Future<List<BrowseTrack>> likedTracks() async => liked;

  @override
  Future<List<BrowseTrack>> searchTracks(String query) async => results;

  @override
  Future<void> clearCover(String playlistId) => throw UnimplementedError();

  @override
  Future<Playlist> create(CreatePlaylistRequest request) async =>
      Playlist(createdAt: 0, id: 'p-new', name: request.name, trackCount: 0);

  @override
  Future<void> delete(String playlistId) async => deleted.add(playlistId);

  @override
  Future<List<Playlist>> playlists() async => const [];

  @override
  Future<void> setCover(String playlistId, String hash) async =>
      covers.add(hash);

  @override
  Future<void> update(String playlistId, PlaylistPatch changes) =>
      throw UnimplementedError();

  @override
  Future<String> uploadImage(List<int> bytes) async {
    uploads.add(bytes);
    return 'uploaded-hash';
  }
}

// ── Widget harness ─────────────────────────────────────────────────────────────

String _t(String key, [Map<String, Object?> args = const {}]) =>
    translations(key, args);

BrowseTrack _track(String id, String title) => BrowseTrack(
  artist: 'An Artist',
  artistId: 'ar-1',
  albumId: 'al-1',
  contentHash: 'hash-$id',
  durationMs: 180000,
  id: id,
  libraryId: 'lib-1',
  title: title,
  trackRef: 'ref-$id',
);

PlaylistDetail _detail({
  bool owned = true,
  bool canEdit = true,
  List<BrowseTrack>? tracks,
}) => PlaylistDetail(
  id: 'p1',
  name: 'Road Trip',
  owner: const PublicUser(displayName: 'Me', handle: 'me', id: 'me'),
  tracks: tracks ?? [_track('t1', 'First'), _track('t2', 'Second')],
  owned: owned,
  canEdit: canEdit,
  visibility: PlaylistVisibility.private,
);

class _Harness {
  _Harness(this.detail, this.edits);

  final _FakePlaylistApi detail;
  final _FakePlaylistsApi edits;
}

/// Pushes [screen] onto a real navigator, so a screen that pops itself has somewhere to pop to.
///
/// The alternative — putting it in `home:` — makes "the page went away" untestable: popping the
/// only route leaves the navigator empty rather than showing what was underneath.
Future<void> _pumpApp(
  WidgetTester tester,
  Widget screen, {
  _FakePlaylistApi? playlist,
  _FakePlaylistsApi? edits,
  _FakeSmart? smart,
}) async {
  // Tall enough that the header, the action row and the empty-state button are all on screen: the
  // default 800x600 puts the button a page press would reach below the fold, where a tap silently
  // hits nothing.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        translationsProvider.overrideWithValue(translations),
        playlistApiProvider.overrideWithValue(playlist),
        // Turning the picker on is what puts "Upload a photo" in the cover sheet, and that row is
        // the one thing the deleted inline picker could never offer.
        coverPhotoPickerProvider.overrideWithValue(
          () async => CoverPhoto(bytes: Uint8List.fromList(const [1, 2, 3])),
        ),
        playlistsEditApiProvider.overrideWithValue(edits),
        smartPlaylistsApiProvider.overrideWithValue(smart),
        pinsApiProvider.overrideWithValue(_FakePins()),
        // The track menu reads both of these on build; the test binding answers every HTTP request
        // with 400, so unfaked they would render the menu as a permanent failure.
        likedTrackIdsProvider.overrideWith(_FakeLikedIds.new),
        downloadedTrackIdsProvider.overrideWith(
          (ref) => Stream.value(<String>{}),
        ),
        // The menu reads the download pipeline as it builds; the real one wants a database.
        downloadsApiProvider.overrideWithValue(_FakeDownloads()),
      ],
      child: const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    ),
  );

  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  unawaited(
    navigator.push(MaterialPageRoute<void>(builder: (context) => screen)),
  );
  // Fixed frames rather than `pumpAndSettle`: the player ticks twice a second, so a settle never
  // returns anywhere this app's shell is mounted.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<_Harness> _pumpPlaylist(
  WidgetTester tester,
  PlaylistDetail detail,
) async {
  final api = _FakePlaylistApi(detail);
  final edits = _FakePlaylistsApi()..liked = [_track('liked-1', 'Liked One')];
  await _pumpApp(
    tester,
    const PlaylistDetailScreen(playlistId: 'p1'),
    playlist: api,
    edits: edits,
  );
  await tester.pump(const Duration(milliseconds: 100));
  return _Harness(api, edits);
}

Future<void> _openManageSheet(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.more_vert_rounded),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The download pipeline, doing nothing. Implemented rather than constructed: the real one wants a
/// database, a store and a pinned fetcher to answer a menu item that is only being LOOKED at.
class _FakeDownloads implements DownloadsApi {
  @override
  Future<void> start() async {}

  @override
  Future<DownloadOutcome> save(BrowseTrack track) => throw UnimplementedError();

  @override
  Future<DownloadBatch> saveAll(Iterable<BrowseTrack> tracks) =>
      throw UnimplementedError();

  @override
  Future<bool> remove(String trackId) async => true;

  @override
  Future<DownloadClearResult> removeAll(Iterable<String> trackIds) =>
      throw UnimplementedError();

  @override
  Future<DownloadClearResult> clear() => throw UnimplementedError();

  @override
  Future<void> cancel(String trackId) async {}

  @override
  Future<void> pause(String trackId) async {}

  @override
  Future<void> resume(String trackId) async {}

  @override
  Future<void> retry(String trackId) async {}
}

class _FakeLikedIds extends LikedTracksController {
  @override
  Future<Set<String>> build() async => const {};
}

class _FakePins implements PinsApi {
  @override
  Future<List<PinnedItem>> pins() async => const [];

  @override
  Future<void> add(PinKind kind, String id) async {}

  @override
  Future<void> remove(PinKind kind, String id) async {}

  @override
  Future<void> reorder(List<PinnedItem> order) async {}
}

/// The reading half of one playlist, for the detail screen's own controller.
class _FakePlaylistApi implements PlaylistApi {
  _FakePlaylistApi(this.value);

  PlaylistDetail value;

  @override
  Future<PlaylistDetail> detail(String playlistId) async => value;

  @override
  Future<void> reorderTracks(String playlistId, List<String> trackIds) async {}

  @override
  Future<void> removeTrack(String playlistId, String trackId) async {}

  @override
  Future<void> update(String playlistId, PlaylistPatch changes) async {}

  @override
  Future<void> setCover(String playlistId, String hash) async {}

  @override
  Future<void> clearCover(String playlistId) async {}

  @override
  Future<void> addCollaborator(String playlistId, String handle) async {}

  @override
  Future<void> removeCollaborator(String playlistId, String userId) async {}
}

class _FakeSmart implements SmartPlaylistsApi {
  final deleted = <String>[];
  final saved = <SmartBody>[];

  @override
  Future<SmartPlaylistDetail> detail(String playlistId) async =>
      SmartPlaylistDetail(
        id: playlistId,
        name: 'On Repeat',
        rules: const SmartRules(
          conditions: [
            SmartCondition(
              field: SmartField.liked,
              op: SmartOp.isValue,
              value: 'true',
            ),
          ],
        ),
        tracks: [_track('t1', 'First')],
      );

  @override
  Future<SmartRefreshResult> refresh(String playlistId) async =>
      const SmartRefreshResult(added: 0, refreshedAt: 0, removed: 0, total: 1);

  @override
  Future<SmartPlaylist> create(SmartBody body) async {
    saved.add(body);
    return SmartPlaylist(
      createdAt: 0,
      id: 's-new',
      name: body.name,
      rules: body.rules ?? const SmartRules(),
    );
  }

  @override
  Future<void> update(String playlistId, SmartBody body) async =>
      saved.add(body);

  @override
  Future<void> delete(String playlistId) async => deleted.add(playlistId);

  @override
  Future<SmartPreview> preview(SmartRules rules) async =>
      const SmartPreview(count: 0, sample: []);
}
