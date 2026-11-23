// Custom fork: in-album search.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/gallery_search.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/infrastructure/repositories/timeline.repository.dart';

/// Search text per album id. `null` = search bar closed, '' = open but empty.
final albumSearchQueryProvider = StateProvider.autoDispose.family<String?, String>((ref, albumId) => null);

/// Custom fork: DOpus labels the album is filtered by (all must match), from the PC gallery server.
final albumSearchLabelsProvider = StateProvider.autoDispose.family<List<String>, String>((ref, albumId) => const []);

/// The album's assets carrying every label; key = (albumId, labels joined by ).
final albumLabelAssetsProvider = FutureProvider.autoDispose.family<List<RemoteAsset>, (String, String)>((ref, key) async {
  final (albumId, joined) = key;
  final labels = joined.split('').where((l) => l.isNotEmpty).toList();
  final db = ref.watch(driftProvider);
  final ids = await galleryFilterIds(db, models: const [], chars: const [], labels: labels, mixes: const []);
  final q = db.remoteAlbumAssetEntity.selectOnly()
    ..addColumns([db.remoteAlbumAssetEntity.assetId])
    ..where(db.remoteAlbumAssetEntity.albumId.equals(albumId));
  final inAlbum = {for (final row in await q.get()) row.read(db.remoteAlbumAssetEntity.assetId)!};
  return galleryAssetsByIds(db, ids.where(inAlbum.contains).toList());
});

/// #5: the album's Filters sheet. Included labels live in [albumSearchLabelsProvider]; this holds the rest.
class AlbumFilter {
  const AlbumFilter({
    this.labels = const [],
    this.exclude = const [],
    this.chars = const [],
    this.mixes = const [],
    this.models = const [],
    this.labelAny = false,
    this.favorites = false,
    this.dateFrom = '',
    this.dateTo = '',
  });

  final List<String> labels;
  final List<String> exclude;
  final List<String> chars;
  final List<String> mixes;
  final List<String> models;
  final bool labelAny;
  final bool favorites;
  final String dateFrom;
  final String dateTo;

  AlbumFilter copyWith({
    List<String>? labels,
    List<String>? exclude,
    List<String>? chars,
    List<String>? mixes,
    List<String>? models,
    bool? labelAny,
    bool? favorites,
    String? dateFrom,
    String? dateTo,
  }) => AlbumFilter(
    labels: labels ?? this.labels,
    exclude: exclude ?? this.exclude,
    chars: chars ?? this.chars,
    mixes: mixes ?? this.mixes,
    models: models ?? this.models,
    labelAny: labelAny ?? this.labelAny,
    favorites: favorites ?? this.favorites,
    dateFrom: dateFrom ?? this.dateFrom,
    dateTo: dateTo ?? this.dateTo,
  );

  AlbumFilter withLabels(List<String> value) => copyWith(labels: value);

  /// Anything beyond included labels.
  bool get hasExtras =>
      exclude.isNotEmpty ||
      chars.isNotEmpty ||
      mixes.isNotEmpty ||
      models.isNotEmpty ||
      favorites ||
      dateFrom.isNotEmpty ||
      dateTo.isNotEmpty;

  /// Plain "all of these labels" keeps using the existing, cached label query.
  bool get needsFullFilter => hasExtras || (labelAny && labels.length > 1);

  int get activeCount =>
      labels.length +
      exclude.length +
      chars.length +
      mixes.length +
      models.length +
      (favorites ? 1 : 0) +
      (dateFrom.isEmpty ? 0 : 1) +
      (dateTo.isEmpty ? 0 : 1);

  Map<String, Object?> toJson() => {
    'labels': labels,
    'exclude': exclude,
    'chars': chars,
    'mixes': mixes,
    'models': models,
    'labelAny': labelAny,
    'favorites': favorites,
    'dateFrom': dateFrom,
    'dateTo': dateTo,
  };

  static AlbumFilter fromJson(Map j) {
    List<String> l(String k) => [for (final v in (j[k] as List? ?? const [])) v.toString()];
    return AlbumFilter(
      labels: l('labels'),
      exclude: l('exclude'),
      chars: l('chars'),
      mixes: l('mixes'),
      models: l('models'),
      labelAny: j['labelAny'] == true,
      favorites: j['favorites'] == true,
      dateFrom: (j['dateFrom'] ?? '').toString(),
      dateTo: (j['dateTo'] ?? '').toString(),
    );
  }
}

final albumFilterProvider = StateProvider.autoDispose.family<AlbumFilter, String>((ref, albumId) => const AlbumFilter());

(String, String) albumFilterKey(String albumId, AlbumFilter f) => (albumId, jsonEncode(f.toJson()));

/// [inAlbum] kept by each include list (AND), minus [excluded]. Pure, so it can be tested.
List<String> albumFilterIds(Set<String> inAlbum, List<List<String>> includes, List<String> excluded) {
  var out = inAlbum;
  for (final list in includes) {
    out = out.intersection(list.toSet());
  }
  return out.difference(excluded.toSet()).toList();
}

/// Full filter. An exclude is fetched as "photos with that label" and subtracted, so a filter with only
/// excludes never downloads the id of every image over mobile data.
final albumFilteredAssetsProvider = FutureProvider.autoDispose.family<List<RemoteAsset>, (String, String)>((
  ref,
  key,
) async {
  final (albumId, json) = key;
  final f = AlbumFilter.fromJson(jsonDecode(json) as Map);
  final db = ref.watch(driftProvider);
  final q = db.remoteAlbumAssetEntity.selectOnly()
    ..addColumns([db.remoteAlbumAssetEntity.assetId])
    ..where(db.remoteAlbumAssetEntity.albumId.equals(albumId));
  final inAlbum = {for (final row in await q.get()) row.read(db.remoteAlbumAssetEntity.assetId)!};
  final andLabels = f.labelAny ? const <String>[] : f.labels;
  final hasMain =
      andLabels.isNotEmpty ||
      f.chars.isNotEmpty ||
      f.mixes.isNotEmpty ||
      f.models.isNotEmpty ||
      f.dateFrom.isNotEmpty ||
      f.dateTo.isNotEmpty;
  final answers = await Future.wait([
    if (hasMain)
      galleryServerIds(
        models: f.models,
        chars: f.chars,
        labels: andLabels,
        mixes: f.mixes,
        dateFrom: f.dateFrom,
        dateTo: f.dateTo,
      ),
    if (f.labelAny && f.labels.isNotEmpty) galleryServerIds(labels: f.labels, labelAny: true),
    if (f.exclude.isNotEmpty) galleryServerIds(labels: f.exclude, labelAny: true),
  ]);
  final excluded = f.exclude.isNotEmpty ? answers.last : const <String>[];
  final includes = f.exclude.isNotEmpty ? answers.sublist(0, answers.length - 1) : answers;
  final ids = await galleryIdsOrdered(db, albumFilterIds(inAlbum, includes, excluded));
  final assets = await galleryAssetsByIds(db, ids);
  return f.favorites ? assets.where((a) => a.isFavorite).toList() : assets;
});

/// Which field the in-album search matches (Both / Name / Description).
final albumSearchFieldProvider = StateProvider.autoDispose.family<AlbumSearchField, String>(
  (ref, albumId) => AlbumSearchField.both,
);
