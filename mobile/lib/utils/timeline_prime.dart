// Custom fork.
import 'dart:math' as math;

import 'package:immich_mobile/domain/services/timeline.service.dart';

/// A fresh [TimelineService] fills in asynchronously. The slideshow reads its first asset
/// right away, so wait for the count and load the first few assets before opening it.
/// Returns false when the timeline stays empty.
Future<bool> primeTimeline(TimelineService timeline, {int count = 5}) async {
  for (var i = 0; i < 100 && timeline.totalAssets == 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (timeline.totalAssets == 0) {
    return false;
  }
  await timeline.loadAssets(0, math.min(count, timeline.totalAssets));
  return true;
}
