// Custom fork: search filters answered by the PC gallery server's search index (/search, /searchfacets,
// /genmixes): model version, character, DOpus label, style mix. The server returns Immich asset ids
// (matched on the PC by NTFS file id, never by file name); the phone orders them newest first.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:path_provider/path_provider.dart';

const kGalleryModels = ['v4.5', 'v4', 'v3', 'v5'];

class GalleryFacetItem {
  const GalleryFacetItem(this.key, this.title, this.count, {String? search}) : _search = search;

  final String key;
  final String title;
  final int count;
  final String? _search;

  /// Lower-case text the picker filter matches: mixes also carry their full artist list.
  String get search => (_search ?? title).toLowerCase();

  Map<String, Object?> toJson() => {'k': key, 't': title, 'c': count, if (_search != null) 's': _search};
  static GalleryFacetItem fromJson(Map j) =>
      GalleryFacetItem(j['k'].toString(), j['t'].toString(), (j['c'] as num?)?.toInt() ?? 0, search: j['s'] as String?);
}

/// One /search request per model: (ver, extra label, excluded label). v4 / v4.5 share the '45' index;
/// v4 images carry the DOpus label "v4".
List<(String, String?, String?)> _modelQueries(List<String> models) {
  if (models.isEmpty) {
    return const [('45', null, null), ('v3', null, null), ('v5', null, null)];
  }
  return [
    for (final m in models)
      switch (m) {
        'v4' => ('45', 'v4', null),
        'v3' => ('v3', null, null),
        'v5' => ('v5', null, null),
        _ => ('45', null, 'v4'),
      },
  ];
}

/// #4: decoding a big answer (tens of thousands of ids) runs off the UI thread.
List<String> _idsFromBodies(List<List<int>> bodies) {
  final ids = <String>{};
  for (final bytes in bodies) {
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    for (final i in (body['ids'] as List? ?? const [])) {
      ids.add(i.toString());
    }
  }
  return ids.toList();
}

/// Immich asset ids matching every given filter (models are OR'ed, the rest AND). The server
/// (/search ids=1) finds each hit's Immich asset by NTFS file id, never by file name (fork #4).
/// The model requests run at the same time.
Future<List<String>> galleryServerIds({
  List<String> models = const [],
  List<String> chars = const [],
  List<String> labels = const [],
  List<String> mixes = const [],
}) async {
  final responses = await Future.wait([
    for (final (ver, extra, exclude) in _modelQueries(models))
      http
          .get(
            Uri.parse('$kGalleryServer/search').replace(
              queryParameters: {
                'ids': '1',
                'flat': '1',
                if (ver != '45') 'ver': ver,
                if (labels.isNotEmpty || extra != null) 'label': [...labels, ?extra],
                'exclude': ?exclude,
                if (chars.isNotEmpty) 'char': chars,
                if (mixes.isNotEmpty) 'mix': mixes,
              },
            ),
          )
          .timeout(const Duration(seconds: 60)),
  ]);
  final bodies = [
    for (final res in responses)
      if (res.statusCode == 200) res.bodyBytes,
  ];
  return Isolate.run(() => _idsFromBodies(bodies));
}

/// [ids] that this phone has (not trashed), newest first. One query, primary-key lookups only.
Future<List<String>> galleryIdsOrdered(Drift db, List<String> ids) async {
  if (ids.isEmpty) {
    return const [];
  }
  final rows = await db
      .customSelect(
        'SELECT id FROM remote_asset_entity WHERE deleted_at IS NULL '
        'AND id IN (SELECT value FROM json_each(?)) ORDER BY created_at DESC',
        variables: [Variable.withString(jsonEncode(ids))],
        readsFrom: {db.remoteAssetEntity},
      )
      .get();
  return [for (final r in rows) r.read<String>('id')];
}

/// The assets for [ids], in the same order (one page at a time, so the first page shows at once).
Future<List<RemoteAsset>> galleryAssetsByIds(Drift db, List<String> ids) async {
  final byId = <String, RemoteAsset>{};
  for (var i = 0; i < ids.length; i += 500) {
    final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
    final q = db.remoteAssetEntity.select()..where((r) => r.id.isIn(chunk));
    for (final a in await q.map((r) => r.toDto()).get()) {
      byId[a.id] = a;
    }
  }
  return [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
}

String? _cacheKey;
List<String>? _cacheIds;

/// The Immich asset ids (newest first) for a set of gallery filters; the last answer is kept for paging.
Future<List<String>> galleryFilterIds(
  Drift db, {
  required List<String> models,
  required List<String> chars,
  required List<String> labels,
  required List<String> mixes,
}) async {
  final key = jsonEncode([models, chars, labels, mixes]);
  if (key == _cacheKey && _cacheIds != null) {
    return _cacheIds!;
  }
  final found = await galleryServerIds(models: models, chars: chars, labels: labels, mixes: mixes);
  final ids = await galleryIdsOrdered(db, found);
  _cacheKey = key;
  _cacheIds = ids;
  return ids;
}

/// The Immich assets for a set of gallery filters (all of them; prefer [galleryFilterIds] + paging).
Future<List<RemoteAsset>> galleryFilterAssets(
  Drift db, {
  required List<String> models,
  required List<String> chars,
  required List<String> labels,
  required List<String> mixes,
}) async =>
    galleryAssetsByIds(db, await galleryFilterIds(db, models: models, chars: chars, labels: labels, mixes: mixes));

/// #4: the labels of one /label_groups group (e.g. "Body", "Male", "Model / Request type").
final Map<String, List<String>> _groupCache = {};

Future<List<String>> galleryGroupLabels(String group) async {
  final cached = _groupCache[group];
  if (cached != null) {
    return cached;
  }
  Future<void> fill(String text) async {
    final list = jsonDecode(text) as List;
    for (final g in list) {
      _groupCache[g['name'].toString()] = [for (final l in (g['labels'] as List? ?? const [])) l.toString()];
    }
  }

  Future<String> fetch() async {
    final res = await http.get(Uri.parse('$kGalleryServer/label_groups')).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('label_groups ${res.statusCode}');
    }
    return utf8.decode(res.bodyBytes);
  }

  await _diskCached('label_groups', fetch, fill);
  return _groupCache[group] ?? const [];
}

/// Facet lists rarely change: show the copy saved on the phone at once and refresh it in the background
/// (the download is what made the filter sheets slow over mobile data, the server answers in ms).
final Set<String> _refreshed = {};

/// Tests point this at a temp folder.
Future<Directory> Function() galleryCacheDir = getApplicationSupportDirectory;

@visibleForTesting
void galleryFacetCacheReset() {
  _refreshed.clear();
  _facetCache.clear();
  _groupCache.clear();
}

Future<void> _diskCached(String name, Future<String> Function() fetch, Future<void> Function(String) fill) async {
  File? file;
  try {
    file = File('${(await galleryCacheDir()).path}/gallery_$name.json');
  } catch (_) {}
  Future<void> refresh() async {
    final text = await fetch();
    await fill(text);
    try {
      await file?.writeAsString(text);
    } catch (_) {}
  }

  if (file != null && file.existsSync()) {
    try {
      await fill(await file.readAsString());
      if (_refreshed.add(name)) {
        unawaited(refresh().catchError((_) {}));
      }
      return;
    } catch (_) {}
  }
  _refreshed.add(name);
  await refresh();
}

/// Search page open: load the filter lists before the first chip tap.
void galleryPrefetchFacets() {
  unawaited(galleryFacet('labels').then((_) {}, onError: (_) {}));
  unawaited(galleryFacet('chars').then((_) {}, onError: (_) {}));
  unawaited(galleryGroupLabels('Body').then((_) {}, onError: (_) {}));
}

/// Label facet limited to one label group, with the same counts as the Labels chip.
Future<List<GalleryFacetItem>> galleryGroupFacet(String group) async {
  final labels = (await galleryGroupLabels(group)).toSet();
  final all = await galleryFacet('labels');
  final counted = {for (final i in all) i.key};
  return [
    ...all.where((i) => labels.contains(i.key)),
    for (final l in labels)
      if (!counted.contains(l)) GalleryFacetItem(l, l, 0),
  ];
}

final Map<String, List<GalleryFacetItem>> _facetCache = {};

/// 'chars' | 'labels' -> counts merged over the 4.5, V3 and V5 indexes; 'mixes' -> /genmixes with names.
Future<List<GalleryFacetItem>> galleryFacet(String kind) async {
  final cached = _facetCache[kind];
  if (cached != null) {
    return cached;
  }
  await _diskCached('facet_$kind', () async => jsonEncode([for (final i in await _fetchFacet(kind)) i.toJson()]), (
    text,
  ) async {
    final items = [for (final j in jsonDecode(text) as List) GalleryFacetItem.fromJson(j as Map)];
    if (items.isNotEmpty) {
      _facetCache[kind] = items;
    }
  });
  return _facetCache[kind] ?? const [];
}

Future<List<GalleryFacetItem>> _fetchFacet(String kind) async {
  final List<GalleryFacetItem> items;
  if (kind == 'mixes') {
    final res = await http
        .get(Uri.parse('$kGalleryServer/genmixes').replace(queryParameters: {'names': '1', 'artists': '1'}))
        .timeout(const Duration(seconds: 30));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    items = [
      for (final m in (body['all'] as List? ?? const []))
        GalleryFacetItem(
          m['id'].toString(),
          (m['name'] ?? '').toString().isEmpty ? m['id'].toString() : "${m['name']} (${m['id']})",
          (m['count'] as num?)?.toInt() ?? 0,
          search: "${m['name'] ?? ''} ${m['id']} ${m['artists'] ?? ''}",
        ),
    ];
  } else {
    final counts = <String, int>{};
    final responses = await Future.wait([
      for (final ver in const ['', 'v3', 'v5'])
        http
            .get(Uri.parse('$kGalleryServer/searchfacets').replace(queryParameters: {if (ver.isNotEmpty) 'ver': ver}))
            .timeout(const Duration(seconds: 60)),
    ]);
    for (final res in responses) {
      if (res.statusCode != 200) {
        continue;
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final m = body[kind] as Map<String, dynamic>? ?? const {};
      for (final e in m.entries) {
        counts[e.key] = (counts[e.key] ?? 0) + ((e.value as num?)?.toInt() ?? 0);
      }
    }
    items = [for (final e in counts.entries) GalleryFacetItem(e.key, e.key, e.value)];
  }
  items.sort((a, b) => b.count.compareTo(a.count));
  if (items.isEmpty) {
    throw Exception('no $kind from the gallery server');
  }
  return items;
}

/// Searchable multi-select list for a gallery facet (or a fixed list such as the models).
class GalleryFacetPicker extends StatefulWidget {
  const GalleryFacetPicker({super.key, required this.load, required this.initial, required this.onChanged});

  final Future<List<GalleryFacetItem>> Function() load;
  final Set<String> initial;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<GalleryFacetPicker> createState() => _GalleryFacetPickerState();
}

class _GalleryFacetPickerState extends State<GalleryFacetPicker> {
  late final Set<String> _selected = {...widget.initial};
  final _query = TextEditingController();
  List<GalleryFacetItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget
          .load()
          .then((v) {
            if (mounted) {
              setState(() => _items = v);
            }
          })
          .catchError((Object e) {
            if (mounted) {
              setState(() => _error = "Gallery server not reachable ($e)");
            }
          }),
    );
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(16), child: Text(_error!));
    }
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // every typed word must appear (artist names, mix name or id), e.g. "riz scia"
    final words = _query.text.trim().toLowerCase().split(RegExp(r'[\s,]+')).where((w) => w.isNotEmpty).toList();
    final shown = [
      ...items.where((i) => _selected.contains(i.key)),
      ...items.where((i) => !_selected.contains(i.key) && words.every(i.search.contains)),
    ];
    return Column(
      children: [
        if (items.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Filter",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final item = shown[i];
              return CheckboxListTile(
                dense: true,
                value: _selected.contains(item.key),
                title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                secondary: item.count > 0 ? Text("${item.count}") : null,
                onChanged: (v) {
                  setState(() => v == true ? _selected.add(item.key) : _selected.remove(item.key));
                  widget.onChanged({..._selected});
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
