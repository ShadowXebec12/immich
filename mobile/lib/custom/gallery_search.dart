// Custom fork: search filters answered by the PC gallery server's search index (/search, /searchfacets,
// /genmixes): model version, character, DOpus label, style mix. The server returns file paths; they are
// matched to Immich assets by file name in the app's local database.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';

const kGalleryModels = ['v4.5', 'v4', 'v3', 'v5'];

class GalleryFacetItem {
  const GalleryFacetItem(this.key, this.title, this.count, {String? search}) : _search = search;

  final String key;
  final String title;
  final int count;
  final String? _search;

  /// Lower-case text the picker filter matches: mixes also carry their full artist list.
  String get search => (_search ?? title).toLowerCase();
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

String _baseName(String path) => path.substring(path.lastIndexOf(RegExp(r'[\\/]')) + 1).toLowerCase();

/// Lower-case file names matching every given filter (models are OR'ed, the rest AND).
Future<Set<String>> galleryFileNames({
  List<String> models = const [],
  List<String> chars = const [],
  List<String> labels = const [],
  List<String> mixes = const [],
}) async {
  final names = <String>{};
  final responses = await Future.wait([
    for (final (ver, extra, exclude) in _modelQueries(models))
      http
          .get(
            Uri.parse('$kGalleryServer/search').replace(
              queryParameters: {
                'paths': '1',
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
  for (final res in responses) {
    if (res.statusCode != 200) {
      continue;
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    for (final p in (body['paths'] as List? ?? const [])) {
      names.add(_baseName(p.toString()));
    }
  }
  return names;
}

/// Immich assets (not trashed) whose file name is in [names], newest first.
Future<List<RemoteAsset>> galleryAssets(Drift db, Set<String> names) async {
  final list = names.toList();
  final out = <RemoteAsset>[];
  for (var i = 0; i < list.length; i += 500) {
    final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
    final q = db.remoteAssetEntity.select()..where((r) => r.name.lower().isIn(chunk) & r.deletedAt.isNull());
    out.addAll(await q.map((r) => r.toDto()).get());
  }
  out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return out;
}

String? _cacheKey;
List<RemoteAsset>? _cacheAssets;

/// The Immich assets for a set of gallery filters; the last answer is kept for paging.
Future<List<RemoteAsset>> galleryFilterAssets(
  Drift db, {
  required List<String> models,
  required List<String> chars,
  required List<String> labels,
  required List<String> mixes,
}) async {
  final key = jsonEncode([models, chars, labels, mixes]);
  if (key == _cacheKey && _cacheAssets != null) {
    return _cacheAssets!;
  }
  final names = await galleryFileNames(models: models, chars: chars, labels: labels, mixes: mixes);
  final assets = await galleryAssets(db, names);
  _cacheKey = key;
  _cacheAssets = assets;
  return assets;
}

final Map<String, List<GalleryFacetItem>> _facetCache = {};

/// 'chars' | 'labels' -> counts merged over the 4.5, V3 and V5 indexes; 'mixes' -> /genmixes with names.
Future<List<GalleryFacetItem>> galleryFacet(String kind) async {
  final cached = _facetCache[kind];
  if (cached != null) {
    return cached;
  }
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
            .get(
              Uri.parse('$kGalleryServer/searchfacets').replace(queryParameters: {if (ver.isNotEmpty) 'ver': ver}),
            )
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
  if (items.isNotEmpty) {
    _facetCache[kind] = items;
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
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
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
