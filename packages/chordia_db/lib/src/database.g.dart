// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $HubsTable extends Hubs with TableInfo<$HubsTable, Hub> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HubsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _apiBaseMeta = const VerificationMeta(
    'apiBase',
  );
  @override
  late final GeneratedColumn<String> apiBase = GeneratedColumn<String>(
    'api_base',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _frontendUrlMeta = const VerificationMeta(
    'frontendUrl',
  );
  @override
  late final GeneratedColumn<String> frontendUrl = GeneratedColumn<String>(
    'frontend_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    apiBase,
    frontendUrl,
    addedAt,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hubs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Hub> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('api_base')) {
      context.handle(
        _apiBaseMeta,
        apiBase.isAcceptableOrUnknown(data['api_base']!, _apiBaseMeta),
      );
    } else if (isInserting) {
      context.missing(_apiBaseMeta);
    }
    if (data.containsKey('frontend_url')) {
      context.handle(
        _frontendUrlMeta,
        frontendUrl.isAcceptableOrUnknown(
          data['frontend_url']!,
          _frontendUrlMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Hub map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Hub(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      apiBase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}api_base'],
      )!,
      frontendUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}frontend_url'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $HubsTable createAlias(String alias) {
    return $HubsTable(attachedDatabase, alias);
  }
}

class Hub extends DataClass implements Insertable<Hub> {
  /// The Hub's own id, so the same Hub reached through two URLs is still one row.
  final String id;

  /// What the Hub calls itself, for the switcher.
  final String name;

  /// Origin of the control-plane API, e.g. `https://hub.example.com`.
  final String apiBase;

  /// Origin of the Hub's web client, used to build shareable links.
  ///
  /// Nullable because a Hub deployed API-only has no web client to point at, and a share sheet
  /// that offers a dead link is worse than one that offers no link.
  final String? frontendUrl;

  /// Epoch milliseconds, like every timestamp Chordia stores.
  final int addedAt;

  /// At most one row may hold true; `HubsDao.setActive` is what keeps that so.
  final bool isActive;
  const Hub({
    required this.id,
    required this.name,
    required this.apiBase,
    this.frontendUrl,
    required this.addedAt,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['api_base'] = Variable<String>(apiBase);
    if (!nullToAbsent || frontendUrl != null) {
      map['frontend_url'] = Variable<String>(frontendUrl);
    }
    map['added_at'] = Variable<int>(addedAt);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  HubsCompanion toCompanion(bool nullToAbsent) {
    return HubsCompanion(
      id: Value(id),
      name: Value(name),
      apiBase: Value(apiBase),
      frontendUrl: frontendUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(frontendUrl),
      addedAt: Value(addedAt),
      isActive: Value(isActive),
    );
  }

  factory Hub.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Hub(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      apiBase: serializer.fromJson<String>(json['apiBase']),
      frontendUrl: serializer.fromJson<String?>(json['frontendUrl']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'apiBase': serializer.toJson<String>(apiBase),
      'frontendUrl': serializer.toJson<String?>(frontendUrl),
      'addedAt': serializer.toJson<int>(addedAt),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  Hub copyWith({
    String? id,
    String? name,
    String? apiBase,
    Value<String?> frontendUrl = const Value.absent(),
    int? addedAt,
    bool? isActive,
  }) => Hub(
    id: id ?? this.id,
    name: name ?? this.name,
    apiBase: apiBase ?? this.apiBase,
    frontendUrl: frontendUrl.present ? frontendUrl.value : this.frontendUrl,
    addedAt: addedAt ?? this.addedAt,
    isActive: isActive ?? this.isActive,
  );
  Hub copyWithCompanion(HubsCompanion data) {
    return Hub(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      apiBase: data.apiBase.present ? data.apiBase.value : this.apiBase,
      frontendUrl: data.frontendUrl.present
          ? data.frontendUrl.value
          : this.frontendUrl,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Hub(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('apiBase: $apiBase, ')
          ..write('frontendUrl: $frontendUrl, ')
          ..write('addedAt: $addedAt, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, apiBase, frontendUrl, addedAt, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Hub &&
          other.id == this.id &&
          other.name == this.name &&
          other.apiBase == this.apiBase &&
          other.frontendUrl == this.frontendUrl &&
          other.addedAt == this.addedAt &&
          other.isActive == this.isActive);
}

class HubsCompanion extends UpdateCompanion<Hub> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> apiBase;
  final Value<String?> frontendUrl;
  final Value<int> addedAt;
  final Value<bool> isActive;
  final Value<int> rowid;
  const HubsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.apiBase = const Value.absent(),
    this.frontendUrl = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HubsCompanion.insert({
    required String id,
    required String name,
    required String apiBase,
    this.frontendUrl = const Value.absent(),
    required int addedAt,
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       apiBase = Value(apiBase),
       addedAt = Value(addedAt);
  static Insertable<Hub> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? apiBase,
    Expression<String>? frontendUrl,
    Expression<int>? addedAt,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (apiBase != null) 'api_base': apiBase,
      if (frontendUrl != null) 'frontend_url': frontendUrl,
      if (addedAt != null) 'added_at': addedAt,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HubsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? apiBase,
    Value<String?>? frontendUrl,
    Value<int>? addedAt,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return HubsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      apiBase: apiBase ?? this.apiBase,
      frontendUrl: frontendUrl ?? this.frontendUrl,
      addedAt: addedAt ?? this.addedAt,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (apiBase.present) {
      map['api_base'] = Variable<String>(apiBase.value);
    }
    if (frontendUrl.present) {
      map['frontend_url'] = Variable<String>(frontendUrl.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HubsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('apiBase: $apiBase, ')
          ..write('frontendUrl: $frontendUrl, ')
          ..write('addedAt: $addedAt, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadsTable extends Downloads
    with TableInfo<$DownloadsTable, DownloadedTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _libraryIdMeta = const VerificationMeta(
    'libraryId',
  );
  @override
  late final GeneratedColumn<String> libraryId = GeneratedColumn<String>(
    'library_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackRefMeta = const VerificationMeta(
    'trackRef',
  );
  @override
  late final GeneratedColumn<String> trackRef = GeneratedColumn<String>(
    'track_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileMeta = const VerificationMeta(
    'profile',
  );
  @override
  late final GeneratedColumn<String> profile = GeneratedColumn<String>(
    'profile',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<int> savedAt = GeneratedColumn<int>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistsJsonMeta = const VerificationMeta(
    'artistsJson',
  );
  @override
  late final GeneratedColumn<String> artistsJson = GeneratedColumn<String>(
    'artists_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverShaMeta = const VerificationMeta(
    'coverSha',
  );
  @override
  late final GeneratedColumn<String> coverSha = GeneratedColumn<String>(
    'cover_sha',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _advisoryMeta = const VerificationMeta(
    'advisory',
  );
  @override
  late final GeneratedColumn<String> advisory = GeneratedColumn<String>(
    'advisory',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _variantsJsonMeta = const VerificationMeta(
    'variantsJson',
  );
  @override
  late final GeneratedColumn<String> variantsJson = GeneratedColumn<String>(
    'variants_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackNoMeta = const VerificationMeta(
    'trackNo',
  );
  @override
  late final GeneratedColumn<int> trackNo = GeneratedColumn<int>(
    'track_no',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discNoMeta = const VerificationMeta('discNo');
  @override
  late final GeneratedColumn<int> discNo = GeneratedColumn<int>(
    'disc_no',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    trackId,
    libraryId,
    trackRef,
    contentHash,
    profile,
    filePath,
    sizeBytes,
    savedAt,
    title,
    artist,
    artistsJson,
    album,
    albumId,
    durationMs,
    coverSha,
    advisory,
    variantsJson,
    trackNo,
    discNo,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'downloads';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadedTrack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('library_id')) {
      context.handle(
        _libraryIdMeta,
        libraryId.isAcceptableOrUnknown(data['library_id']!, _libraryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_libraryIdMeta);
    }
    if (data.containsKey('track_ref')) {
      context.handle(
        _trackRefMeta,
        trackRef.isAcceptableOrUnknown(data['track_ref']!, _trackRefMeta),
      );
    } else if (isInserting) {
      context.missing(_trackRefMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('profile')) {
      context.handle(
        _profileMeta,
        profile.isAcceptableOrUnknown(data['profile']!, _profileMeta),
      );
    } else if (isInserting) {
      context.missing(_profileMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('artists_json')) {
      context.handle(
        _artistsJsonMeta,
        artistsJson.isAcceptableOrUnknown(
          data['artists_json']!,
          _artistsJsonMeta,
        ),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('cover_sha')) {
      context.handle(
        _coverShaMeta,
        coverSha.isAcceptableOrUnknown(data['cover_sha']!, _coverShaMeta),
      );
    }
    if (data.containsKey('advisory')) {
      context.handle(
        _advisoryMeta,
        advisory.isAcceptableOrUnknown(data['advisory']!, _advisoryMeta),
      );
    }
    if (data.containsKey('variants_json')) {
      context.handle(
        _variantsJsonMeta,
        variantsJson.isAcceptableOrUnknown(
          data['variants_json']!,
          _variantsJsonMeta,
        ),
      );
    }
    if (data.containsKey('track_no')) {
      context.handle(
        _trackNoMeta,
        trackNo.isAcceptableOrUnknown(data['track_no']!, _trackNoMeta),
      );
    }
    if (data.containsKey('disc_no')) {
      context.handle(
        _discNoMeta,
        discNo.isAcceptableOrUnknown(data['disc_no']!, _discNoMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackId};
  @override
  DownloadedTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadedTrack(
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      libraryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}library_id'],
      )!,
      trackRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_ref'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      profile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}saved_at'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      artistsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artists_json'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      coverSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_sha'],
      ),
      advisory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}advisory'],
      ),
      variantsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variants_json'],
      ),
      trackNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_no'],
      ),
      discNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}disc_no'],
      ),
    );
  }

  @override
  $DownloadsTable createAlias(String alias) {
    return $DownloadsTable(attachedDatabase, alias);
  }
}

class DownloadedTrack extends DataClass implements Insertable<DownloadedTrack> {
  /// The Hub's catalog id for the track — the id every other surface in the app keys on.
  final String trackId;

  /// The library the audio came from, kept so a re-download can go straight to the right server.
  final String libraryId;

  /// That library's own id for the track, which is what stream URLs are built from.
  final String trackRef;

  /// SHA-256 of the source file, so a re-scan that moves the file can still recognise it.
  final String contentHash;

  /// Quality profile the bytes were fetched at: `original`, `high`, `normal` or `data_saver`.
  ///
  /// Stored as the wire string rather than a Dart enum so this package stays independent of the
  /// generated API models, and so an unknown future profile round-trips instead of throwing.
  final String profile;

  /// Absolute path of the audio file on this device.
  final String filePath;
  final int sizeBytes;

  /// Epoch milliseconds the download completed.
  final int savedAt;
  final String title;

  /// The full credited-artist line ("X feat. Y"), already assembled by the Hub.
  final String artist;

  /// The credited artists as a JSON array of `ArtistRef`, for per-artist navigation offline.
  final String? artistsJson;
  final String? album;
  final String? albumId;
  final int durationMs;

  /// Hash half of the Hub's `/v1/images/{hash}` cover URL, so artwork resolves from the image
  /// cache without first re-fetching the track.
  final String? coverSha;

  /// Content advisory from the file's rating tag: `explicit`, `clean`, or null when unrated.
  final String? advisory;

  /// Title markers the Hub lifted out of the title (`live`, `remaster`, …) as a JSON array.
  ///
  /// Without these an offline row renders a bare title where the online one badges the recording,
  /// which reads as two different tracks.
  final String? variantsJson;
  final int? trackNo;
  final int? discNo;
  const DownloadedTrack({
    required this.trackId,
    required this.libraryId,
    required this.trackRef,
    required this.contentHash,
    required this.profile,
    required this.filePath,
    required this.sizeBytes,
    required this.savedAt,
    required this.title,
    required this.artist,
    this.artistsJson,
    this.album,
    this.albumId,
    required this.durationMs,
    this.coverSha,
    this.advisory,
    this.variantsJson,
    this.trackNo,
    this.discNo,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_id'] = Variable<String>(trackId);
    map['library_id'] = Variable<String>(libraryId);
    map['track_ref'] = Variable<String>(trackRef);
    map['content_hash'] = Variable<String>(contentHash);
    map['profile'] = Variable<String>(profile);
    map['file_path'] = Variable<String>(filePath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['saved_at'] = Variable<int>(savedAt);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || artistsJson != null) {
      map['artists_json'] = Variable<String>(artistsJson);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || albumId != null) {
      map['album_id'] = Variable<String>(albumId);
    }
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || coverSha != null) {
      map['cover_sha'] = Variable<String>(coverSha);
    }
    if (!nullToAbsent || advisory != null) {
      map['advisory'] = Variable<String>(advisory);
    }
    if (!nullToAbsent || variantsJson != null) {
      map['variants_json'] = Variable<String>(variantsJson);
    }
    if (!nullToAbsent || trackNo != null) {
      map['track_no'] = Variable<int>(trackNo);
    }
    if (!nullToAbsent || discNo != null) {
      map['disc_no'] = Variable<int>(discNo);
    }
    return map;
  }

  DownloadsCompanion toCompanion(bool nullToAbsent) {
    return DownloadsCompanion(
      trackId: Value(trackId),
      libraryId: Value(libraryId),
      trackRef: Value(trackRef),
      contentHash: Value(contentHash),
      profile: Value(profile),
      filePath: Value(filePath),
      sizeBytes: Value(sizeBytes),
      savedAt: Value(savedAt),
      title: Value(title),
      artist: Value(artist),
      artistsJson: artistsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(artistsJson),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      albumId: albumId == null && nullToAbsent
          ? const Value.absent()
          : Value(albumId),
      durationMs: Value(durationMs),
      coverSha: coverSha == null && nullToAbsent
          ? const Value.absent()
          : Value(coverSha),
      advisory: advisory == null && nullToAbsent
          ? const Value.absent()
          : Value(advisory),
      variantsJson: variantsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(variantsJson),
      trackNo: trackNo == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNo),
      discNo: discNo == null && nullToAbsent
          ? const Value.absent()
          : Value(discNo),
    );
  }

  factory DownloadedTrack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadedTrack(
      trackId: serializer.fromJson<String>(json['trackId']),
      libraryId: serializer.fromJson<String>(json['libraryId']),
      trackRef: serializer.fromJson<String>(json['trackRef']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      profile: serializer.fromJson<String>(json['profile']),
      filePath: serializer.fromJson<String>(json['filePath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      savedAt: serializer.fromJson<int>(json['savedAt']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      artistsJson: serializer.fromJson<String?>(json['artistsJson']),
      album: serializer.fromJson<String?>(json['album']),
      albumId: serializer.fromJson<String?>(json['albumId']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      coverSha: serializer.fromJson<String?>(json['coverSha']),
      advisory: serializer.fromJson<String?>(json['advisory']),
      variantsJson: serializer.fromJson<String?>(json['variantsJson']),
      trackNo: serializer.fromJson<int?>(json['trackNo']),
      discNo: serializer.fromJson<int?>(json['discNo']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackId': serializer.toJson<String>(trackId),
      'libraryId': serializer.toJson<String>(libraryId),
      'trackRef': serializer.toJson<String>(trackRef),
      'contentHash': serializer.toJson<String>(contentHash),
      'profile': serializer.toJson<String>(profile),
      'filePath': serializer.toJson<String>(filePath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'savedAt': serializer.toJson<int>(savedAt),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'artistsJson': serializer.toJson<String?>(artistsJson),
      'album': serializer.toJson<String?>(album),
      'albumId': serializer.toJson<String?>(albumId),
      'durationMs': serializer.toJson<int>(durationMs),
      'coverSha': serializer.toJson<String?>(coverSha),
      'advisory': serializer.toJson<String?>(advisory),
      'variantsJson': serializer.toJson<String?>(variantsJson),
      'trackNo': serializer.toJson<int?>(trackNo),
      'discNo': serializer.toJson<int?>(discNo),
    };
  }

  DownloadedTrack copyWith({
    String? trackId,
    String? libraryId,
    String? trackRef,
    String? contentHash,
    String? profile,
    String? filePath,
    int? sizeBytes,
    int? savedAt,
    String? title,
    String? artist,
    Value<String?> artistsJson = const Value.absent(),
    Value<String?> album = const Value.absent(),
    Value<String?> albumId = const Value.absent(),
    int? durationMs,
    Value<String?> coverSha = const Value.absent(),
    Value<String?> advisory = const Value.absent(),
    Value<String?> variantsJson = const Value.absent(),
    Value<int?> trackNo = const Value.absent(),
    Value<int?> discNo = const Value.absent(),
  }) => DownloadedTrack(
    trackId: trackId ?? this.trackId,
    libraryId: libraryId ?? this.libraryId,
    trackRef: trackRef ?? this.trackRef,
    contentHash: contentHash ?? this.contentHash,
    profile: profile ?? this.profile,
    filePath: filePath ?? this.filePath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    savedAt: savedAt ?? this.savedAt,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    artistsJson: artistsJson.present ? artistsJson.value : this.artistsJson,
    album: album.present ? album.value : this.album,
    albumId: albumId.present ? albumId.value : this.albumId,
    durationMs: durationMs ?? this.durationMs,
    coverSha: coverSha.present ? coverSha.value : this.coverSha,
    advisory: advisory.present ? advisory.value : this.advisory,
    variantsJson: variantsJson.present ? variantsJson.value : this.variantsJson,
    trackNo: trackNo.present ? trackNo.value : this.trackNo,
    discNo: discNo.present ? discNo.value : this.discNo,
  );
  DownloadedTrack copyWithCompanion(DownloadsCompanion data) {
    return DownloadedTrack(
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      libraryId: data.libraryId.present ? data.libraryId.value : this.libraryId,
      trackRef: data.trackRef.present ? data.trackRef.value : this.trackRef,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      profile: data.profile.present ? data.profile.value : this.profile,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      artistsJson: data.artistsJson.present
          ? data.artistsJson.value
          : this.artistsJson,
      album: data.album.present ? data.album.value : this.album,
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      coverSha: data.coverSha.present ? data.coverSha.value : this.coverSha,
      advisory: data.advisory.present ? data.advisory.value : this.advisory,
      variantsJson: data.variantsJson.present
          ? data.variantsJson.value
          : this.variantsJson,
      trackNo: data.trackNo.present ? data.trackNo.value : this.trackNo,
      discNo: data.discNo.present ? data.discNo.value : this.discNo,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadedTrack(')
          ..write('trackId: $trackId, ')
          ..write('libraryId: $libraryId, ')
          ..write('trackRef: $trackRef, ')
          ..write('contentHash: $contentHash, ')
          ..write('profile: $profile, ')
          ..write('filePath: $filePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('savedAt: $savedAt, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistsJson: $artistsJson, ')
          ..write('album: $album, ')
          ..write('albumId: $albumId, ')
          ..write('durationMs: $durationMs, ')
          ..write('coverSha: $coverSha, ')
          ..write('advisory: $advisory, ')
          ..write('variantsJson: $variantsJson, ')
          ..write('trackNo: $trackNo, ')
          ..write('discNo: $discNo')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    trackId,
    libraryId,
    trackRef,
    contentHash,
    profile,
    filePath,
    sizeBytes,
    savedAt,
    title,
    artist,
    artistsJson,
    album,
    albumId,
    durationMs,
    coverSha,
    advisory,
    variantsJson,
    trackNo,
    discNo,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadedTrack &&
          other.trackId == this.trackId &&
          other.libraryId == this.libraryId &&
          other.trackRef == this.trackRef &&
          other.contentHash == this.contentHash &&
          other.profile == this.profile &&
          other.filePath == this.filePath &&
          other.sizeBytes == this.sizeBytes &&
          other.savedAt == this.savedAt &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.artistsJson == this.artistsJson &&
          other.album == this.album &&
          other.albumId == this.albumId &&
          other.durationMs == this.durationMs &&
          other.coverSha == this.coverSha &&
          other.advisory == this.advisory &&
          other.variantsJson == this.variantsJson &&
          other.trackNo == this.trackNo &&
          other.discNo == this.discNo);
}

class DownloadsCompanion extends UpdateCompanion<DownloadedTrack> {
  final Value<String> trackId;
  final Value<String> libraryId;
  final Value<String> trackRef;
  final Value<String> contentHash;
  final Value<String> profile;
  final Value<String> filePath;
  final Value<int> sizeBytes;
  final Value<int> savedAt;
  final Value<String> title;
  final Value<String> artist;
  final Value<String?> artistsJson;
  final Value<String?> album;
  final Value<String?> albumId;
  final Value<int> durationMs;
  final Value<String?> coverSha;
  final Value<String?> advisory;
  final Value<String?> variantsJson;
  final Value<int?> trackNo;
  final Value<int?> discNo;
  final Value<int> rowid;
  const DownloadsCompanion({
    this.trackId = const Value.absent(),
    this.libraryId = const Value.absent(),
    this.trackRef = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.profile = const Value.absent(),
    this.filePath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.artistsJson = const Value.absent(),
    this.album = const Value.absent(),
    this.albumId = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.coverSha = const Value.absent(),
    this.advisory = const Value.absent(),
    this.variantsJson = const Value.absent(),
    this.trackNo = const Value.absent(),
    this.discNo = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadsCompanion.insert({
    required String trackId,
    required String libraryId,
    required String trackRef,
    required String contentHash,
    required String profile,
    required String filePath,
    required int sizeBytes,
    required int savedAt,
    required String title,
    required String artist,
    this.artistsJson = const Value.absent(),
    this.album = const Value.absent(),
    this.albumId = const Value.absent(),
    required int durationMs,
    this.coverSha = const Value.absent(),
    this.advisory = const Value.absent(),
    this.variantsJson = const Value.absent(),
    this.trackNo = const Value.absent(),
    this.discNo = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : trackId = Value(trackId),
       libraryId = Value(libraryId),
       trackRef = Value(trackRef),
       contentHash = Value(contentHash),
       profile = Value(profile),
       filePath = Value(filePath),
       sizeBytes = Value(sizeBytes),
       savedAt = Value(savedAt),
       title = Value(title),
       artist = Value(artist),
       durationMs = Value(durationMs);
  static Insertable<DownloadedTrack> custom({
    Expression<String>? trackId,
    Expression<String>? libraryId,
    Expression<String>? trackRef,
    Expression<String>? contentHash,
    Expression<String>? profile,
    Expression<String>? filePath,
    Expression<int>? sizeBytes,
    Expression<int>? savedAt,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? artistsJson,
    Expression<String>? album,
    Expression<String>? albumId,
    Expression<int>? durationMs,
    Expression<String>? coverSha,
    Expression<String>? advisory,
    Expression<String>? variantsJson,
    Expression<int>? trackNo,
    Expression<int>? discNo,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackId != null) 'track_id': trackId,
      if (libraryId != null) 'library_id': libraryId,
      if (trackRef != null) 'track_ref': trackRef,
      if (contentHash != null) 'content_hash': contentHash,
      if (profile != null) 'profile': profile,
      if (filePath != null) 'file_path': filePath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (savedAt != null) 'saved_at': savedAt,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (artistsJson != null) 'artists_json': artistsJson,
      if (album != null) 'album': album,
      if (albumId != null) 'album_id': albumId,
      if (durationMs != null) 'duration_ms': durationMs,
      if (coverSha != null) 'cover_sha': coverSha,
      if (advisory != null) 'advisory': advisory,
      if (variantsJson != null) 'variants_json': variantsJson,
      if (trackNo != null) 'track_no': trackNo,
      if (discNo != null) 'disc_no': discNo,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadsCompanion copyWith({
    Value<String>? trackId,
    Value<String>? libraryId,
    Value<String>? trackRef,
    Value<String>? contentHash,
    Value<String>? profile,
    Value<String>? filePath,
    Value<int>? sizeBytes,
    Value<int>? savedAt,
    Value<String>? title,
    Value<String>? artist,
    Value<String?>? artistsJson,
    Value<String?>? album,
    Value<String?>? albumId,
    Value<int>? durationMs,
    Value<String?>? coverSha,
    Value<String?>? advisory,
    Value<String?>? variantsJson,
    Value<int?>? trackNo,
    Value<int?>? discNo,
    Value<int>? rowid,
  }) {
    return DownloadsCompanion(
      trackId: trackId ?? this.trackId,
      libraryId: libraryId ?? this.libraryId,
      trackRef: trackRef ?? this.trackRef,
      contentHash: contentHash ?? this.contentHash,
      profile: profile ?? this.profile,
      filePath: filePath ?? this.filePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      savedAt: savedAt ?? this.savedAt,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artistsJson: artistsJson ?? this.artistsJson,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      durationMs: durationMs ?? this.durationMs,
      coverSha: coverSha ?? this.coverSha,
      advisory: advisory ?? this.advisory,
      variantsJson: variantsJson ?? this.variantsJson,
      trackNo: trackNo ?? this.trackNo,
      discNo: discNo ?? this.discNo,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (libraryId.present) {
      map['library_id'] = Variable<String>(libraryId.value);
    }
    if (trackRef.present) {
      map['track_ref'] = Variable<String>(trackRef.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (profile.present) {
      map['profile'] = Variable<String>(profile.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<int>(savedAt.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (artistsJson.present) {
      map['artists_json'] = Variable<String>(artistsJson.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (coverSha.present) {
      map['cover_sha'] = Variable<String>(coverSha.value);
    }
    if (advisory.present) {
      map['advisory'] = Variable<String>(advisory.value);
    }
    if (variantsJson.present) {
      map['variants_json'] = Variable<String>(variantsJson.value);
    }
    if (trackNo.present) {
      map['track_no'] = Variable<int>(trackNo.value);
    }
    if (discNo.present) {
      map['disc_no'] = Variable<int>(discNo.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadsCompanion(')
          ..write('trackId: $trackId, ')
          ..write('libraryId: $libraryId, ')
          ..write('trackRef: $trackRef, ')
          ..write('contentHash: $contentHash, ')
          ..write('profile: $profile, ')
          ..write('filePath: $filePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('savedAt: $savedAt, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('artistsJson: $artistsJson, ')
          ..write('album: $album, ')
          ..write('albumId: $albumId, ')
          ..write('durationMs: $durationMs, ')
          ..write('coverSha: $coverSha, ')
          ..write('advisory: $advisory, ')
          ..write('variantsJson: $variantsJson, ')
          ..write('trackNo: $trackNo, ')
          ..write('discNo: $discNo, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadTasksTable extends DownloadTasks
    with TableInfo<$DownloadTasksTable, DownloadTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DownloadState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DownloadState>($DownloadTasksTable.$converterstate);
  static const VerificationMeta _bytesDoneMeta = const VerificationMeta(
    'bytesDone',
  );
  @override
  late final GeneratedColumn<int> bytesDone = GeneratedColumn<int>(
    'bytes_done',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    trackId,
    state,
    bytesDone,
    totalBytes,
    error,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('bytes_done')) {
      context.handle(
        _bytesDoneMeta,
        bytesDone.isAcceptableOrUnknown(data['bytes_done']!, _bytesDoneMeta),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DownloadTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadTask(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      state: $DownloadTasksTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      bytesDone: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_done'],
      )!,
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DownloadTasksTable createAlias(String alias) {
    return $DownloadTasksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DownloadState, String, String> $converterstate =
      const EnumNameConverter<DownloadState>(DownloadState.values);
}

class DownloadTask extends DataClass implements Insertable<DownloadTask> {
  final String id;
  final String trackId;
  final DownloadState state;

  /// Bytes already on disk — also the offset the next Range request resumes from.
  final int bytesDone;

  /// Zero until the server has told us the length.
  final int totalBytes;

  /// Why the last attempt failed, shown on the row so a retry is an informed choice.
  final String? error;
  final int createdAt;
  final int updatedAt;
  const DownloadTask({
    required this.id,
    required this.trackId,
    required this.state,
    required this.bytesDone,
    required this.totalBytes,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['track_id'] = Variable<String>(trackId);
    {
      map['state'] = Variable<String>(
        $DownloadTasksTable.$converterstate.toSql(state),
      );
    }
    map['bytes_done'] = Variable<int>(bytesDone);
    map['total_bytes'] = Variable<int>(totalBytes);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  DownloadTasksCompanion toCompanion(bool nullToAbsent) {
    return DownloadTasksCompanion(
      id: Value(id),
      trackId: Value(trackId),
      state: Value(state),
      bytesDone: Value(bytesDone),
      totalBytes: Value(totalBytes),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DownloadTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadTask(
      id: serializer.fromJson<String>(json['id']),
      trackId: serializer.fromJson<String>(json['trackId']),
      state: $DownloadTasksTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      bytesDone: serializer.fromJson<int>(json['bytesDone']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      error: serializer.fromJson<String?>(json['error']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'trackId': serializer.toJson<String>(trackId),
      'state': serializer.toJson<String>(
        $DownloadTasksTable.$converterstate.toJson(state),
      ),
      'bytesDone': serializer.toJson<int>(bytesDone),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'error': serializer.toJson<String?>(error),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  DownloadTask copyWith({
    String? id,
    String? trackId,
    DownloadState? state,
    int? bytesDone,
    int? totalBytes,
    Value<String?> error = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => DownloadTask(
    id: id ?? this.id,
    trackId: trackId ?? this.trackId,
    state: state ?? this.state,
    bytesDone: bytesDone ?? this.bytesDone,
    totalBytes: totalBytes ?? this.totalBytes,
    error: error.present ? error.value : this.error,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DownloadTask copyWithCompanion(DownloadTasksCompanion data) {
    return DownloadTask(
      id: data.id.present ? data.id.value : this.id,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      state: data.state.present ? data.state.value : this.state,
      bytesDone: data.bytesDone.present ? data.bytesDone.value : this.bytesDone,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      error: data.error.present ? data.error.value : this.error,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadTask(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('state: $state, ')
          ..write('bytesDone: $bytesDone, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    trackId,
    state,
    bytesDone,
    totalBytes,
    error,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadTask &&
          other.id == this.id &&
          other.trackId == this.trackId &&
          other.state == this.state &&
          other.bytesDone == this.bytesDone &&
          other.totalBytes == this.totalBytes &&
          other.error == this.error &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DownloadTasksCompanion extends UpdateCompanion<DownloadTask> {
  final Value<String> id;
  final Value<String> trackId;
  final Value<DownloadState> state;
  final Value<int> bytesDone;
  final Value<int> totalBytes;
  final Value<String?> error;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const DownloadTasksCompanion({
    this.id = const Value.absent(),
    this.trackId = const Value.absent(),
    this.state = const Value.absent(),
    this.bytesDone = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadTasksCompanion.insert({
    required String id,
    required String trackId,
    required DownloadState state,
    this.bytesDone = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.error = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       trackId = Value(trackId),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DownloadTask> custom({
    Expression<String>? id,
    Expression<String>? trackId,
    Expression<String>? state,
    Expression<int>? bytesDone,
    Expression<int>? totalBytes,
    Expression<String>? error,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackId != null) 'track_id': trackId,
      if (state != null) 'state': state,
      if (bytesDone != null) 'bytes_done': bytesDone,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (error != null) 'error': error,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? trackId,
    Value<DownloadState>? state,
    Value<int>? bytesDone,
    Value<int>? totalBytes,
    Value<String?>? error,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return DownloadTasksCompanion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      state: state ?? this.state,
      bytesDone: bytesDone ?? this.bytesDone,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $DownloadTasksTable.$converterstate.toSql(state.value),
      );
    }
    if (bytesDone.present) {
      map['bytes_done'] = Variable<int>(bytesDone.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DownloadTasksCompanion(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('state: $state, ')
          ..write('bytesDone: $bytesDone, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScrobbleQueueTable extends ScrobbleQueue
    with TableInfo<$ScrobbleQueueTable, QueuedScrobble> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScrobbleQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [eventId, payloadJson, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scrobble_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueuedScrobble> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  QueuedScrobble map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueuedScrobble(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ScrobbleQueueTable createAlias(String alias) {
    return $ScrobbleQueueTable(attachedDatabase, alias);
  }
}

class QueuedScrobble extends DataClass implements Insertable<QueuedScrobble> {
  /// The client-generated UUIDv7 that is also the Hub's idempotency key.
  ///
  /// Being the primary key means a double-enqueue of the same play is a no-op locally, and a batch
  /// that was delivered but whose response was lost is deduped again server-side on retry.
  final String eventId;

  /// The full `ListeningEvent` as JSON, posted through to `/v1/scrobbles:batch` untouched.
  ///
  /// Opaque here deliberately: the queue must keep accepting events written by an older build of
  /// the app after the event shape gains a field.
  final String payloadJson;

  /// Epoch milliseconds the event was queued — the drain and prune order.
  final int createdAt;
  const QueuedScrobble({
    required this.eventId,
    required this.payloadJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ScrobbleQueueCompanion toCompanion(bool nullToAbsent) {
    return ScrobbleQueueCompanion(
      eventId: Value(eventId),
      payloadJson: Value(payloadJson),
      createdAt: Value(createdAt),
    );
  }

  factory QueuedScrobble.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueuedScrobble(
      eventId: serializer.fromJson<String>(json['eventId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  QueuedScrobble copyWith({
    String? eventId,
    String? payloadJson,
    int? createdAt,
  }) => QueuedScrobble(
    eventId: eventId ?? this.eventId,
    payloadJson: payloadJson ?? this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
  );
  QueuedScrobble copyWithCompanion(ScrobbleQueueCompanion data) {
    return QueuedScrobble(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueuedScrobble(')
          ..write('eventId: $eventId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(eventId, payloadJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueuedScrobble &&
          other.eventId == this.eventId &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt);
}

class ScrobbleQueueCompanion extends UpdateCompanion<QueuedScrobble> {
  final Value<String> eventId;
  final Value<String> payloadJson;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ScrobbleQueueCompanion({
    this.eventId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScrobbleQueueCompanion.insert({
    required String eventId,
    required String payloadJson,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<QueuedScrobble> custom({
    Expression<String>? eventId,
    Expression<String>? payloadJson,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScrobbleQueueCompanion copyWith({
    Value<String>? eventId,
    Value<String>? payloadJson,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ScrobbleQueueCompanion(
      eventId: eventId ?? this.eventId,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScrobbleQueueCompanion(')
          ..write('eventId: $eventId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResponseCacheTable extends ResponseCache
    with TableInfo<$ResponseCacheTable, CachedResponse> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResponseCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyJsonMeta = const VerificationMeta(
    'bodyJson',
  );
  @override
  late final GeneratedColumn<String> bodyJson = GeneratedColumn<String>(
    'body_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _staleAtMeta = const VerificationMeta(
    'staleAt',
  );
  @override
  late final GeneratedColumn<int> staleAt = GeneratedColumn<int>(
    'stale_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, bodyJson, fetchedAt, staleAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'response_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedResponse> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('body_json')) {
      context.handle(
        _bodyJsonMeta,
        bodyJson.isAcceptableOrUnknown(data['body_json']!, _bodyJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyJsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('stale_at')) {
      context.handle(
        _staleAtMeta,
        staleAt.isAcceptableOrUnknown(data['stale_at']!, _staleAtMeta),
      );
    } else if (isInserting) {
      context.missing(_staleAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CachedResponse map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedResponse(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      bodyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      staleAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stale_at'],
      )!,
    );
  }

  @override
  $ResponseCacheTable createAlias(String alias) {
    return $ResponseCacheTable(attachedDatabase, alias);
  }
}

class CachedResponse extends DataClass implements Insertable<CachedResponse> {
  /// Cache key, conventionally the request's method, path and query.
  final String key;

  /// The response body, stored verbatim so the decoder is the same one the network path uses.
  final String bodyJson;

  /// Epoch milliseconds the response arrived.
  final int fetchedAt;

  /// Epoch milliseconds after which the body is served but revalidated in the background.
  final int staleAt;
  const CachedResponse({
    required this.key,
    required this.bodyJson,
    required this.fetchedAt,
    required this.staleAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['body_json'] = Variable<String>(bodyJson);
    map['fetched_at'] = Variable<int>(fetchedAt);
    map['stale_at'] = Variable<int>(staleAt);
    return map;
  }

  ResponseCacheCompanion toCompanion(bool nullToAbsent) {
    return ResponseCacheCompanion(
      key: Value(key),
      bodyJson: Value(bodyJson),
      fetchedAt: Value(fetchedAt),
      staleAt: Value(staleAt),
    );
  }

  factory CachedResponse.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedResponse(
      key: serializer.fromJson<String>(json['key']),
      bodyJson: serializer.fromJson<String>(json['bodyJson']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      staleAt: serializer.fromJson<int>(json['staleAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'bodyJson': serializer.toJson<String>(bodyJson),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'staleAt': serializer.toJson<int>(staleAt),
    };
  }

  CachedResponse copyWith({
    String? key,
    String? bodyJson,
    int? fetchedAt,
    int? staleAt,
  }) => CachedResponse(
    key: key ?? this.key,
    bodyJson: bodyJson ?? this.bodyJson,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    staleAt: staleAt ?? this.staleAt,
  );
  CachedResponse copyWithCompanion(ResponseCacheCompanion data) {
    return CachedResponse(
      key: data.key.present ? data.key.value : this.key,
      bodyJson: data.bodyJson.present ? data.bodyJson.value : this.bodyJson,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      staleAt: data.staleAt.present ? data.staleAt.value : this.staleAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedResponse(')
          ..write('key: $key, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('staleAt: $staleAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, bodyJson, fetchedAt, staleAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedResponse &&
          other.key == this.key &&
          other.bodyJson == this.bodyJson &&
          other.fetchedAt == this.fetchedAt &&
          other.staleAt == this.staleAt);
}

class ResponseCacheCompanion extends UpdateCompanion<CachedResponse> {
  final Value<String> key;
  final Value<String> bodyJson;
  final Value<int> fetchedAt;
  final Value<int> staleAt;
  final Value<int> rowid;
  const ResponseCacheCompanion({
    this.key = const Value.absent(),
    this.bodyJson = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.staleAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResponseCacheCompanion.insert({
    required String key,
    required String bodyJson,
    required int fetchedAt,
    required int staleAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       bodyJson = Value(bodyJson),
       fetchedAt = Value(fetchedAt),
       staleAt = Value(staleAt);
  static Insertable<CachedResponse> custom({
    Expression<String>? key,
    Expression<String>? bodyJson,
    Expression<int>? fetchedAt,
    Expression<int>? staleAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (bodyJson != null) 'body_json': bodyJson,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (staleAt != null) 'stale_at': staleAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResponseCacheCompanion copyWith({
    Value<String>? key,
    Value<String>? bodyJson,
    Value<int>? fetchedAt,
    Value<int>? staleAt,
    Value<int>? rowid,
  }) {
    return ResponseCacheCompanion(
      key: key ?? this.key,
      bodyJson: bodyJson ?? this.bodyJson,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      staleAt: staleAt ?? this.staleAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (bodyJson.present) {
      map['body_json'] = Variable<String>(bodyJson.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (staleAt.present) {
      map['stale_at'] = Variable<int>(staleAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResponseCacheCompanion(')
          ..write('key: $key, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('staleAt: $staleAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KeyValuesTable extends KeyValues
    with TableInfo<$KeyValuesTable, KvEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeyValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $KeyValuesTable createAlias(String alias) {
    return $KeyValuesTable(attachedDatabase, alias);
  }
}

class KvEntry extends DataClass implements Insertable<KvEntry> {
  final String key;
  final String value;
  const KvEntry({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KeyValuesCompanion toCompanion(bool nullToAbsent) {
    return KeyValuesCompanion(key: Value(key), value: Value(value));
  }

  factory KvEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  KvEntry copyWith({String? key, String? value}) =>
      KvEntry(key: key ?? this.key, value: value ?? this.value);
  KvEntry copyWithCompanion(KeyValuesCompanion data) {
    return KvEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvEntry(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvEntry && other.key == this.key && other.value == this.value);
}

class KeyValuesCompanion extends UpdateCompanion<KvEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KeyValuesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeyValuesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KvEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeyValuesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return KeyValuesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeyValuesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ChordiaDatabase extends GeneratedDatabase {
  _$ChordiaDatabase(QueryExecutor e) : super(e);
  $ChordiaDatabaseManager get managers => $ChordiaDatabaseManager(this);
  late final $HubsTable hubs = $HubsTable(this);
  late final $DownloadsTable downloads = $DownloadsTable(this);
  late final $DownloadTasksTable downloadTasks = $DownloadTasksTable(this);
  late final $ScrobbleQueueTable scrobbleQueue = $ScrobbleQueueTable(this);
  late final $ResponseCacheTable responseCache = $ResponseCacheTable(this);
  late final $KeyValuesTable keyValues = $KeyValuesTable(this);
  late final Index downloadsAlbumId = Index(
    'downloads_album_id',
    'CREATE INDEX downloads_album_id ON downloads (album_id)',
  );
  late final Index downloadsArtist = Index(
    'downloads_artist',
    'CREATE INDEX downloads_artist ON downloads (artist)',
  );
  late final Index downloadTasksState = Index(
    'download_tasks_state',
    'CREATE INDEX download_tasks_state ON download_tasks (state)',
  );
  late final Index downloadTasksTrackId = Index(
    'download_tasks_track_id',
    'CREATE INDEX download_tasks_track_id ON download_tasks (track_id)',
  );
  late final Index scrobbleQueueCreatedAt = Index(
    'scrobble_queue_created_at',
    'CREATE INDEX scrobble_queue_created_at ON scrobble_queue (created_at)',
  );
  late final HubsDao hubsDao = HubsDao(this as ChordiaDatabase);
  late final DownloadsDao downloadsDao = DownloadsDao(this as ChordiaDatabase);
  late final DownloadTasksDao downloadTasksDao = DownloadTasksDao(
    this as ChordiaDatabase,
  );
  late final ScrobbleQueueDao scrobbleQueueDao = ScrobbleQueueDao(
    this as ChordiaDatabase,
  );
  late final ResponseCacheDao responseCacheDao = ResponseCacheDao(
    this as ChordiaDatabase,
  );
  late final KvDao kvDao = KvDao(this as ChordiaDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    hubs,
    downloads,
    downloadTasks,
    scrobbleQueue,
    responseCache,
    keyValues,
    downloadsAlbumId,
    downloadsArtist,
    downloadTasksState,
    downloadTasksTrackId,
    scrobbleQueueCreatedAt,
  ];
}

typedef $$HubsTableCreateCompanionBuilder =
    HubsCompanion Function({
      required String id,
      required String name,
      required String apiBase,
      Value<String?> frontendUrl,
      required int addedAt,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$HubsTableUpdateCompanionBuilder =
    HubsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> apiBase,
      Value<String?> frontendUrl,
      Value<int> addedAt,
      Value<bool> isActive,
      Value<int> rowid,
    });

class $$HubsTableFilterComposer
    extends Composer<_$ChordiaDatabase, $HubsTable> {
  $$HubsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get apiBase => $composableBuilder(
    column: $table.apiBase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get frontendUrl => $composableBuilder(
    column: $table.frontendUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HubsTableOrderingComposer
    extends Composer<_$ChordiaDatabase, $HubsTable> {
  $$HubsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get apiBase => $composableBuilder(
    column: $table.apiBase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get frontendUrl => $composableBuilder(
    column: $table.frontendUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HubsTableAnnotationComposer
    extends Composer<_$ChordiaDatabase, $HubsTable> {
  $$HubsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get apiBase =>
      $composableBuilder(column: $table.apiBase, builder: (column) => column);

  GeneratedColumn<String> get frontendUrl => $composableBuilder(
    column: $table.frontendUrl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);
}

class $$HubsTableTableManager
    extends
        RootTableManager<
          _$ChordiaDatabase,
          $HubsTable,
          Hub,
          $$HubsTableFilterComposer,
          $$HubsTableOrderingComposer,
          $$HubsTableAnnotationComposer,
          $$HubsTableCreateCompanionBuilder,
          $$HubsTableUpdateCompanionBuilder,
          (Hub, BaseReferences<_$ChordiaDatabase, $HubsTable, Hub>),
          Hub,
          PrefetchHooks Function()
        > {
  $$HubsTableTableManager(_$ChordiaDatabase db, $HubsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HubsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HubsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HubsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> apiBase = const Value.absent(),
                Value<String?> frontendUrl = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HubsCompanion(
                id: id,
                name: name,
                apiBase: apiBase,
                frontendUrl: frontendUrl,
                addedAt: addedAt,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String apiBase,
                Value<String?> frontendUrl = const Value.absent(),
                required int addedAt,
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HubsCompanion.insert(
                id: id,
                name: name,
                apiBase: apiBase,
                frontendUrl: frontendUrl,
                addedAt: addedAt,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HubsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChordiaDatabase,
      $HubsTable,
      Hub,
      $$HubsTableFilterComposer,
      $$HubsTableOrderingComposer,
      $$HubsTableAnnotationComposer,
      $$HubsTableCreateCompanionBuilder,
      $$HubsTableUpdateCompanionBuilder,
      (Hub, BaseReferences<_$ChordiaDatabase, $HubsTable, Hub>),
      Hub,
      PrefetchHooks Function()
    >;
typedef $$DownloadsTableCreateCompanionBuilder =
    DownloadsCompanion Function({
      required String trackId,
      required String libraryId,
      required String trackRef,
      required String contentHash,
      required String profile,
      required String filePath,
      required int sizeBytes,
      required int savedAt,
      required String title,
      required String artist,
      Value<String?> artistsJson,
      Value<String?> album,
      Value<String?> albumId,
      required int durationMs,
      Value<String?> coverSha,
      Value<String?> advisory,
      Value<String?> variantsJson,
      Value<int?> trackNo,
      Value<int?> discNo,
      Value<int> rowid,
    });
typedef $$DownloadsTableUpdateCompanionBuilder =
    DownloadsCompanion Function({
      Value<String> trackId,
      Value<String> libraryId,
      Value<String> trackRef,
      Value<String> contentHash,
      Value<String> profile,
      Value<String> filePath,
      Value<int> sizeBytes,
      Value<int> savedAt,
      Value<String> title,
      Value<String> artist,
      Value<String?> artistsJson,
      Value<String?> album,
      Value<String?> albumId,
      Value<int> durationMs,
      Value<String?> coverSha,
      Value<String?> advisory,
      Value<String?> variantsJson,
      Value<int?> trackNo,
      Value<int?> discNo,
      Value<int> rowid,
    });

class $$DownloadsTableFilterComposer
    extends Composer<_$ChordiaDatabase, $DownloadsTable> {
  $$DownloadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get libraryId => $composableBuilder(
    column: $table.libraryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackRef => $composableBuilder(
    column: $table.trackRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artistsJson => $composableBuilder(
    column: $table.artistsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverSha => $composableBuilder(
    column: $table.coverSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get advisory => $composableBuilder(
    column: $table.advisory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variantsJson => $composableBuilder(
    column: $table.variantsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNo => $composableBuilder(
    column: $table.trackNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discNo => $composableBuilder(
    column: $table.discNo,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadsTableOrderingComposer
    extends Composer<_$ChordiaDatabase, $DownloadsTable> {
  $$DownloadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get libraryId => $composableBuilder(
    column: $table.libraryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackRef => $composableBuilder(
    column: $table.trackRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profile => $composableBuilder(
    column: $table.profile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artistsJson => $composableBuilder(
    column: $table.artistsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverSha => $composableBuilder(
    column: $table.coverSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get advisory => $composableBuilder(
    column: $table.advisory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variantsJson => $composableBuilder(
    column: $table.variantsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNo => $composableBuilder(
    column: $table.trackNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discNo => $composableBuilder(
    column: $table.discNo,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadsTableAnnotationComposer
    extends Composer<_$ChordiaDatabase, $DownloadsTable> {
  $$DownloadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get libraryId =>
      $composableBuilder(column: $table.libraryId, builder: (column) => column);

  GeneratedColumn<String> get trackRef =>
      $composableBuilder(column: $table.trackRef, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get profile =>
      $composableBuilder(column: $table.profile, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get artistsJson => $composableBuilder(
    column: $table.artistsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverSha =>
      $composableBuilder(column: $table.coverSha, builder: (column) => column);

  GeneratedColumn<String> get advisory =>
      $composableBuilder(column: $table.advisory, builder: (column) => column);

  GeneratedColumn<String> get variantsJson => $composableBuilder(
    column: $table.variantsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trackNo =>
      $composableBuilder(column: $table.trackNo, builder: (column) => column);

  GeneratedColumn<int> get discNo =>
      $composableBuilder(column: $table.discNo, builder: (column) => column);
}

class $$DownloadsTableTableManager
    extends
        RootTableManager<
          _$ChordiaDatabase,
          $DownloadsTable,
          DownloadedTrack,
          $$DownloadsTableFilterComposer,
          $$DownloadsTableOrderingComposer,
          $$DownloadsTableAnnotationComposer,
          $$DownloadsTableCreateCompanionBuilder,
          $$DownloadsTableUpdateCompanionBuilder,
          (
            DownloadedTrack,
            BaseReferences<_$ChordiaDatabase, $DownloadsTable, DownloadedTrack>,
          ),
          DownloadedTrack,
          PrefetchHooks Function()
        > {
  $$DownloadsTableTableManager(_$ChordiaDatabase db, $DownloadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> trackId = const Value.absent(),
                Value<String> libraryId = const Value.absent(),
                Value<String> trackRef = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<String> profile = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> savedAt = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String?> artistsJson = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String?> coverSha = const Value.absent(),
                Value<String?> advisory = const Value.absent(),
                Value<String?> variantsJson = const Value.absent(),
                Value<int?> trackNo = const Value.absent(),
                Value<int?> discNo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion(
                trackId: trackId,
                libraryId: libraryId,
                trackRef: trackRef,
                contentHash: contentHash,
                profile: profile,
                filePath: filePath,
                sizeBytes: sizeBytes,
                savedAt: savedAt,
                title: title,
                artist: artist,
                artistsJson: artistsJson,
                album: album,
                albumId: albumId,
                durationMs: durationMs,
                coverSha: coverSha,
                advisory: advisory,
                variantsJson: variantsJson,
                trackNo: trackNo,
                discNo: discNo,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackId,
                required String libraryId,
                required String trackRef,
                required String contentHash,
                required String profile,
                required String filePath,
                required int sizeBytes,
                required int savedAt,
                required String title,
                required String artist,
                Value<String?> artistsJson = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> albumId = const Value.absent(),
                required int durationMs,
                Value<String?> coverSha = const Value.absent(),
                Value<String?> advisory = const Value.absent(),
                Value<String?> variantsJson = const Value.absent(),
                Value<int?> trackNo = const Value.absent(),
                Value<int?> discNo = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadsCompanion.insert(
                trackId: trackId,
                libraryId: libraryId,
                trackRef: trackRef,
                contentHash: contentHash,
                profile: profile,
                filePath: filePath,
                sizeBytes: sizeBytes,
                savedAt: savedAt,
                title: title,
                artist: artist,
                artistsJson: artistsJson,
                album: album,
                albumId: albumId,
                durationMs: durationMs,
                coverSha: coverSha,
                advisory: advisory,
                variantsJson: variantsJson,
                trackNo: trackNo,
                discNo: discNo,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChordiaDatabase,
      $DownloadsTable,
      DownloadedTrack,
      $$DownloadsTableFilterComposer,
      $$DownloadsTableOrderingComposer,
      $$DownloadsTableAnnotationComposer,
      $$DownloadsTableCreateCompanionBuilder,
      $$DownloadsTableUpdateCompanionBuilder,
      (
        DownloadedTrack,
        BaseReferences<_$ChordiaDatabase, $DownloadsTable, DownloadedTrack>,
      ),
      DownloadedTrack,
      PrefetchHooks Function()
    >;
typedef $$DownloadTasksTableCreateCompanionBuilder =
    DownloadTasksCompanion Function({
      required String id,
      required String trackId,
      required DownloadState state,
      Value<int> bytesDone,
      Value<int> totalBytes,
      Value<String?> error,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$DownloadTasksTableUpdateCompanionBuilder =
    DownloadTasksCompanion Function({
      Value<String> id,
      Value<String> trackId,
      Value<DownloadState> state,
      Value<int> bytesDone,
      Value<int> totalBytes,
      Value<String?> error,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$DownloadTasksTableFilterComposer
    extends Composer<_$ChordiaDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DownloadState, DownloadState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get bytesDone => $composableBuilder(
    column: $table.bytesDone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadTasksTableOrderingComposer
    extends Composer<_$ChordiaDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesDone => $composableBuilder(
    column: $table.bytesDone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadTasksTableAnnotationComposer
    extends Composer<_$ChordiaDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DownloadState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get bytesDone =>
      $composableBuilder(column: $table.bytesDone, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DownloadTasksTableTableManager
    extends
        RootTableManager<
          _$ChordiaDatabase,
          $DownloadTasksTable,
          DownloadTask,
          $$DownloadTasksTableFilterComposer,
          $$DownloadTasksTableOrderingComposer,
          $$DownloadTasksTableAnnotationComposer,
          $$DownloadTasksTableCreateCompanionBuilder,
          $$DownloadTasksTableUpdateCompanionBuilder,
          (
            DownloadTask,
            BaseReferences<
              _$ChordiaDatabase,
              $DownloadTasksTable,
              DownloadTask
            >,
          ),
          DownloadTask,
          PrefetchHooks Function()
        > {
  $$DownloadTasksTableTableManager(
    _$ChordiaDatabase db,
    $DownloadTasksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<DownloadState> state = const Value.absent(),
                Value<int> bytesDone = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadTasksCompanion(
                id: id,
                trackId: trackId,
                state: state,
                bytesDone: bytesDone,
                totalBytes: totalBytes,
                error: error,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String trackId,
                required DownloadState state,
                Value<int> bytesDone = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<String?> error = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DownloadTasksCompanion.insert(
                id: id,
                trackId: trackId,
                state: state,
                bytesDone: bytesDone,
                totalBytes: totalBytes,
                error: error,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$ChordiaDatabase,
      $DownloadTasksTable,
      DownloadTask,
      $$DownloadTasksTableFilterComposer,
      $$DownloadTasksTableOrderingComposer,
      $$DownloadTasksTableAnnotationComposer,
      $$DownloadTasksTableCreateCompanionBuilder,
      $$DownloadTasksTableUpdateCompanionBuilder,
      (
        DownloadTask,
        BaseReferences<_$ChordiaDatabase, $DownloadTasksTable, DownloadTask>,
      ),
      DownloadTask,
      PrefetchHooks Function()
    >;
typedef $$ScrobbleQueueTableCreateCompanionBuilder =
    ScrobbleQueueCompanion Function({
      required String eventId,
      required String payloadJson,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$ScrobbleQueueTableUpdateCompanionBuilder =
    ScrobbleQueueCompanion Function({
      Value<String> eventId,
      Value<String> payloadJson,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$ScrobbleQueueTableFilterComposer
    extends Composer<_$ChordiaDatabase, $ScrobbleQueueTable> {
  $$ScrobbleQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScrobbleQueueTableOrderingComposer
    extends Composer<_$ChordiaDatabase, $ScrobbleQueueTable> {
  $$ScrobbleQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScrobbleQueueTableAnnotationComposer
    extends Composer<_$ChordiaDatabase, $ScrobbleQueueTable> {
  $$ScrobbleQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ScrobbleQueueTableTableManager
    extends
        RootTableManager<
          _$ChordiaDatabase,
          $ScrobbleQueueTable,
          QueuedScrobble,
          $$ScrobbleQueueTableFilterComposer,
          $$ScrobbleQueueTableOrderingComposer,
          $$ScrobbleQueueTableAnnotationComposer,
          $$ScrobbleQueueTableCreateCompanionBuilder,
          $$ScrobbleQueueTableUpdateCompanionBuilder,
          (
            QueuedScrobble,
            BaseReferences<
              _$ChordiaDatabase,
              $ScrobbleQueueTable,
              QueuedScrobble
            >,
          ),
          QueuedScrobble,
          PrefetchHooks Function()
        > {
  $$ScrobbleQueueTableTableManager(
    _$ChordiaDatabase db,
    $ScrobbleQueueTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScrobbleQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScrobbleQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScrobbleQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScrobbleQueueCompanion(
                eventId: eventId,
                payloadJson: payloadJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String payloadJson,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ScrobbleQueueCompanion.insert(
                eventId: eventId,
                payloadJson: payloadJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScrobbleQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$ChordiaDatabase,
      $ScrobbleQueueTable,
      QueuedScrobble,
      $$ScrobbleQueueTableFilterComposer,
      $$ScrobbleQueueTableOrderingComposer,
      $$ScrobbleQueueTableAnnotationComposer,
      $$ScrobbleQueueTableCreateCompanionBuilder,
      $$ScrobbleQueueTableUpdateCompanionBuilder,
      (
        QueuedScrobble,
        BaseReferences<_$ChordiaDatabase, $ScrobbleQueueTable, QueuedScrobble>,
      ),
      QueuedScrobble,
      PrefetchHooks Function()
    >;
typedef $$ResponseCacheTableCreateCompanionBuilder =
    ResponseCacheCompanion Function({
      required String key,
      required String bodyJson,
      required int fetchedAt,
      required int staleAt,
      Value<int> rowid,
    });
typedef $$ResponseCacheTableUpdateCompanionBuilder =
    ResponseCacheCompanion Function({
      Value<String> key,
      Value<String> bodyJson,
      Value<int> fetchedAt,
      Value<int> staleAt,
      Value<int> rowid,
    });

class $$ResponseCacheTableFilterComposer
    extends Composer<_$ChordiaDatabase, $ResponseCacheTable> {
  $$ResponseCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get staleAt => $composableBuilder(
    column: $table.staleAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ResponseCacheTableOrderingComposer
    extends Composer<_$ChordiaDatabase, $ResponseCacheTable> {
  $$ResponseCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get staleAt => $composableBuilder(
    column: $table.staleAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ResponseCacheTableAnnotationComposer
    extends Composer<_$ChordiaDatabase, $ResponseCacheTable> {
  $$ResponseCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get bodyJson =>
      $composableBuilder(column: $table.bodyJson, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get staleAt =>
      $composableBuilder(column: $table.staleAt, builder: (column) => column);
}

class $$ResponseCacheTableTableManager
    extends
        RootTableManager<
          _$ChordiaDatabase,
          $ResponseCacheTable,
          CachedResponse,
          $$ResponseCacheTableFilterComposer,
          $$ResponseCacheTableOrderingComposer,
          $$ResponseCacheTableAnnotationComposer,
          $$ResponseCacheTableCreateCompanionBuilder,
          $$ResponseCacheTableUpdateCompanionBuilder,
          (
            CachedResponse,
            BaseReferences<
              _$ChordiaDatabase,
              $ResponseCacheTable,
              CachedResponse
            >,
          ),
          CachedResponse,
          PrefetchHooks Function()
        > {
  $$ResponseCacheTableTableManager(
    _$ChordiaDatabase db,
    $ResponseCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResponseCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResponseCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResponseCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> bodyJson = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int> staleAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResponseCacheCompanion(
                key: key,
                bodyJson: bodyJson,
                fetchedAt: fetchedAt,
                staleAt: staleAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String bodyJson,
                required int fetchedAt,
                required int staleAt,
                Value<int> rowid = const Value.absent(),
              }) => ResponseCacheCompanion.insert(
                key: key,
                bodyJson: bodyJson,
                fetchedAt: fetchedAt,
                staleAt: staleAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ResponseCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$ChordiaDatabase,
      $ResponseCacheTable,
      CachedResponse,
      $$ResponseCacheTableFilterComposer,
      $$ResponseCacheTableOrderingComposer,
      $$ResponseCacheTableAnnotationComposer,
      $$ResponseCacheTableCreateCompanionBuilder,
      $$ResponseCacheTableUpdateCompanionBuilder,
      (
        CachedResponse,
        BaseReferences<_$ChordiaDatabase, $ResponseCacheTable, CachedResponse>,
      ),
      CachedResponse,
      PrefetchHooks Function()
    >;
typedef $$KeyValuesTableCreateCompanionBuilder =
    KeyValuesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$KeyValuesTableUpdateCompanionBuilder =
    KeyValuesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$KeyValuesTableFilterComposer
    extends Composer<_$ChordiaDatabase, $KeyValuesTable> {
  $$KeyValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KeyValuesTableOrderingComposer
    extends Composer<_$ChordiaDatabase, $KeyValuesTable> {
  $$KeyValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KeyValuesTableAnnotationComposer
    extends Composer<_$ChordiaDatabase, $KeyValuesTable> {
  $$KeyValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$KeyValuesTableTableManager
    extends
        RootTableManager<
          _$ChordiaDatabase,
          $KeyValuesTable,
          KvEntry,
          $$KeyValuesTableFilterComposer,
          $$KeyValuesTableOrderingComposer,
          $$KeyValuesTableAnnotationComposer,
          $$KeyValuesTableCreateCompanionBuilder,
          $$KeyValuesTableUpdateCompanionBuilder,
          (
            KvEntry,
            BaseReferences<_$ChordiaDatabase, $KeyValuesTable, KvEntry>,
          ),
          KvEntry,
          PrefetchHooks Function()
        > {
  $$KeyValuesTableTableManager(_$ChordiaDatabase db, $KeyValuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KeyValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KeyValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KeyValuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KeyValuesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => KeyValuesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeyValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$ChordiaDatabase,
      $KeyValuesTable,
      KvEntry,
      $$KeyValuesTableFilterComposer,
      $$KeyValuesTableOrderingComposer,
      $$KeyValuesTableAnnotationComposer,
      $$KeyValuesTableCreateCompanionBuilder,
      $$KeyValuesTableUpdateCompanionBuilder,
      (KvEntry, BaseReferences<_$ChordiaDatabase, $KeyValuesTable, KvEntry>),
      KvEntry,
      PrefetchHooks Function()
    >;

class $ChordiaDatabaseManager {
  final _$ChordiaDatabase _db;
  $ChordiaDatabaseManager(this._db);
  $$HubsTableTableManager get hubs => $$HubsTableTableManager(_db, _db.hubs);
  $$DownloadsTableTableManager get downloads =>
      $$DownloadsTableTableManager(_db, _db.downloads);
  $$DownloadTasksTableTableManager get downloadTasks =>
      $$DownloadTasksTableTableManager(_db, _db.downloadTasks);
  $$ScrobbleQueueTableTableManager get scrobbleQueue =>
      $$ScrobbleQueueTableTableManager(_db, _db.scrobbleQueue);
  $$ResponseCacheTableTableManager get responseCache =>
      $$ResponseCacheTableTableManager(_db, _db.responseCache);
  $$KeyValuesTableTableManager get keyValues =>
      $$KeyValuesTableTableManager(_db, _db.keyValues);
}
