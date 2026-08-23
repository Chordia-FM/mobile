// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kv_dao.dart';

// ignore_for_file: type=lint
mixin _$KvDaoMixin on DatabaseAccessor<ChordiaDatabase> {
  $KeyValuesTable get keyValues => attachedDatabase.keyValues;
  KvDaoManager get managers => KvDaoManager(this);
}

class KvDaoManager {
  final _$KvDaoMixin _db;
  KvDaoManager(this._db);
  $$KeyValuesTableTableManager get keyValues =>
      $$KeyValuesTableTableManager(_db.attachedDatabase, _db.keyValues);
}
