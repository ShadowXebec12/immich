// Custom fork: where the app's own data is stored on the laptop.
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'laptop_sync_config.freezed.dart';

@freezed
abstract class LaptopSyncConfig with _$LaptopSyncConfig {
  const factory LaptopSyncConfig({
    /// e.g. http://192.168.1.4:8791, empty = not set up
    @Default('') String serverUrl,

    /// When this phone's settings last changed (or which laptop version they match). ISO UTC, '' = never
    @Default('') String settingsStamp,
  }) = _LaptopSyncConfig;
}
