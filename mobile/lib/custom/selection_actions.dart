// Custom fork: grid selection buttons for DOpus labels, quick tags and stars (PC gallery server).
import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/album_search_sheet.dart';
import 'package:immich_mobile/custom/gen_menu.dart';
import 'package:immich_mobile/custom/pc_copy.dart';
import 'package:immich_mobile/custom/pc_move.dart';
import 'package:immich_mobile/custom/viewer_tools.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';

/// Phone clipboard holds one image, so this shows for a single selected photo.
class CopyImageAction extends AssetActionBuilder {
  const CopyImageAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count != 1) {
      return null;
    }
    return .new(
      icon: Icons.image_outlined,
      label: "Copy image",
      onAction: () async {
        final asset = ref.read(assetsActionProvider(source)).first;
        final toast = ref.read(toastServiceProvider);
        final clearSelection = ref.read(clearSelectionProvider(source));
        final error = await copyImageToClipboard(asset);
        if (error != null) {
          toast.error(error);
          return;
        }
        toast.success("Image copied");
        clearSelection();
      },
    );
  }
}

/// All selected files go on the PC clipboard together.
class CopyToPcAction extends AssetActionBuilder {
  const CopyToPcAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count == 0) {
      return null;
    }
    return .new(
      icon: Icons.desktop_windows_outlined,
      label: count == 1 ? "Copy to PC" : "Copy $count to PC",
      onAction: () async {
        final assets = ref.read(assetsActionProvider(source)).toList(growable: false);
        final clearSelection = ref.read(clearSelectionProvider(source));
        if (await copyManyToPc(ref, assets)) {
          clearSelection();
        }
      },
    );
  }
}

/// #5: album menu row. Brings back the last cleared selection, only the photos that are in this album.
class RestoreSelectionMenuItem extends ConsumerWidget {
  const RestoreSelectionMenuItem({super.key, required this.albumId});

  final String albumId;

  Future<void> _restore(WidgetRef ref, Set<BaseAsset> last) async {
    final toast = ref.read(toastServiceProvider);
    final notifier = ref.read(multiSelectProvider.notifier);
    final db = ref.read(driftProvider);
    final ids = [for (final a in last) ?a.remoteId];
    final inAlbum = <String>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final q = db.remoteAlbumAssetEntity.selectOnly()
        ..addColumns([db.remoteAlbumAssetEntity.assetId])
        ..where(db.remoteAlbumAssetEntity.albumId.equals(albumId) & db.remoteAlbumAssetEntity.assetId.isIn(chunk));
      for (final row in await q.get()) {
        inAlbum.add(row.read(db.remoteAlbumAssetEntity.assetId)!);
      }
    }
    final here = last.where((a) => inAlbum.contains(a.remoteId)).toSet();
    if (here.isEmpty) {
      toast.info("None of the last selection is in this album");
      return;
    }
    notifier.restore(here);
    if (here.length < last.length) {
      toast.info("Restored ${here.length} of ${last.length}: the rest are in other albums");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(multiSelectProvider.select((s) => s.selectedAssets.length)); // relabel after a selection is cleared
    final last = MultiSelectNotifier.lastCleared;
    return BaseActionButton(
      key: const Key('album_restore_selection'),
      label: last.isEmpty ? "No selection to restore" : "Restore last selection (${last.length})",
      iconData: Icons.restore_rounded,
      menuItem: true,
      onPressed: last.isEmpty ? null : () => unawaited(_restore(ref, last)),
    );
  }
}

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
          openAssetsInViewer(
            context,
            ref,
            assets,
            selectContainer: ProviderScope.containerOf(context, listen: false),
            viewSelected: true,
          ),
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
