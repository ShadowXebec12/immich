// Custom fork: in-album search runs against the real (in-memory) database.
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.drift.dart';
import 'package:immich_mobile/data/db/main/table/remote/exif.drift.dart';
import 'package:immich_mobile/infrastructure/repositories/timeline.repository.dart';

import '../medium/repository_context.dart';

void main() {
  late MediumRepositoryContext ctx;
  late TimelineRepository sut;
  late String albumId;
  late String otherAlbumId;
  late String ownerId;

  Future<String> addAsset(
    String name, {
    String? description,
    String? album,
    DateTime? createdAt,
    bool deleted = false,
  }) async {
    final asset = await ctx.newRemoteAsset(
      ownerId: ownerId,
      createdAt: createdAt,
      deletedAt: deleted ? DateTime(2026) : null,
    );
    await (ctx.db.update(
      ctx.db.remoteAssetEntity,
    )..where((t) => t.id.equals(asset.id))).write(RemoteAssetEntityCompanion(name: Value(name)));
    if (description != null) {
      await ctx.db
          .into(ctx.db.remoteExifEntity)
          .insert(RemoteExifEntityCompanion(assetId: Value(asset.id), description: Value(description)));
    }
    await ctx.newRemoteAlbumAsset(albumId: album ?? albumId, assetId: asset.id);
    return asset.id;
  }

  Future<List<String>> search(String query, {String? album, int offset = 0, int count = 100}) async {
    final assets = await sut.remoteAlbumSearch(album ?? albumId, query).assetSource(offset, count);
    return assets.map((a) => a.name).toList();
  }

  Future<int> total(String query) async {
    final buckets = await sut.remoteAlbumSearch(albumId, query).bucketSource().first;
    return buckets.fold<int>(0, (sum, b) => sum + b.assetCount);
  }

  setUp(() async {
    ctx = MediumRepositoryContext();
    sut = TimelineRepository(ctx.db);
    ownerId = (await ctx.newUser()).id;
    albumId = (await ctx.newRemoteAlbum(name: 'Nobara', ownerId: ownerId)).id;
    otherAlbumId = (await ctx.newRemoteAlbum(name: 'Other', ownerId: ownerId)).id;

    await addAsset('1girl, nobara kugisaki, smile s-111.png', createdAt: DateTime(2026, 1, 3));
    await addAsset('1girl, nobara kugisaki, angry s-222_1.png', createdAt: DateTime(2026, 1, 2));
    await addAsset(
      'landscape [test] {x} s-333.png',
      description: 'beach sunset, nobara in the distance',
      createdAt: DateTime(2026, 1, 1),
    );
    await addAsset('写真 nobara s-444.png', createdAt: DateTime(2025, 12, 31));
    await addAsset('deleted nobara s-555.png', deleted: true);
    await addAsset('1girl, nobara kugisaki, smile s-999.png', album: otherAlbumId);
  });

  tearDown(() => ctx.dispose());

  test('matches file names, newest first, only inside this album and not deleted', () async {
    expect(await search('kugisaki'), [
      '1girl, nobara kugisaki, smile s-111.png',
      '1girl, nobara kugisaki, angry s-222_1.png',
    ]);
    expect(await total('kugisaki'), 2);
  });

  test('matches the description too', () async {
    expect(await search('sunset'), ['landscape [test] {x} s-333.png']);
    // name OR description per word
    expect(await search('nobara'), hasLength(4));
    expect(await total('nobara'), 4);
  });

  test('every word must match, in any order, ignoring case', () async {
    expect(await search('SMILE Nobara'), ['1girl, nobara kugisaki, smile s-111.png']);
    expect(await search('smile angry'), isEmpty);
    expect(await total('smile angry'), 0);
  });

  test('wildcards and literal special characters', () async {
    expect(await search('nobara*angry'), ['1girl, nobara kugisaki, angry s-222_1.png']);
    expect(await search('s-?11'), ['1girl, nobara kugisaki, smile s-111.png']);
    // _ and % are literal, not SQL wildcards
    expect(await search('222_1'), ['1girl, nobara kugisaki, angry s-222_1.png']);
    expect(await search('2_2'), isEmpty);
    expect(await search('%'), isEmpty);
    expect(await search('[test] {x}'), ['landscape [test] {x} s-333.png']);
    expect(await search("o'brien"), isEmpty);
  });

  test('non-ASCII', () async {
    expect(await search('写真'), ['写真 nobara s-444.png']);
  });

  test('paging with offset and count', () async {
    final all = await search('nobara');
    expect(await search('nobara', offset: 0, count: 2), all.sublist(0, 2));
    expect(await search('nobara', offset: 2, count: 2), all.sublist(2, 4));
    expect(await search('nobara', offset: 4, count: 2), isEmpty);
  });

  test('other album is searched separately', () async {
    expect(await search('smile', album: otherAlbumId), ['1girl, nobara kugisaki, smile s-999.png']);
  });
}
