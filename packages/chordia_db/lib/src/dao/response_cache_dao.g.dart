// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'response_cache_dao.dart';

// ignore_for_file: type=lint
mixin _$ResponseCacheDaoMixin on DatabaseAccessor<ChordiaDatabase> {
  $ResponseCacheTable get responseCache => attachedDatabase.responseCache;
  ResponseCacheDaoManager get managers => ResponseCacheDaoManager(this);
}

class ResponseCacheDaoManager {
  final _$ResponseCacheDaoMixin _db;
  ResponseCacheDaoManager(this._db);
  $$ResponseCacheTableTableManager get responseCache =>
      $$ResponseCacheTableTableManager(_db.attachedDatabase, _db.responseCache);
}
