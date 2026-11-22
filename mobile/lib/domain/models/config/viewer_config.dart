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
    // Custom fork: viewer gestures as "gesture=action" (see lib/custom/viewer_tools.dart)
    @Default(<String>[]) List<String> gestures,
    // Custom fork: labels added from this app (JSON entries) and pinned label sets (see lib/custom/label_sheet.dart)
    @Default(<String>[]) List<String> labelHistory,
    @Default(<String>[]) List<String> labelPins,
    // Custom fork: last gen from the Generate sheet and grid label badges (see lib/custom/label_badges.dart)
    @Default(<String>[]) List<String> lastGen,
    @Default(<String>[]) List<String> labelBadges,
    // Custom fork (#4): gen queue ("immichId|name") and the last Generate sheet options (JSON)
    @Default(<String>[]) List<String> genQueue,
    String? lastGenOptions,
    // Custom fork: ask "are you sure" before Move on PC
    @Default(true) bool confirmPcMove,
  }) = _ViewerConfig;
}
