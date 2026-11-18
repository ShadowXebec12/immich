import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/app/settings.drift.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/domain/models/settings_key.dart';
import 'package:immich_mobile/infrastructure/repositories/cached_key_value_repository.dart';

class SettingsRepository extends CachedKeyValueRepository<SettingsKey, AppConfig> {
  final Drift _db;

  SettingsRepository._(this._db) : super(const .new());

  static SettingsRepository? _instance;

  static SettingsRepository get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('SettingsRepository not initialized. Call ensureInitialized() first');
    }
    return instance;
  }

  static Future<SettingsRepository> ensureInitialized(Drift db) async {
    if (_instance == null) {
      final instance = SettingsRepository._(db);
      await instance.refresh();
      _instance = instance;
    }
    return _instance!;
  }

  @visibleForTesting
  static Future<void> reset() async {
    final instance = _instance;
    if (instance != null) {
      await instance.clear(SettingsKey.values);
      _instance = null;
    }
  }

  @override
  List<SettingsKey> get keys => SettingsKey.values;

  @override
  Object decodeValue(SettingsKey key, String raw) => key.decode(raw);

  @override
  AppConfig buildSnapshot(Map<SettingsKey, Object?> overrides) => AppConfig.fromEntries(overrides);

  @override
  Selectable<({String key, String? value})> selectable() =>
      _db.select(_db.settingsEntity).map((row) => (key: row.key, value: row.value));

  AppConfig get appConfig => snapshot;

  Future<void> clear(Iterable<SettingsKey> keys) async {
    if (keys.isEmpty) {
      return;
    }

    final names = keys.map((key) => key.name).toList();
    await (_db.delete(_db.settingsEntity)..where((row) => row.key.isIn(names))).go();

    var config = snapshot;
    for (final key in keys) {
      config = config.write(key, defaultConfig.read(key));
    }
    snapshot = config;
  }

  Future<void> write<T, U extends T>(SettingsKey<T> key, U value) async {
    if (value == snapshot.read(key)) {
      return;
    }

    if (value == defaultConfig.read(key)) {
      return clear([key]);
    }

    String? resolvedValue;
    if (value != null) {
      resolvedValue = key.encode(value);
    }

    await _db
        .into(_db.settingsEntity)
        .insertOnConflictUpdate(
          SettingsEntityCompanion.insert(key: key.name, value: .new(resolvedValue), updatedAt: .new(DateTime.now())),
        );
    snapshot = snapshot.write(key, value);
  }

  Stream<AppConfig> watchConfig() => watchSnapshot();

  // ---- Custom fork: laptop sync works on the raw key -> text rows, so every setting is covered
  // without listing them (new settings sync automatically).

  /// Every stored (non-default) setting except [exclude], as key name -> encoded text.
  Future<Map<String, String?>> exportRaw({Set<SettingsKey> exclude = const {}}) async {
    final skip = exclude.map((key) => key.name).toSet();
    final rows = await selectable().get();
    return {
      for (final row in rows)
        if (!skip.contains(row.key) && keys.any((key) => key.name == row.key)) row.key: row.value,
    };
  }

  /// Replaces every setting except [exclude] with [rows]. Unknown keys and values that do not
  /// decode are skipped, so data written by a newer or older app version cannot break this one.
  Future<void> importRaw(Map<String, String?> rows, {Set<SettingsKey> exclude = const {}}) async {
    final skip = exclude.map((key) => key.name).toSet();
    final valid = <String, String?>{};
    for (final entry in rows.entries) {
      final key = keys.firstWhereOrNull((key) => key.name == entry.key);
      if (key == null || skip.contains(entry.key)) {
        continue;
      }
      try {
        if (entry.value != null) {
          decodeValue(key, entry.value!);
        }
        valid[entry.key] = entry.value;
      } catch (_) {
        // not readable by this version
      }
    }

    final replaceable = keys.map((key) => key.name).where((name) => !skip.contains(name)).toList();
    await _db.transaction(() async {
      await (_db.delete(_db.settingsEntity)..where((row) => row.key.isIn(replaceable))).go();
      for (final entry in valid.entries) {
        await _db
            .into(_db.settingsEntity)
            .insertOnConflictUpdate(
              SettingsEntityCompanion.insert(key: entry.key, value: .new(entry.value), updatedAt: .new(DateTime.now())),
            );
      }
    });
    await refresh();
  }
}
