import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/custom/gen_menu.dart';
import 'package:immich_mobile/custom/pc_copy.dart';
import 'package:immich_mobile/custom/pc_move.dart';
import 'package:immich_mobile/custom/viewer_tools.dart';
import 'package:immich_mobile/custom/stack_export.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/providers/infrastructure/current_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/setting.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart' show appConfigProvider;
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/utils/action_button.utils.dart';
import 'package:immich_ui/immich_ui.dart';

class ViewerKebabMenu extends ConsumerWidget {
  const ViewerKebabMenu({super.key, this.originalTheme});

  final ThemeData? originalTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(assetViewerProvider.select((s) => s.currentAsset));
    if (asset == null) {
      return const SizedBox.shrink();
    }

    final user = ref.watch(currentUserProvider);
    final isOwner = asset is RemoteAsset && asset.ownerId == user?.id;
    final isCasting = ref.watch(castProvider.select((c) => c.isCasting));
    final timelineOrigin = ref.watch(timelineServiceProvider).origin;
    final isTrashEnable = ref.watch(serverInfoProvider.select((state) => state.serverFeatures.trash));
    final isInLockedView = ref.watch(inLockedViewProvider);
    final currentAlbum = ref.watch(currentRemoteAlbumProvider);
    final isArchived = asset is RemoteAsset && asset.visibility == AssetVisibility.archive;
    final advancedTroubleshooting = ref.watch(settingsProvider.notifier).get(.advancedTroubleshooting);

    final actionContext = ActionButtonContext(
      asset: asset,
      isOwner: isOwner,
      isArchived: isArchived,
      isTrashEnabled: isTrashEnable,
      isStacked: asset is RemoteAsset && asset.stackId != null,
      isInLockedView: isInLockedView,
      currentAlbum: currentAlbum,
      advancedTroubleshooting: advancedTroubleshooting,
      source: ActionSource.viewer,
      isCasting: isCasting,
      timelineOrigin: timelineOrigin,
    );

    final menuChildren = ActionButtonBuilder.buildViewerKebabMenu(actionContext, context);

    return ImmichMenu(
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(context.themeData.scaffoldBackgroundColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.grey),
        elevation: const WidgetStatePropertyAll(4),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 150),
          child: Theme(
            data: originalTheme ?? context.themeData,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Custom fork: mix gallery gen buttons + copy prompt parts
                if (asset.hasRemote) ...[
                  if (lastGen(ref.watch(appConfigProvider.select((c) => c.viewer.lastGen))) case final last?)
                    MenuItemButton(
                      key: const ValueKey('kebab_gen_again'),
                      leadingIcon: const Icon(Icons.replay_rounded),
                      onPressed: () => unawaited(genAgain(ref, asset)),
                      child: Text("Again: ${lastGenSummary(last)}"),
                    ),
                  MenuItemButton(
                    key: const ValueKey('kebab_generate'),
                    leadingIcon: const Icon(Icons.auto_awesome),
                    onPressed: () => unawaited(showGenSheet(context, ref, asset)),
                    child: const Text("Generate"),
                  ),
                  // #4: queue for one gen job + move on the PC (the selection when there is one, else this photo)
                  MenuItemButton(
                    key: const ValueKey('kebab_gen_queue'),
                    leadingIcon: const Icon(Icons.playlist_add_rounded),
                    onPressed: () => unawaited(addToGenQueue(ref, labelTargets(ref, asset))),
                    child: Text(
                      "Add to gen queue (${ref.watch(appConfigProvider.select((c) => c.viewer.genQueue.length))})",
                    ),
                  ),
                  PcMoveMenuEntries(
                    onMove: (ver, dest, folder) =>
                        unawaited(movePhotosOnPc(context, ref, labelTargets(ref, asset), ver, dest, folder)),
                  ),
                  MenuItemButton(
                    key: const ValueKey('kebab_copy_parts'),
                    leadingIcon: const Icon(Icons.content_copy),
                    onPressed: () => unawaited(showGenSheet(context, ref, asset, copyOnly: true)),
                    child: const Text("Copy prompt parts"),
                  ),
                  ...copyMenuEntries(context, ref, asset),
                  if (asset is RemoteAsset && asset.stackId != null)
                    MenuItemButton(
                      key: const ValueKey('kebab_stack_export'),
                      leadingIcon: const Icon(Icons.burst_mode_outlined),
                      onPressed: () => unawaited(exportStackOf(context, ref, asset)),
                      child: const Text("Export stack (save / PDF)"),
                    ),
                  const Divider(height: 1),
                ],
                ...menuChildren,
              ],
            ),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        );
      },
    );
  }
}
