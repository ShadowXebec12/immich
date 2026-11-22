import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immich_mobile/custom/gallery_search.dart';

void main() {
  late Directory tmp;
  var calls = 0;
  var online = true;
  final client = MockClient((req) async {
    calls++;
    if (!online) {
      throw const SocketException('offline');
    }
    if (req.url.path == '/searchfacets') {
      return http.Response(
        jsonEncode({
          'labels': {'cowgirl': 3, 'chubby': 2},
        }),
        200,
      );
    }
    if (req.url.path == '/label_groups') {
      return http.Response(
        jsonEncode([
          {
            'name': 'Body',
            'labels': ['chubby'],
          },
        ]),
        200,
      );
    }
    return http.Response('{}', 404);
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('facet_cache');
    galleryCacheDir = () async => tmp;
    galleryFacetCacheReset();
    calls = 0;
    online = true;
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('first load downloads and saves; next app start reads the phone copy even offline', () async {
    await http.runWithClient(() async {
      final first = await galleryFacet('labels');
      expect(first.first.key, 'cowgirl');
      expect(first.first.count, 9); // 3 indexes x 3
      expect(File('${tmp.path}/gallery_facet_labels.json').existsSync(), isTrue);
      await galleryGroupLabels('Body');

      galleryFacetCacheReset(); // = app restart
      online = false;
      calls = 0;
      final again = await galleryFacet('labels');
      expect(again.map((i) => i.key), ['cowgirl', 'chubby']);
      final body = await galleryGroupFacet('Body');
      expect(body.single.key, 'chubby');
    }, () => client);
  });

  test('saved copy is refreshed in the background once per app start', () async {
    await http.runWithClient(() async {
      await galleryFacet('labels');
      galleryFacetCacheReset();
      calls = 0;
      await galleryFacet('labels');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 3); // one background refresh (3 indexes)
      await galleryFacet('labels');
      expect(calls, 3); // memory hit, no more requests
    }, () => client);
  });
}
