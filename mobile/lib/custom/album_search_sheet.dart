// Custom fork: album search sheet (two-finger swipe up anywhere, or the search button).
// Pinned albums on top (star to pin), folders collapse/expand and open by themselves while typing.
import 'dart:async';

import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/gallery_search.dart';
import 'package:immich_mobile/presentation/pages/search/paginated_search.provider.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/viewer_select_button.widget.dart';
import 'package:immich_mobile/custom/stack_export.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/utils/timeline_prime.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/presentation/widgets/album/album_folder_bar.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail.widget.dart';
import 'package:immich_mobile/presentation/widgets/album/recent_albums.widget.dart';
import 'package:immich_mobile/providers/album/album_search.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/routing/router.dart';

bool _sheetOpen = false;

/// Opens [assets] in the photo viewer (swipe through them).
/// [selectContainer]: the grid whose selection the viewer's Select button edits (View selected), else none.
Future<void> openAssetsInViewer(
  BuildContext context,
  WidgetRef ref,
  List<BaseAsset> assets, {
  ProviderContainer? selectContainer,
}) async {
  if (assets.isEmpty) {
    return;
  }
  final timeline = ref.read(timelineFactoryProvider).fromAssets(assets, TimelineOrigin.deepLink);
  if (!await primeTimeline(timeline, count: assets.length < 20 ? assets.length : 20) || !context.mounted) {
    unawaited(timeline.dispose());
    return;
  }
  // #4: reset the viewer state like a grid tap does; without it the viewer kept the last close's
  // fade-out (see-through page, no bars) and stacks / label results never opened properly
  AssetViewer.setAsset(ref, assets.first);
  ref.read(viewerSelectContainerProvider.notifier).state = selectContainer;
  await context.router.push(AssetViewerRoute(initialIndex: 0, timelineService: timeline));
}

/// albumId -> how many of [assetIds] it holds.
Future<Map<String, int>> albumHits(Drift db, List<String> assetIds) async {
  final counts = <String, int>{};
  for (var i = 0; i < assetIds.length; i += 500) {
    final chunk = assetIds.sublist(i, i + 500 > assetIds.length ? assetIds.length : i + 500);
    final q = db.remoteAlbumAssetEntity.select()..where((r) => r.assetId.isIn(chunk));
    for (final row in await q.get()) {
      counts[row.albumId] = (counts[row.albumId] ?? 0) + 1;
    }
  }
  return counts;
}

/// Every stack: stackId -> its photos (newest first).
Future<Map<String, List<RemoteAsset>>> allStacks(Drift db) async {
  final q = db.remoteAssetEntity.select()
    ..where((r) => r.stackId.isNotNull() & r.deletedAt.isNull())
    ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
  final out = <String, List<RemoteAsset>>{};
  for (final a in await q.map((r) => r.toDto()).get()) {
    out.putIfAbsent(a.stackId!, () => []).add(a);
  }
  return out;
}

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
      builder: (_) => _AlbumSearchSheet(album: currentStackAlbum(context)),
    );
    if (picked != null && context.mounted) {
      unawaited(context.router.push(RemoteAlbumRoute(album: picked)));
    }
  } finally {
    _sheetOpen = false;
  }
}

class _AlbumSearchSheet extends ConsumerStatefulWidget {
  const _AlbumSearchSheet({this.album});

  final RemoteAlbum? album;

  @override
  ConsumerState<_AlbumSearchSheet> createState() => _AlbumSearchSheetState();
}

class _AlbumSearchSheetState extends ConsumerState<_AlbumSearchSheet> {
  final _query = TextEditingController();
  final Set<String> _open = {};
  bool _labelsMode = false;

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
    final pinnedHits = [
      for (final id in pinned)
        if (byId[id] != null) byId[id]!,
    ];
    final rest = hits.where((a) => !pinned.contains(a.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final children = <Widget>[
      if (!typing || "all stacks".contains(query.toLowerCase()))
        ListTile(
          key: const Key('album_search_all_stacks'),
          dense: true,
          leading: const Icon(Icons.burst_mode_outlined),
          title: const Text("All stacks", style: TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AllStacksPage()))),
        ),
    ];
    if (pinnedHits.isNotEmpty) {
      children.add(
        const ListTile(
          dense: true,
          title: Text("Pinned", style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
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
        children.addAll(inFolder.map((a) => Padding(padding: const EdgeInsets.only(left: 16), child: _row(a, pinned))));
      }
    }
    final unfiled = rest.where((a) => folders.folderOf(a.id) == null).toList();
    if (unfiled.isNotEmpty && folders.names.isNotEmpty) {
      children.add(
        const ListTile(
          dense: true,
          title: Text("Albums", style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text("Album name"), icon: Icon(Icons.photo_album_outlined)),
                ButtonSegment(value: true, label: Text("Labels"), icon: Icon(Icons.label_outline)),
              ],
              selected: {_labelsMode},
              onSelectionChanged: (v) => setState(() => _labelsMode = v.first),
            ),
          ),
          if (_labelsMode) Expanded(child: _LabelsMode(album: widget.album)),
          if (!_labelsMode)
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
          if (!_labelsMode) Expanded(child: ListView(children: children)),
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
    if (quick && d0.dy < -90 && d1.dy < -90 && d0.dx.abs() < 70 && d1.dx.abs() < 70 && (gapNow - gapStart).abs() < 60) {
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

/// One pose row of the pose drawer (/pose_base): its full pose labels and framing / secondary sub-labels.
class PoseBaseRow {
  const PoseBaseRow(this.tag, this.count, this.combos, this.subs);

  final String tag;
  final int count;
  final List<(String, int)> combos;
  final List<(String, String, int)> subs; // label, group (framing | secondary), count

  static PoseBaseRow fromJson(Map<String, dynamic> j) => PoseBaseRow(
    j['tag'].toString(),
    (j['count'] as num?)?.toInt() ?? 0,
    [for (final c in (j['combos'] as List? ?? const [])) (c['label'].toString(), (c['count'] as num?)?.toInt() ?? 0)],
    [
      for (final c in (j['subs'] as List? ?? const []))
        (c['label'].toString(), c['group'].toString(), (c['count'] as num?)?.toInt() ?? 0),
    ],
  );
}

Future<List<PoseBaseRow>> loadPoseBase() async {
  final res = await http
      .get(Uri.parse('$kGalleryServer/pose_base').replace(queryParameters: {'scope': 'all'}))
      .timeout(const Duration(seconds: 30));
  final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
  return [for (final j in list) PoseBaseRow.fromJson(j as Map<String, dynamic>)];
}

/// The nearest album page in the navigation stack (the album the sheet was opened from), if any.
RemoteAlbum? currentStackAlbum(BuildContext context) {
  final pages = context.router.root.stack;
  for (var i = pages.length - 1; i >= 0; i--) {
    final args = pages[i].routeData.args;
    if (args is RemoteAlbumRouteArgs) {
      return args.album;
    }
  }
  return null;
}

/// Labels mode (#3): the mix gallery's pose drawer (tick = add, row = only this, chevron = full pose
/// labels + framing / secondary sub-rows), the other label groups as chips, and a This album /
/// All albums switch. This album = the album's own label filter; All albums = matching albums + images.
class _LabelsMode extends ConsumerStatefulWidget {
  const _LabelsMode({this.album});

  final RemoteAlbum? album;

  @override
  ConsumerState<_LabelsMode> createState() => _LabelsModeState();
}

class _LabelsModeState extends ConsumerState<_LabelsMode> {
  static const _framing = (Color(0xFF084F40), Color(0xFF9EE0CC));
  static const _secondary = (Color(0xFF3D338A), Color(0xFFCFCCF5));
  static const _poseChip = (Color(0xFF0F3D7A), Color(0xFFB3D6FF));

  final _filter = TextEditingController();
  final List<String> _picked = [];
  final Set<String> _open = {};
  List<LabelGroup>? _groups;
  List<PoseBaseRow>? _poses;
  String? _error;
  bool _busy = false;
  // #4: All albums (search) is the default; This album stays one tap away
  bool _inAlbum = false;
  List<String> _ids = const [];
  Map<String, int> _hits = const {};
  int _search = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([ref.read(galleryLabelsProvider.notifier).groups(), loadPoseBase()]);
      if (mounted) {
        setState(() {
          _groups = results[0] as List<LabelGroup>;
          _poses = results[1] as List<PoseBaseRow>;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Gallery server not reachable");
      }
    }
  }

  Future<void> _run() async {
    final id = ++_search;
    if (_picked.isEmpty || _inAlbum) {
      setState(() {
        _ids = const [];
        _hits = const {};
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final db = ref.read(driftProvider);
      // same request + cache as the Search page, so "Show in Search" opens at once
      final ids = await galleryFilterIds(db, models: const [], chars: const [], labels: List.of(_picked), mixes: const []);
      final hits = await albumHits(db, ids);
      if (mounted && id == _search) {
        setState(() {
          _ids = ids;
          _hits = hits;
          _busy = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && id == _search) {
        setState(() {
          _busy = false;
          _error = "Label search failed: $e";
        });
      }
    }
  }

  void _set(List<String> labels) {
    setState(() {
      _picked
        ..clear()
        ..addAll(labels);
    });
    unawaited(_run());
  }

  /// tick: add / remove one label
  void _toggle(String label) =>
      _set(_picked.contains(label) ? (List.of(_picked)..remove(label)) : [..._picked, label]);

  /// row tap: only this label (tap the sole pick again to clear)
  void _only(String label) => _set(_picked.length == 1 && _picked.first == label ? const [] : [label]);

  /// sub-row tap: this pose AND that framing / secondary label
  void _poseSub(String pose, String sub) {
    final same = _picked.length == 2 && _picked[0] == pose && _picked[1] == sub;
    _set(same ? [pose] : [pose, sub]);
  }

  /// This album: hand the labels to the album's own filter and go back to the album.
  void _applyToAlbum() {
    final album = widget.album;
    if (album == null || _picked.isEmpty) {
      return;
    }
    ref.read(albumSearchLabelsProvider(album.id).notifier).state = List.of(_picked);
    final query = ref.read(albumSearchQueryProvider(album.id).notifier);
    query.state ??= '';
    final router = context.router.root;
    Navigator.of(context).pop();
    router.popUntil((r) => r.settings.arguments is RemoteAlbumRouteArgs || r.isFirst);
  }

  /// #4: All albums: the matching images open as a Search page result (Labels filter set).
  void _showInSearch() {
    final router = context.router;
    final labels = List.of(_picked);
    Navigator.of(context).pop();
    ref.read(searchPreFilterProvider.notifier)
      ..clear()
      ..setFilter(
        .new(
          galLabels: labels,
          people: {},
          location: const .new(),
          camera: const .new(),
          date: const .new(),
          display: const .new(isNotInAlbum: false, isArchive: false, isFavorite: false),
          rating: const .new(),
          mediaType: .other,
        ),
      );
    unawaited(router.navigate(const SearchRoute()));
  }

  Widget _tag((Color, Color) c, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: c.$1, borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: TextStyle(color: c.$2, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  List<Widget> _poseRows(String f) {
    final rows = <Widget>[];
    for (final p in _poses ?? const <PoseBaseRow>[]) {
      final combos = f.isEmpty ? p.combos : p.combos.where((c) => c.$1.toLowerCase().contains(f)).toList();
      if (f.isNotEmpty && !p.tag.toLowerCase().contains(f) && combos.isEmpty) {
        continue;
      }
      final open = _open.contains(p.tag) || (f.isNotEmpty && combos.isNotEmpty);
      final on = _picked.contains(p.tag);
      rows.add(
        ListTile(
          key: ValueKey('drawer_pose_${p.tag}'),
          dense: true,
          selected: on && _picked.length == 1,
          leading: IconButton(
            icon: Icon(on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
            onPressed: () => _toggle(p.tag),
          ),
          title: Text(p.tag),
          subtitle: Text("${p.count}"),
          trailing: IconButton(
            icon: Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded),
            onPressed: p.combos.isEmpty && p.subs.isEmpty
                ? null
                : () => setState(() => _open.contains(p.tag) ? _open.remove(p.tag) : _open.add(p.tag)),
          ),
          onTap: () => _only(p.tag),
        ),
      );
      if (!open) {
        continue;
      }
      for (final (label, count) in combos) {
        final comboOn = _picked.contains(label);
        rows.add(
          ListTile(
            key: ValueKey('drawer_combo_$label'),
            dense: true,
            contentPadding: const EdgeInsets.only(left: 40, right: 16),
            selected: comboOn && _picked.length == 1,
            leading: IconButton(
              icon: Icon(comboOn ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 20),
              onPressed: () => _toggle(label),
            ),
            title: Row(
              children: [
                _tag(_poseChip, "pose"),
                const SizedBox(width: 8),
                Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
            trailing: Text("$count"),
            onTap: () => _only(label),
          ),
        );
      }
      if (_open.contains(p.tag)) {
        for (final (label, group, count) in p.subs) {
          final subOn = _picked.length == 2 && _picked[0] == p.tag && _picked[1] == label;
          rows.add(
            ListTile(
              key: ValueKey('drawer_sub_${p.tag}_$label'),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 56, right: 16),
              selected: subOn,
              title: Row(
                children: [
                  _tag(group == 'framing' ? _framing : _secondary, group == 'framing' ? "framing" : "secondary"),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              trailing: Text("$count"),
              onTap: () => _poseSub(p.tag, label),
            ),
          );
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final albums = {for (final a in ref.watch(remoteAlbumProvider.select((s) => s.albums))) a.id: a};
    final f = _filter.text.trim().toLowerCase();
    final groups = _groups;
    final hitAlbums = [
      for (final e in _hits.entries)
        if (albums[e.key] != null) (albums[e.key]!, e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final album = widget.album;

    return ListView(
      children: [
        if (album != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<bool>(
              key: const Key('label_scope_toggle'),
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  icon: const Icon(Icons.photo_album_outlined),
                ),
                const ButtonSegment(value: false, label: Text("All albums"), icon: Icon(Icons.public)),
              ],
              selected: {_inAlbum},
              onSelectionChanged: (v) {
                setState(() => _inAlbum = v.first);
                unawaited(_run());
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            key: const Key('label_search_field'),
            controller: _filter,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: "Filter labels",
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (_picked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              children: [
                for (final l in _picked) InputChip(label: Text(l), selected: true, onDeleted: () => _toggle(l)),
              ],
            ),
          ),
        if (_error != null) ListTile(title: Text(_error!)),
        if (_busy) const LinearProgressIndicator(),
        if (_picked.isNotEmpty && _inAlbum && album != null)
          ListTile(
            key: const Key('label_apply_album'),
            leading: const Icon(Icons.filter_alt_outlined),
            title: Text("Show in ${album.name}", style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _applyToAlbum,
          ),
        if (_picked.isNotEmpty && !_inAlbum && !_busy) ...[
          ListTile(
            key: const Key('label_all_matching'),
            leading: const Icon(Icons.search),
            title: const Text("Show in Search", style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: Text("${_ids.length}"),
            onTap: _showInSearch,
          ),
          for (final (a, n) in hitAlbums)
            ListTile(
              dense: true,
              leading: const Icon(Icons.photo_album_outlined),
              title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text("$n"),
              onTap: () {
                unawaited(recordRecentAlbum(ref, a.id));
                Navigator.of(context).pop(a);
              },
            ),
        ],
        const Divider(),
        if ((groups == null || _poses == null) && _error == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_poses != null) ...[
          const ListTile(dense: true, title: Text("Poses", style: TextStyle(fontWeight: FontWeight.w600))),
          ..._poseRows(f),
        ],
        if (groups != null)
          for (final g in groups)
            if (g.name.toLowerCase() != 'pose' && g.labels.any((l) => f.isEmpty || l.toLowerCase().contains(f))) ...[
              ListTile(
                dense: true,
                title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final l in g.labels)
                      if (f.isEmpty || l.toLowerCase().contains(f))
                        FilterChip(label: Text(l), selected: _picked.contains(l), onSelected: (_) => _toggle(l)),
                  ],
                ),
              ),
            ],
      ],
    );
  }
}

/// Every stack in the library, filterable by album folder. Tap opens the stack in the viewer.
class AllStacksPage extends ConsumerStatefulWidget {
  const AllStacksPage({super.key});

  @override
  ConsumerState<AllStacksPage> createState() => _AllStacksPageState();
}

class _AllStacksPageState extends ConsumerState<AllStacksPage> {
  Map<String, List<RemoteAsset>>? _stacks;
  Map<String, Set<String>> _assetFolders = const {};
  String? _folder;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final db = ref.read(driftProvider);
    final stacks = await allStacks(db);
    final folders = ref.read(albumFoldersProvider);
    final ids = [for (final list in stacks.values) ...list.map((a) => a.id)];
    final byAsset = <String, Set<String>>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
      final q = db.remoteAlbumAssetEntity.select()..where((r) => r.assetId.isIn(chunk));
      for (final row in await q.get()) {
        final folder = folders.folderOf(row.albumId);
        if (folder != null) {
          byAsset.putIfAbsent(row.assetId, () => {}).add(folder);
        }
      }
    }
    if (mounted) {
      setState(() {
        _stacks = stacks;
        _assetFolders = byAsset;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(albumFoldersProvider);
    final stacks = _stacks;
    final shown = stacks == null
        ? const <List<RemoteAsset>>[]
        : [
            for (final list in stacks.values)
              if (_folder == null || list.any((a) => _assetFolders[a.id]?.contains(_folder) ?? false)) list,
          ];
    return Scaffold(
      appBar: AppBar(title: Text(stacks == null ? "All stacks" : "All stacks (${shown.length})")),
      body: stacks == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (folders.names.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: ChoiceChip(
                            label: const Text("All"),
                            selected: _folder == null,
                            onSelected: (_) => setState(() => _folder = null),
                          ),
                        ),
                        for (final f in folders.names)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: ChoiceChip(
                              label: Text(f),
                              selected: _folder == f,
                              onSelected: (_) => setState(() => _folder = f),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(2),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                      childAspectRatio: 2 / 3,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final list = shown[i];
                      return GestureDetector(
                        key: ValueKey('stack_${list.first.stackId}'),
                        onTap: () => unawaited(openAssetsInViewer(context, ref, list)),
                        onLongPress: () => unawaited(showStackExportSheet(context, ref, list)),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Thumbnail.fromAsset(asset: list.first),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.burst_mode_outlined, size: 12, color: Colors.white),
                                    const SizedBox(width: 2),
                                    Text(
                                      "${list.length}",
                                      style: const TextStyle(color: Colors.white, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
