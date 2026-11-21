// Custom fork (#4): queue albums and play them as one slideshow (album after album; shuffle deals
// from all of them). The queue is kept on this phone (setting albumSlideshowQueue, album ids in order).
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/timeline_prime.dart';

/// [ids] with [albumId] added at the end, or taken out when already queued.
List<String> toggleQueued(List<String> ids, String albumId) =>
    ids.contains(albumId) ? ids.where((id) => id != albumId).toList() : [...ids, albumId];

Future<void> playSlideshowQueue(BuildContext context, WidgetRef ref) async {
  final toast = ref.read(toastServiceProvider);
  final ids = ref.read(appConfigProvider).album.slideshowQueue;
  final notifier = ref.read(remoteAlbumProvider.notifier);
  final assets = <BaseAsset>[];
  final seen = <String>{};
  for (final id in ids) {
    try {
      for (final a in await notifier.getAssets(id)) {
        if (seen.add(a.id)) {
          assets.add(a);
        }
      }
    } catch (_) {
      // album gone: skip it
    }
  }
  if (assets.isEmpty) {
    toast.error("The queued albums have no photos");
    return;
  }
  if (!context.mounted) {
    return;
  }
  final timeline = ref.read(timelineFactoryProvider).fromAssets(assets, TimelineOrigin.deepLink);
  if (!await primeTimeline(timeline, count: assets.length < 20 ? assets.length : 20) || !context.mounted) {
    unawaited(timeline.dispose());
    return;
  }
  AssetViewer.setAsset(ref, assets.first);
  await context.pushRoute(SlideshowRoute(timeline: timeline));
  unawaited(timeline.dispose());
}

/// Album ... menu entries: Add to / Remove from slideshow queue, Play queue, Clear queue.
List<Widget> slideshowQueueMenuItems(BuildContext context, WidgetRef ref, RemoteAlbum album) {
  final queue = ref.watch(appConfigProvider.select((c) => c.album.slideshowQueue));
  final queued = queue.contains(album.id);
  return [
    BaseActionButton(
      key: const ValueKey('album_slideshow_queue_toggle'),
      label: queued ? 'Remove from slideshow queue' : 'Add to slideshow queue (${queue.length + 1})',
      iconData: queued ? Icons.playlist_remove_rounded : Icons.playlist_add_rounded,
      onPressed: () => unawaited(ref.read(settingsProvider).write(.albumSlideshowQueue, toggleQueued(queue, album.id))),
      menuItem: true,
    ),
    if (queue.isNotEmpty)
      BaseActionButton(
        key: const ValueKey('album_slideshow_queue_play'),
        label: 'Play slideshow queue (${queue.length} albums)',
        iconData: Icons.slideshow_rounded,
        onPressed: () => unawaited(playSlideshowQueue(context, ref)),
        menuItem: true,
      ),
    if (queue.isNotEmpty)
      BaseActionButton(
        key: const ValueKey('album_slideshow_queue_clear'),
        label: 'Clear slideshow queue',
        iconData: Icons.clear_all_rounded,
        onPressed: () => unawaited(ref.read(settingsProvider).write(.albumSlideshowQueue, const <String>[])),
        menuItem: true,
      ),
  ];
}
