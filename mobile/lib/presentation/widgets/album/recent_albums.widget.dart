// Custom fork: jump back to recently opened albums.
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/routing/router.dart';

const kRecentAlbumLimit = 12;

/// [ids] with [albumId] moved to the front, without duplicates, at most [limit] long.
List<String> pushRecentAlbum(List<String> ids, String albumId, {int limit = kRecentAlbumLimit}) => [
  albumId,
  ...ids.where((id) => id != albumId),
].take(limit).toList();

/// Recent ids resolved to albums that still exist, newest first, without [excludeId].
List<RemoteAlbum> resolveRecentAlbums(List<String> ids, List<RemoteAlbum> albums, {String? excludeId}) {
  final byId = {for (final album in albums) album.id: album};
  return [
    for (final id in ids)
      if (id != excludeId && byId[id] != null) byId[id]!,
  ];
}

Future<void> recordRecentAlbum(WidgetRef ref, String albumId) {
  final current = ref.read(appConfigProvider).album.recentIds;
  if (current.isNotEmpty && current.first == albumId) {
    return Future.value();
  }
  return ref.read(settingsProvider).write(.albumRecentIds, pushRecentAlbum(current, albumId));
}

class RecentAlbumsButton extends ConsumerWidget {
  const RecentAlbumsButton({super.key, this.currentAlbumId, this.color, this.shadows});

  /// Set when shown inside an album: that album is left out and the picked one replaces it.
  final String? currentAlbumId;
  final Color? color;
  final List<Shadow>? shadows;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (ref.read(remoteAlbumProvider).albums.isEmpty) {
      await ref.read(remoteAlbumProvider.notifier).refresh();
    }
    if (!context.mounted) {
      return;
    }

    final recent = resolveRecentAlbums(
      ref.read(appConfigProvider).album.recentIds,
      ref.read(remoteAlbumProvider).albums,
      excludeId: currentAlbumId,
    );

    final picked = await showModalBottomSheet<RemoteAlbum>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text("Recent albums", style: context.textTheme.titleMedium)),
              if (recent.isEmpty)
                const ListTile(key: Key('recent_albums_empty'), title: Text("No other albums opened yet")),
              for (final album in recent)
                ListTile(
                  key: ValueKey('recent_album_${album.id}'),
                  leading: const Icon(Icons.photo_album_outlined),
                  title: Text(album.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text("${album.assetCount} items"),
                  onTap: () => Navigator.of(context).pop(album),
                ),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !context.mounted) {
      return;
    }
    final route = RemoteAlbumRoute(album: picked);
    unawaited(currentAlbumId == null ? context.router.push(route) : context.router.popAndPush(route));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: const Key('recent_albums_button'),
    tooltip: "Recent albums",
    onPressed: () => unawaited(_open(context, ref)),
    icon: Icon(Icons.history_rounded, color: color, shadows: shadows),
  );
}
