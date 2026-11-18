// Custom fork: keeps the app's own data on the laptop. The phone copy is a cache.
//
// Everything in the settings table (album folders, thumbnail shape, slideshow, ...) is stored as
// one document, `app_settings`. Whichever side changed last wins. A phone that has never synced
// (fresh install) never overwrites what the laptop already holds.
import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/domain/models/config/laptop_sync_config.dart';
import 'package:immich_mobile/domain/models/settings_key.dart';
import 'package:immich_mobile/infrastructure/repositories/laptop_sync_api.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:logging/logging.dart';

enum LaptopSyncOutcome { notConfigured, inSync, sentToLaptop, restoredFromLaptop }

enum LaptopSyncForce { none, sendToLaptop, restoreFromLaptop }

const kLaptopSettingsKey = 'app_settings';

/// Settings that describe the sync itself and must stay on the phone.
const kLaptopLocalOnlyKeys = <SettingsKey>{SettingsKey.laptopSyncServerUrl, SettingsKey.laptopSyncSettingsStamp};

/// Fixed-width UTC time (millisecond precision) so stamps compare correctly as text.
String laptopStamp(DateTime time) =>
    DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch, isUtc: true).toIso8601String();

class LaptopSyncService {
  static const _debounce = Duration(seconds: 3);

  final SettingsRepository _settings;
  final LaptopSyncApiRepository _api;
  final DateTime Function() _now;
  final _log = Logger('LaptopSyncService');

  StreamSubscription<AppConfig>? _subscription;
  Timer? _timer;
  AppConfig? _lastSynced;
  bool _applyingRemote = false;
  Future<LaptopSyncOutcome>? _running;

  LaptopSyncService(this._settings, this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  LaptopSyncConfig get _config => _settings.appConfig.laptopSync;

  static AppConfig _withoutLocalOnly(AppConfig config) => config.copyWith(laptopSync: const LaptopSyncConfig());

  /// Call once after the settings are loaded: syncs now, then again a few seconds after every change.
  void start() {
    if (_subscription != null) {
      return;
    }
    _lastSynced = _withoutLocalOnly(_settings.appConfig);
    _subscription = _settings.watchConfig().listen(_onConfigChanged);
    unawaited(syncQuietly());
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _onConfigChanged(AppConfig config) {
    final comparable = _withoutLocalOnly(config);
    if (_applyingRemote || comparable == _lastSynced) {
      return;
    }
    _lastSynced = comparable;
    // Not set up yet: leave the stamp alone, so connecting later restores from the laptop
    // instead of overwriting it with a fresh install's settings.
    if (_config.serverUrl.isEmpty) {
      return;
    }
    unawaited(_settings.write(.laptopSyncSettingsStamp, laptopStamp(_now())));
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(syncQuietly()));
  }

  /// Sync that never throws (background use). Returns null when the laptop could not be reached.
  Future<LaptopSyncOutcome?> syncQuietly() async {
    try {
      return await sync();
    } catch (error) {
      _log.info('Laptop sync skipped: $error');
      return null;
    }
  }

  /// Throws [LaptopSyncException] when the laptop cannot be reached.
  Future<LaptopSyncOutcome> sync({LaptopSyncForce force = LaptopSyncForce.none}) {
    final running = _running;
    if (running != null && force == LaptopSyncForce.none) {
      return running;
    }
    final next = (running ?? Future<void>.value()).catchError((_) => LaptopSyncOutcome.inSync).then((_) => _sync(force));
    _running = next;
    return next.whenComplete(() {
      if (identical(_running, next)) {
        _running = null;
      }
    });
  }

  Future<LaptopSyncOutcome> _sync(LaptopSyncForce force) async {
    final url = _config.serverUrl;
    if (url.isEmpty) {
      return LaptopSyncOutcome.notConfigured;
    }

    final remote = await _api.get(url, kLaptopSettingsKey);
    final localStamp = _config.settingsStamp;

    final restore =
        force == LaptopSyncForce.restoreFromLaptop ||
        (force == LaptopSyncForce.none && remote != null && remote.updatedAt.compareTo(localStamp) > 0);
    if (restore) {
      if (remote == null) {
        throw const LaptopSyncException('The laptop has no saved data yet');
      }
      await _applyRemote(remote);
      return LaptopSyncOutcome.restoredFromLaptop;
    }

    final send =
        force == LaptopSyncForce.sendToLaptop ||
        remote == null ||
        localStamp.compareTo(remote.updatedAt) > 0;
    if (!send) {
      return LaptopSyncOutcome.inSync;
    }

    // A forced send must beat whatever the laptop holds
    var stamp = localStamp.isEmpty || force == LaptopSyncForce.sendToLaptop ? laptopStamp(_now()) : localStamp;
    if (remote != null && stamp.compareTo(remote.updatedAt) <= 0) {
      stamp = laptopStamp(DateTime.parse(remote.updatedAt).add(const Duration(milliseconds: 1)));
    }

    final value = await _settings.exportRaw(exclude: kLaptopLocalOnlyKeys);
    final newer = await _api.put(url, kLaptopSettingsKey, updatedAt: stamp, value: value);
    if (newer != null) {
      // the laptop changed between our read and write
      await _applyRemote(newer);
      return LaptopSyncOutcome.restoredFromLaptop;
    }
    await _settings.write(.laptopSyncSettingsStamp, stamp);
    return LaptopSyncOutcome.sentToLaptop;
  }

  Future<void> _applyRemote(LaptopDoc remote) async {
    final value = remote.value;
    if (value is! Map) {
      throw const LaptopSyncException('The data on the laptop is not in the expected format');
    }
    final rows = <String, String?>{
      for (final entry in value.entries)
        if (entry.key is String && (entry.value == null || entry.value is String))
          entry.key as String: entry.value as String?,
    };

    _applyingRemote = true;
    try {
      await _settings.importRaw(rows, exclude: kLaptopLocalOnlyKeys);
      await _settings.write(.laptopSyncSettingsStamp, remote.updatedAt);
      _lastSynced = _withoutLocalOnly(_settings.appConfig);
    } finally {
      _applyingRemote = false;
    }
  }

  /// Everything this app stores about itself, for the Export button.
  Future<Map<String, Object?>> exportBundle() async => {
    'app': 'immich-custom',
    'exportedAt': laptopStamp(_now()),
    kLaptopSettingsKey: await _settings.exportRaw(exclude: kLaptopLocalOnlyKeys),
  };
}

final laptopSyncApiRepositoryProvider = Provider((ref) => LaptopSyncApiRepository());

final laptopSyncServiceProvider = Provider((ref) {
  final service = LaptopSyncService(SettingsRepository.instance, ref.watch(laptopSyncApiRepositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});
