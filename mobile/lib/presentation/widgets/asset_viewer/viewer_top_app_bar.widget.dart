import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/custom/label_badges.dart';
import 'package:immich_mobile/custom/route_history.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/viewer_tools.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/datetime_extensions.dart';
import 'package:immich_mobile/presentation/actions/action.widget.dart';
import 'package:immich_mobile/presentation/actions/favorite.action.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/motion_photo_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/viewer_kebab_menu.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/viewer_select_button.widget.dart';
import 'package:immich_mobile/providers/activity.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/current_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/timezone.dart';
import 'package:immich_ui/immich_ui.dart';

class ViewerTopAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ViewerTopAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(assetViewerProvider.select((s) => s.currentAsset));
    if (asset == null) {
      return const SizedBox.shrink();
    }

    final album = ref.watch(currentRemoteAlbumProvider);

    final isInLockedView = ref.watch(inLockedViewProvider);
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);

    final showingDetails = ref.watch(assetViewerProvider.select((state) => state.showingDetails));

    if (album != null && album.isActivityEnabled && album.isShared && asset is RemoteAsset) {
      ref.watch(albumActivityProvider((album.id, asset.id)));
    }

    final showingControls = ref.watch(assetViewerProvider.select((s) => s.showingControls));
    final double opacity =
        ref.watch(assetViewerProvider.select((s) => s.backgroundOpacity)) * (showingControls ? 1 : 0);

    final originalTheme = context.themeData;

    final actions = <Widget>[
      if (asset.isMotionPhoto) const MotionPhotoActionButton(iconOnly: true),
      if (album != null && album.isActivityEnabled && album.isShared)
        IconButton(
          icon: const Icon(Icons.chat_outlined),
          onPressed: () {
            unawaited(
              context.router.push(
                ActivitiesRoute(album: album, assetId: asset is RemoteAsset ? asset.id : null, assetName: asset.name),
              ),
            );
          },
        ),

      ViewerSelectButton(asset: asset),
      const ActionIconButton(action: FavoriteAction(source: .viewer)),

      ImmichColorOverride(color: null, child: ViewerKebabMenu(originalTheme: originalTheme)),
    ];

    final lockedViewActions = <Widget>[ViewerKebabMenu(originalTheme: originalTheme)];

    return IgnorePointer(
      ignoring: opacity < 1.0,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: Durations.short2,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: showingDetails
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black45, Colors.black12, Colors.transparent],
                            stops: [0.0, 0.7, 1.0],
                          ),
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                height: preferredSize.height,
                child: Theme(
                  data: context.themeData.copyWith(iconTheme: const IconThemeData(size: 22, color: Colors.white)),
                  child: NavigationToolbar(
                    centerMiddle: true,
                    // Custom fork: tag button next to back (tap = recent labels, hold = label sheet)
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _AppBarBackButton(),
                        if (!showingDetails && !isReadonlyModeEnabled && !isInLockedView && asset.hasRemote)
                          ViewerLabelButton(asset: asset),
                      ],
                    ),
                    middle: showingDetails ? null : _AssetInfoTitle(asset: asset),
                    trailing: !showingDetails && !isReadonlyModeEnabled
                        ? ImmichColorOverride(
                            color: Colors.white,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: isInLockedView ? lockedViewActions : actions,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
                  // Custom fork (#4): this photo's pose / body / style (+ ref, vibe, test style, impaint) labels
                  if (!showingDetails && asset.hasRemote) ViewerLabelStrip(asset: asset),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60.0);
}

class _AppBarBackButton extends ConsumerWidget {
  const _AppBarBackButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showingDetails = ref.watch(assetViewerProvider.select((state) => state.showingDetails));
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: showingDetails ? context.colorScheme.surface : Colors.transparent,
        shape: const CircleBorder(),
        iconSize: 22,
        iconColor: showingDetails ? context.colorScheme.onSurface : Colors.white,
        padding: const EdgeInsets.all(10.0),
        elevation: showingDetails ? 4 : 0,
      ),
      onPressed: context.maybePop,
      onLongPress: () => unawaited(showRouteHistory(context)),
      child: const Icon(Icons.arrow_back_rounded),
    );
  }
}

class _AssetInfoTitle extends ConsumerWidget {
  final BaseAsset asset;

  const _AssetInfoTitle({required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exifInfo = ref.watch(assetExifProvider(asset)).valueOrNull;
    final alwaysUse24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);

    final (dateTime, _) = resolveAssetDateTime(asset, exifInfo);

    final dateFormatted = dateTime.formatDate();
    final timeFormatted = dateTime.formatTime(alwaysUse24HourFormat: alwaysUse24HourFormat);

    // Custom fork: the extra toolbar buttons (tag, select) leave little room; never wrap the
    // date one letter per line. Shrink to fit, and hide it when there is no usable room.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 56) {
          return const SizedBox.shrink();
        }
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dateFormatted, maxLines: 1, softWrap: false, style: context.textTheme.labelLarge?.copyWith(color: Colors.white)),
              Text(timeFormatted, maxLines: 1, softWrap: false, style: context.textTheme.labelMedium?.copyWith(color: Colors.white70)),
            ],
          ),
        );
      },
    );
  }
}
