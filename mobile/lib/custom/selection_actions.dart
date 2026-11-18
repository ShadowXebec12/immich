// Custom fork: grid selection buttons for DOpus labels, quick tags and stars (PC gallery server).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/viewer_tools.dart';
import 'package:immich_mobile/presentation/actions/action.dart';

class LabelSheetAction extends AssetActionBuilder {
  const LabelSheetAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count == 0) {
      return null;
    }
    return .new(
      icon: Icons.sell_outlined,
      label: "Label",
      onAction: () {
        final assets = ref.read(assetsActionProvider(source)).toList(growable: false);
        unawaited(showLabelSheetFor(context, ref, assets));
      },
    );
  }
}

class QuickTagAction extends AssetActionBuilder {
  const QuickTagAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count == 0) {
      return null;
    }
    return .new(
      icon: Icons.bookmark_add_outlined,
      label: "Quick tag",
      onAction: () {
        final assets = ref.read(assetsActionProvider(source)).toList(growable: false);
        unawaited(showQuickTagMenu(context, ref, assets));
      },
    );
  }
}

class RateAction extends AssetActionBuilder {
  const RateAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count == 0) {
      return null;
    }
    return .new(
      icon: Icons.star_border_rounded,
      label: "Rate",
      onAction: () {
        final assets = ref.read(assetsActionProvider(source)).toList(growable: false);
        unawaited(showRateMenu(context, ref, assets));
      },
    );
  }
}
