// Custom fork: jump back to recently opened albums.
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/saved_searches.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/routing/router.dart';

const kRecentAlbumLimit = 12;

/// [ids] with [albumId] moved to the front, without duplicates, at most [limit] long.
List<String> pushRecentAlbum(List<String> ids, String albumId, {int limit = kRecentAlbumLimit}) =>
    [albumId, ...ids.where((id) => id != albumId)].take(limit).toList();

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

/// Bookmarks / Searches / Recent albums sheet. [currentAlbumId]: shown inside an album, which is left
/// out and replaced by the picked one. [initialTab]: 0 Bookmarks, 1 Searches, 2 Recent albums.
Future<void> showRecentSheet(BuildContext context, WidgetRef ref, {String? currentAlbumId, int initialTab = 2}) async {
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

    // Bookmarks / Searches / Recent albums tabs (saved searches open the Search page)
    Map? openSearch;
    final picked = await showModalBottomSheet<RemoteAlbum>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.7,
          child: DefaultTabController(
            length: 3,
            initialIndex: initialTab,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(key: Key('tab_bookmarks'), text: "Bookmarks"),
                    Tab(key: Key('tab_searches'), text: "Searches"),
                    Tab(key: Key('tab_recent_albums'), text: "Recent albums"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      SavedSearchList(
                        bookmarks: true,
                        onOpen: (q) {
                          openSearch = q;
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                      SavedSearchList(
                        bookmarks: false,
                        onOpen: (q) {
                          openSearch = q;
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                      ListView(
                        children: [
                          if (recent.isEmpty)
                            const ListTile(key: Key('recent_albums_empty'), title: Text("No other albums opened yet")),
                          for (final album in recent)
                            ListTile(
                              key: ValueKey('recent_album_${album.id}'),
                              leading: const Icon(Icons.photo_album_outlined),
                              title: Text(album.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text("${album.assetCount} items"),
                              onTap: () => Navigator.of(sheetContext).pop(album),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (openSearch != null && context.mounted) {
      SavedSearchStore.open(context, ref, openSearch!);
      return;
    }
    if (picked == null || !context.mounted) {
      return;
    }
    final route = RemoteAlbumRoute(album: picked);
    unawaited(currentAlbumId == null ? context.router.push(route) : context.router.popAndPush(route));
}

class RecentAlbumsButton extends ConsumerWidget {
  const RecentAlbumsButton({super.key, this.currentAlbumId, this.color, this.shadows});

  /// Set when shown inside an album: that album is left out and the picked one replaces it.
  final String? currentAlbumId;
  final Color? color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: const Key('recent_albums_button'),
    tooltip: "Bookmarks, searches, recent albums",
    onPressed: () => unawaited(showRecentSheet(context, ref, currentAlbumId: currentAlbumId)),
    icon: Icon(Icons.history_rounded, color: color, shadows: shadows),
  );
}
