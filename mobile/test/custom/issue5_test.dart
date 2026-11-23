import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/album_filter_sheet.dart';
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/gallery_search.dart';
import 'package:immich_mobile/custom/info_description.dart';
import 'package:immich_mobile/custom/search_facets.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/providers/album/album_search.provider.dart';

RemoteAlbum album(int i, String name) => RemoteAlbum(
  id: 'a$i',
  name: name,
  ownerId: 'o',
  description: '',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isActivityEnabled: false,
  order: AlbumAssetOrder.desc,
  assetCount: 1,
  ownerName: 'o',
  isShared: false,
);

Future<void> phone(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  group('#6 gallery address follows Immich', () {
    test('Tailscale on mobile data', () {
      expect(galleryServerFor('http://100.101.102.103:2283/api'), 'http://100.101.102.103:8899');
      expect(galleryServerFor('http://my-pc.tail1234.ts.net:2283/api'), 'http://my-pc.tail1234.ts.net:8899');
    });
    test('errors name the kind of failure', () {
      expect(galleryErrorText(TimeoutException('x')), contains('timed out'));
      expect(galleryErrorText(http.ClientException('Connection refused')), contains('Connection refused'));
    });
    test('home Wi-Fi', () => expect(galleryServerFor('http://192.168.1.4:2283/api'), 'http://192.168.1.4:8899'));
    test('anything else stays on the home address', () {
      for (final e in [null, '', 'https://photos.example.com/api', 'http://100.200.1.1:2283/api']) {
        expect(galleryServerFor(e), kGalleryLan);
      }
    });
  });

  group('facet order', () {
    test('saved first, unknown dropped, missing appended', () {
      final o = orderedFacetIds(['mixes', 'nope', 'albums', 'mixes']);
      expect(o.take(2), ['mixes', 'albums']);
      expect(o.length, kSearchFacets.length);
      expect(o.toSet().length, kSearchFacets.length);
    });
  });

  group('album filter', () {
    test('label chip cycles include, exclude, off', () {
      var (i, e) = cycleLabel(const [], const [], 'x');
      expect([i, e], [['x'], <String>[]]);
      (i, e) = cycleLabel(i, e, 'x');
      expect([i, e], [<String>[], ['x']]);
      (i, e) = cycleLabel(i, e, 'x');
      expect([i, e], [<String>[], <String>[]]);
    });
    test('includes are AND, excludes subtract, nothing outside the album', () {
      expect(
        albumFilterIds({'1', '2', '3'}, [['1', '2', '9'], ['2', '3', '1']], ['1']),
        ['2'],
      );
      expect(albumFilterIds({'1', '2'}, const [], ['2']), ['1']);
    });
    test('json round trip and when the full filter is needed', () {
      const f = AlbumFilter(labels: ['a', 'b'], exclude: ['c'], chars: ['d'], labelAny: true, favorites: true, dateFrom: '2026-01-01');
      final back = AlbumFilter.fromJson(f.toJson());
      expect(back.toJson(), f.toJson());
      expect(back.activeCount, 6);
      expect(const AlbumFilter(labels: ['a', 'b']).needsFullFilter, isFalse);
      expect(const AlbumFilter(labels: ['a', 'b'], labelAny: true).needsFullFilter, isTrue);
      expect(const AlbumFilter(exclude: ['a']).needsFullFilter, isTrue);
    });

    testWidgets('sheet at iPhone width: tabs, chip states, Apply', (t) async {
      await phone(t);
      AlbumFilter? result;
      final groups = [
        for (var g = 0; g < 16; g++)
          LabelGroup(g == 0 ? 'Pose' : 'A very long group name $g', [for (var l = 0; l < 40; l++) 'label $g $l with a long name']),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<AlbumFilter>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => SizedBox(
                        height: 740,
                        child: AlbumFilterSheet(
                          initial: const AlbumFilter(),
                          loadGroups: () async => groups,
                          loadCounts: () async => {'label 0 0 with a long name': 12345},
                          loadFacet: (k) async => [GalleryFacetItem('$k one', '$k one', 3)],
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('album_filter_label_label 0 0 with a long name')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('album_filter_label_label 0 1 with a long name')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('album_filter_label_label 0 1 with a long name')));
      await t.pump();
      await t.tap(find.byKey(const Key('album_filter_fav')));
      await t.pump();
      await t.tap(find.byKey(const Key('album_filter_apply')));
      await t.pumpAndSettle();
      expect(result!.labels, ['label 0 0 with a long name']);
      expect(result!.exclude, ['label 0 1 with a long name']);
      expect(result!.favorites, isTrue);
      expect(t.takeException(), isNull);
    });
  });

  group('info description', () {
    final longPrompt = List.generate(120, (i) => i.isEven ? '1.30::averyveryverylongunbrokenprompttoken$i::,' : '').join('\n');
    final albums = [for (var i = 0; i < 15; i++) album(i, 'album with an extremely long name that must never spill ${'x' * 60} $i')];

    Widget view({required bool open, required List<RemoteAlbum> list, ValueChanged<bool>? toggle}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InfoDescriptionView(
            text: longPrompt,
            open: open,
            onToggle: toggle ?? (_) {},
            albums: list,
            copy: const SizedBox(width: 70, height: 30),
            onAlbum: (_) {},
          ),
        ),
      ),
    );

    test('folded text drops blank lines', () => expect(foldedDescription('a,\n\n  \n b\n'), 'a,\nb'));

    testWidgets('no overflow folded or open, 15 long album names, 390 wide', (t) async {
      await phone(t);
      for (final open in [false, true]) {
        await t.pumpWidget(view(open: open, list: albums));
        await t.pump();
        expect(t.takeException(), isNull);
      }
      final desc = t.getRect(find.byKey(const ValueKey('info_description_text')));
      final col = t.getRect(find.byKey(const ValueKey('info_albums')));
      expect(desc.right, lessThanOrEqualTo(col.left));
      expect(col.right, lessThanOrEqualTo(390));
      expect(find.text('+9 more'), findsOneWidget);
    });

    testWidgets('read-only and folds', (t) async {
      await phone(t);
      bool? toggled;
      await t.pumpWidget(view(open: false, list: const [], toggle: (v) => toggled = v));
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SelectableText), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('info_description_toggle')));
      expect(toggled, isTrue);
    });
  });
}
