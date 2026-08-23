import 'dart:async';
import 'dart:convert';

import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/features/playlists/data/collaborators_controller.dart';
import 'package:chordia_mobile/features/playlists/data/playlists_api.dart';
import 'package:chordia_mobile/features/playlists/data/smart_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  final added = <String>[];
  final removed = <String>[];
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
  Future<void> addTrack(String playlistId, String trackId) =>
      throw UnimplementedError();

  @override
  Future<void> clearCover(String playlistId) => throw UnimplementedError();

  @override
  Future<Playlist> create(CreatePlaylistRequest request) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String playlistId) => throw UnimplementedError();

  @override
  Future<List<Playlist>> playlists() => throw UnimplementedError();

  @override
  Future<void> setCover(String playlistId, String hash) =>
      throw UnimplementedError();

  @override
  Future<void> update(String playlistId, PlaylistPatch changes) =>
      throw UnimplementedError();

  @override
  Future<String> uploadImage(List<int> bytes) => throw UnimplementedError();
}
