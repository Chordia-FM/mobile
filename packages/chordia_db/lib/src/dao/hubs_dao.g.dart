// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hubs_dao.dart';

// ignore_for_file: type=lint
mixin _$HubsDaoMixin on DatabaseAccessor<ChordiaDatabase> {
  $HubsTable get hubs => attachedDatabase.hubs;
  HubsDaoManager get managers => HubsDaoManager(this);
}

class HubsDaoManager {
  final _$HubsDaoMixin _db;
  HubsDaoManager(this._db);
  $$HubsTableTableManager get hubs =>
      $$HubsTableTableManager(_db.attachedDatabase, _db.hubs);
}
