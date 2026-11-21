// Custom fork: grid selection buttons for DOpus labels, quick tags and stars (PC gallery server).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/album_search_sheet.dart';
import 'package:immich_mobile/custom/gen_menu.dart';
import 'package:immich_mobile/custom/pc_move.dart';
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

/// #4: the viewer on just the selected photos (mix gallery "View selected"); its Select button edits this selection.
class ViewSelectedAction extends AssetActionBuilder {
  const ViewSelectedAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count == 0) {
      return null;
    }
    return .new(
      icon: Icons.burst_mode_outlined,
      label: "View selected ($count)",
      onAction: () {
        final assets = ref.read(assetsActionProvider(source)).toList(growable: false);
        unawaited(
          openAssetsInViewer(context, ref, assets, selectContainer: ProviderScope.containerOf(context, listen: false)),
        );
      },
    );
  }
}

/// #4: add the selection to the gen queue (one job later from the Generate page).
class GenQueueAction extends AssetActionBuilder {
  const GenQueueAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count == 0) {
      return null;
    }
    return .new(
      icon: Icons.playlist_add_rounded,
      label: "Queue for gen",
      onAction: () => unawaited(addToGenQueue(ref, ref.read(assetsActionProvider(source)).toList(growable: false))),
    );
  }
}

/// #4: move the selection on the PC (v4.5 / v3 / v5 folders of the F-key move AHK).
class PcMoveAction extends AssetActionBuilder {
  const PcMoveAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count == 0) {
      return null;
    }
    return .new(
      icon: Icons.drive_file_move_outline,
      label: "Move on PC",
      onAction: () => unawaited(showPcMoveSheet(context, ref, ref.read(assetsActionProvider(source)).toList(growable: false))),
    );
  }
}
