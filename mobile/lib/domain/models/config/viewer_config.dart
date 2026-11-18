import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'viewer_config.freezed.dart';

@freezed
abstract class ViewerConfig with _$ViewerConfig {
  const factory ViewerConfig({
    @Default(true) bool loopVideo,
    @Default(false) bool loadOriginalVideo,
    @Default(true) bool autoPlayVideo,
    @Default(false) bool tapToNavigate,
    // Custom fork: viewer gestures as "gesture=action" (see lib/custom/viewer_gestures.dart)
    @Default(<String>[]) List<String> gestures,
  }) = _ViewerConfig;
}
