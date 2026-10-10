// Custom fork: play the photos of the current stack as a slideshow.
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/timeline_prime.dart';

class StackSlideshowAction extends ActionBuilder {
  const StackSlideshowAction();

  @override
  ActionItem create(BuildContext context, WidgetRef ref) => .new(
    icon: Icons.burst_mode_outlined,
    label: "Play stack as slideshow",
    onAction: () async {
      final asset = ref.read(assetViewerProvider).currentAsset;
      if (asset is! RemoteAsset || asset.stackId == null) {
        return;
      }

      final stack = await ref.read(assetServiceProvider).getStack(asset);
      if (stack.isEmpty || !context.mounted) {
        return;
      }

      final timeline = ref.read(timelineFactoryProvider).fromAssets(stack, TimelineOrigin.deepLink);
      if (!await primeTimeline(timeline, count: stack.length) || !context.mounted) {
        unawaited(timeline.dispose());
        return;
      }

      await context.pushRoute(SlideshowRoute(timeline: timeline));
      unawaited(timeline.dispose());
    },
  );
}
