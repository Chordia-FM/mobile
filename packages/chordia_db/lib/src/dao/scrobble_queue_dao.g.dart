// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scrobble_queue_dao.dart';

// ignore_for_file: type=lint
mixin _$ScrobbleQueueDaoMixin on DatabaseAccessor<ChordiaDatabase> {
  $ScrobbleQueueTable get scrobbleQueue => attachedDatabase.scrobbleQueue;
  ScrobbleQueueDaoManager get managers => ScrobbleQueueDaoManager(this);
}

class ScrobbleQueueDaoManager {
  final _$ScrobbleQueueDaoMixin _db;
  ScrobbleQueueDaoManager(this._db);
  $$ScrobbleQueueTableTableManager get scrobbleQueue =>
      $$ScrobbleQueueTableTableManager(_db.attachedDatabase, _db.scrobbleQueue);
}
