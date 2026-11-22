// Custom fork #4: fast gallery name lookup, Generate page bodies, Info panel sections, move groups.
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:immich_mobile/data/db/main/table/remote/asset.drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/custom/gallery_search.dart';
import 'package:immich_mobile/custom/gen_menu.dart';
import 'package:immich_mobile/custom/prompt_info.dart';
import 'package:immich_mobile/custom/slideshow_queue.dart';

import '../medium/repository_context.dart';

void main() {
  group('gallery ids by names', () {
    late MediumRepositoryContext ctx;

    setUp(() async {
      ctx = MediumRepositoryContext();
      final owner = (await ctx.newUser()).id;
      final seed = await ctx.newRemoteAsset(ownerId: owner);
      // clone the seed row into a big library (like the phone's), names "file <n>.png"
      final cols = [
        for (final r in await ctx.db.customSelect('PRAGMA table_info(remote_asset_entity)').get())
          r.read<String>('name'),
      ];
      String pick(String c) => switch (c) {
        'id' => "'id' || n",
        'name' => "'File ' || n || '.png'",
        'checksum' => "'c' || n",
        'created_at' => "strftime('%Y-%m-%dT%H:%M:%S.000', 1700000000 + n, 'unixepoch')",
        'deleted_at' => "CASE WHEN n % 1000 = 7 THEN created_at ELSE NULL END",
        _ => c,
      };
      await ctx.db.customStatement(
        'WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 120000) '
        'INSERT INTO remote_asset_entity (${cols.join(', ')}) '
        'SELECT ${cols.map(pick).join(', ')} FROM seq, remote_asset_entity WHERE id = ?',
        [seed.id],
      );
    });

    tearDown(() async => ctx.db.close());

    test('45k server ids ordered in one query, newest first, trashed and unknown left out', () async {
      final names = [for (var n = 1; n <= 45000; n++) 'id$n', 'not-on-this-phone'];
      final sw = Stopwatch()..start();
      final ids = await galleryIdsOrdered(ctx.db, names);
      sw.stop();
      // ids 1..45000 minus the trashed ones (n % 1000 == 7 -> 45 of them)
      expect(ids.length, 45000 - 45);
      expect(ids.first, 'id45000');
      expect(ids.contains('id7'), isFalse);
      // ignore: avoid_print
      print('galleryIdsOrdered 45k of 120k rows: ${sw.elapsedMilliseconds} ms');
      expect(sw.elapsedMilliseconds, lessThan(5000));

      final page = await galleryAssetsByIds(ctx.db, ids.sublist(0, 300));
      expect(page.map((a) => a.id).toList(), ids.sublist(0, 300));
      expect(await galleryIdsOrdered(ctx.db, const []), isEmpty);
    });
  });

  group('generate page', () {
    test('i2i + ref sends strength and cref only when the toggle is on', () {
      final o = GenOptions()
        ..preset = 'i2i + ref'
        ..strength = 0.6
        ..char = 'makise kurisu';
      var b = o.body({'immich_id': 'a', 'name': 'x.png'});
      expect(b['mode'], 'i2i');
      expect(b['strength'], '0.60');
      expect(b['char'], 'makise kurisu');
      expect(b.containsKey('cref'), isFalse);
      o
        ..cref = true
        ..crefStrength = 0.8;
      b = o.body(const {});
      expect(b['cref'], 1);
      expect(b['cref_strength'], '0.80');
      expect(b.containsKey('immich_id'), isFalse);
    });

    test('i2i ignores char and mix; regen extras go through', () {
      final o = GenOptions()
        ..preset = 'i2i'
        ..char = 'x'
        ..mixId = 'M1'
        ..model = 'v5'
        ..count = 3
        ..extraTags = 'smile'
        ..extraTarget = 'female';
      final b = o.body(const {});
      expect(b.containsKey('char'), isFalse);
      expect(b.containsKey('mix_id'), isFalse);
      expect(b['model'], 'v5');
      expect(b['count'], '3');
      expect(b['extra_tags_target'], 'female');
    });

    test('last settings round-trip and summary', () {
      final o = GenOptions()
        ..preset = 'Char ref'
        ..char = 'nobara'
        ..mixId = 'U09XXC'
        ..crefMode = 'style';
      final back = lastGenOptions(jsonEncode(o.toJson()))!;
      expect(back.preset, 'Char ref');
      expect(back.crefMode, 'style');
      expect(back.summary, 'Char ref, nobara, mix U09XXC');
      expect(lastGenOptions('not json'), isNull);
      expect(lastGenOptions('{"preset":"gone"}')!.preset, 'Regen');
    });

    test('gen queue entries split into items', () {
      expect(genQueueItems(['id1|a b|c.png', 'bad']), [
        {'immich_id': 'id1', 'name': 'a b|c.png'},
      ]);
    });
  });

  group('info panel sections', () {
    test('order, female / male boxes, artists line, empties dropped', () {
      final blocks = promptBlocks({
        'sections': {
          'artist_mix': {
            'text': 'artist:a, artist:b',
            'sequence': ['a', 'b'],
          },
          'char_boxes': [
            {'gender': 'female', 'text': 'girl, weiss'},
            {'gender': 'male', 'text': 'boy, dark skin'},
          ],
          'male': 'ignored when a male box exists',
          'body': 'huge ass',
          'face': '',
          'sex_acts': 'doggystyle',
          'clothes': 'thong',
        },
      });
      expect(blocks.map((b) => b.title).toList(), ['Mix', 'Female char box', 'Male box', 'Body', 'Sex acts', 'Clothes']);
      expect(blocks.first.sub, 'Artists: a, b');
      expect(blocks[2].text, 'boy, dark skin');
    });

    test('no male box falls back to the male section', () {
      final blocks = promptBlocks({
        'sections': {'male': 'muscular male'},
      });
      expect(blocks.single.title, 'Male box');
    });
  });

  test('slideshow queue toggles keep order', () {
    expect(toggleQueued(['a', 'b'], 'c'), ['a', 'b', 'c']);
    expect(toggleQueued(['a', 'b', 'c'], 'b'), ['a', 'c']);
  });
}
