// Custom fork: in-album search.
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

/// Which field the in-album search matches (Both / Name / Description).
final albumSearchFieldProvider = StateProvider.autoDispose.family<AlbumSearchField, String>(
  (ref, albumId) => AlbumSearchField.both,
);
