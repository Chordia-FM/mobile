// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_tasks_dao.dart';

// ignore_for_file: type=lint
mixin _$DownloadTasksDaoMixin on DatabaseAccessor<ChordiaDatabase> {
  $DownloadTasksTable get downloadTasks => attachedDatabase.downloadTasks;
  DownloadTasksDaoManager get managers => DownloadTasksDaoManager(this);
}

class DownloadTasksDaoManager {
  final _$DownloadTasksDaoMixin _db;
  DownloadTasksDaoManager(this._db);
  $$DownloadTasksTableTableManager get downloadTasks =>
      $$DownloadTasksTableTableManager(_db.attachedDatabase, _db.downloadTasks);
}
