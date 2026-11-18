// Custom fork: album sorted by file name runs against the real (in-memory) database.
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/data/db/main/table/remote/album.drift.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.drift.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/infrastructure/repositories/timeline.repository.dart';

import '../medium/repository_context.dart';

void main() {
  late MediumRepositoryContext ctx;
  late TimelineRepository sut;
  late String albumId;
  late String otherAlbumId;
  late String ownerId;

  Future<void> addAsset(String name, {String? album, DateTime? createdAt, bool deleted = false}) async {
    final asset = await ctx.newRemoteAsset(
      ownerId: ownerId,
      createdAt: createdAt,
      deletedAt: deleted ? DateTime(2026) : null,
    );
    await (ctx.db.update(
      ctx.db.remoteAssetEntity,
    )..where((t) => t.id.equals(asset.id))).write(RemoteAssetEntityCompanion(name: Value(name)));
    await ctx.newRemoteAlbumAsset(albumId: album ?? albumId, assetId: asset.id);
  }

  Future<void> setOrder(AlbumAssetOrder order) => (ctx.db.update(
    ctx.db.remoteAlbumEntity,
  )..where((t) => t.id.equals(albumId))).write(RemoteAlbumEntityCompanion(order: Value(order)));

  Future<List<String>> names({int offset = 0, int count = 100}) async {
    final assets = await sut.remoteAlbumByName(albumId).assetSource(offset, count);
    return assets.map((a) => a.name).toList();
  }

  setUp(() async {
    ctx = MediumRepositoryContext();
    sut = TimelineRepository(ctx.db);
    ownerId = (await ctx.newUser()).id;
    albumId = (await ctx.newRemoteAlbum(name: 'A', ownerId: ownerId)).id;
    otherAlbumId = (await ctx.newRemoteAlbum(name: 'B', ownerId: ownerId)).id;

    // dates deliberately out of name order
    await addAsset('b nobara.png', createdAt: DateTime(2026, 1, 1));
    await addAsset('A asa.png', createdAt: DateTime(2026, 1, 3));
    await addAsset('c makise.png', createdAt: DateTime(2025, 6, 1));
    await addAsset('写真.png', createdAt: DateTime(2026, 2, 1));
    await addAsset('aa deleted.png', deleted: true);
    await addAsset('0 other album.png', album: otherAlbumId);
  });

  tearDown(() => ctx.dispose());

  test('oldest-first album order = A-Z, ignoring case, no deleted, no other album', () async {
    await setOrder(AlbumAssetOrder.asc);
    expect(await names(), ['A asa.png', 'b nobara.png', 'c makise.png', '写真.png']);
  });

  test('newest-first album order = Z-A', () async {
    await setOrder(AlbumAssetOrder.desc);
    expect(await names(), ['写真.png', 'c makise.png', 'b nobara.png', 'A asa.png']);
  });

  test('one flat bucket with the full count, and paging', () async {
    await setOrder(AlbumAssetOrder.asc);
    final buckets = await sut.remoteAlbumByName(albumId).bucketSource().first;
    expect(buckets.fold<int>(0, (sum, b) => sum + b.assetCount), 4);
    expect(await names(offset: 0, count: 2), ['A asa.png', 'b nobara.png']);
    expect(await names(offset: 2, count: 2), ['c makise.png', '写真.png']);
    expect(await names(offset: 4, count: 2), isEmpty);
  });
}
