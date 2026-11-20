// Custom fork: album search sheet (two-finger swipe up anywhere, or the search button).
// Pinned albums on top (star to pin), folders collapse/expand and open by themselves while typing.
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/presentation/widgets/album/album_folder_bar.widget.dart';
import 'package:immich_mobile/presentation/widgets/album/recent_albums.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/routing/router.dart';

bool _sheetOpen = false;

/// Pinned ids with [albumId] toggled.
List<String> togglePinned(List<String> ids, String albumId) =>
    ids.contains(albumId) ? ids.where((id) => id != albumId).toList() : [...ids, albumId];

/// Albums whose name contains every word of [query] (case-insensitive).
List<RemoteAlbum> filterAlbums(List<RemoteAlbum> albums, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) {
    return albums;
  }
  return albums.where((a) {
    final name = a.name.toLowerCase();
    return words.every(name.contains);
  }).toList();
}

Future<void> showAlbumSearchSheet(BuildContext context) async {
  if (_sheetOpen) {
    return;
  }
  _sheetOpen = true;
  try {
    final picked = await showModalBottomSheet<RemoteAlbum>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _AlbumSearchSheet(),
    );
    if (picked != null && context.mounted) {
      unawaited(context.router.push(RemoteAlbumRoute(album: picked)));
    }
  } finally {
    _sheetOpen = false;
  }
}

class _AlbumSearchSheet extends ConsumerStatefulWidget {
  const _AlbumSearchSheet();

  @override
  ConsumerState<_AlbumSearchSheet> createState() => _AlbumSearchSheetState();
}

class _AlbumSearchSheetState extends ConsumerState<_AlbumSearchSheet> {
  final _query = TextEditingController();
  final Set<String> _open = {};

  @override
  void initState() {
    super.initState();
    if (ref.read(remoteAlbumProvider).albums.isEmpty) {
      unawaited(ref.read(remoteAlbumProvider.notifier).refresh());
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _row(RemoteAlbum album, List<String> pinned) {
    final isPinned = pinned.contains(album.id);
    return ListTile(
      key: ValueKey('album_search_${album.id}'),
      dense: true,
      leading: const Icon(Icons.photo_album_outlined),
      title: Text(album.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text("${album.assetCount} items"),
      trailing: IconButton(
        tooltip: isPinned ? "Unpin" : "Pin",
        icon: Icon(isPinned ? Icons.star_rounded : Icons.star_border_rounded, color: isPinned ? Colors.amber : null),
        onPressed: () => unawaited(ref.read(settingsProvider).write(.albumPinnedIds, togglePinned(pinned, album.id))),
      ),
      onTap: () {
        unawaited(recordRecentAlbum(ref, album.id));
        Navigator.of(context).pop(album);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(remoteAlbumProvider.select((s) => s.albums));
    final pinned = ref.watch(appConfigProvider.select((c) => c.album.pinnedIds));
    final folders = ref.watch(albumFoldersProvider);
    final query = _query.text.trim();
    final hits = filterAlbums(all, query);
    final typing = query.isNotEmpty;

    final byId = {for (final a in hits) a.id: a};
    final pinnedHits = [for (final id in pinned) if (byId[id] != null) byId[id]!];
    final rest = hits.where((a) => !pinned.contains(a.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final children = <Widget>[];
    if (pinnedHits.isNotEmpty) {
      children.add(const ListTile(dense: true, title: Text("Pinned", style: TextStyle(fontWeight: FontWeight.w600))));
      children.addAll(pinnedHits.map((a) => _row(a, pinned)));
    }
    for (final folder in folders.names) {
      final inFolder = rest.where((a) => folders.folderOf(a.id) == folder).toList();
      if (inFolder.isEmpty) {
        continue;
      }
      final expanded = typing || _open.contains(folder);
      children.add(
        ListTile(
          key: ValueKey('album_search_folder_$folder'),
          dense: true,
          leading: Icon(expanded ? Icons.folder_open_rounded : Icons.folder_rounded),
          title: Text(folder, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: Text("${inFolder.length}"),
          onTap: () => setState(() => _open.contains(folder) ? _open.remove(folder) : _open.add(folder)),
        ),
      );
      if (expanded) {
        children.addAll(
          inFolder.map((a) => Padding(padding: const EdgeInsets.only(left: 16), child: _row(a, pinned))),
        );
      }
    }
    final unfiled = rest.where((a) => folders.folderOf(a.id) == null).toList();
    if (unfiled.isNotEmpty && folders.names.isNotEmpty) {
      children.add(const ListTile(dense: true, title: Text("Albums", style: TextStyle(fontWeight: FontWeight.w600))));
    }
    children.addAll(unfiled.map((a) => _row(a, pinned)));
    if (hits.isEmpty) {
      children.add(const ListTile(title: Text("No albums")));
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              key: const Key('album_search_field'),
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search albums",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(child: ListView(children: children)),
        ],
      ),
    );
  }
}

/// Wraps the whole app: a two-finger swipe up anywhere opens the album search sheet.
/// One-finger scrolls/drags and pinch zoom never trigger it.
class TwoFingerSwipeUp extends ConsumerStatefulWidget {
  const TwoFingerSwipeUp({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<TwoFingerSwipeUp> createState() => _TwoFingerSwipeUpState();
}

class _TwoFingerSwipeUpState extends ConsumerState<TwoFingerSwipeUp> {
  final Map<int, Offset> _start = {};
  final Map<int, Offset> _now = {};
  bool _fired = false;
  DateTime _startedAt = DateTime.now();

  void _down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) {
      return;
    }
    if (_start.isEmpty) {
      _fired = false;
    }
    _start[e.pointer] = e.position;
    _now[e.pointer] = e.position;
    if (_start.length == 2) {
      _startedAt = DateTime.now();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_start.containsKey(e.pointer)) {
      return;
    }
    _now[e.pointer] = e.position;
    if (_fired || _start.length != 2 || !ref.read(appConfigProvider).album.swipeSearch) {
      return;
    }
    final ids = _start.keys.toList();
    final d0 = _now[ids[0]]! - _start[ids[0]]!;
    final d1 = _now[ids[1]]! - _start[ids[1]]!;
    final gapStart = (_start[ids[0]]! - _start[ids[1]]!).distance;
    final gapNow = (_now[ids[0]]! - _now[ids[1]]!).distance;
    final quick = DateTime.now().difference(_startedAt) < const Duration(milliseconds: 700);
    if (quick &&
        d0.dy < -90 &&
        d1.dy < -90 &&
        d0.dx.abs() < 70 &&
        d1.dx.abs() < 70 &&
        (gapNow - gapStart).abs() < 60) {
      _fired = true;
      final ctx = widget.navigatorKey.currentContext;
      if (ctx != null) {
        unawaited(showAlbumSearchSheet(ctx));
      }
    }
  }

  void _up(PointerEvent e) {
    _start.remove(e.pointer);
    _now.remove(e.pointer);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

/// Settings > Preferences > Albums style toggle, shown on the Asset Viewer settings page.
class AlbumSwipeSearchSetting extends ConsumerWidget {
  const AlbumSwipeSearchSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(appConfigProvider.select((c) => c.album.swipeSearch));
    return SwitchListTile(
      title: const Text("Two-finger swipe up: album search"),
      subtitle: const Text("Swipe up with two fingers anywhere to open the album search sheet."),
      value: on,
      onChanged: (v) => unawaited(ref.read(settingsProvider).write(.albumSwipeSearch, v)),
    );
  }
}
