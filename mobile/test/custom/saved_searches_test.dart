import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/presentation/widgets/album/recent_albums.widget.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/remote_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/custom/saved_searches.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('saved_search_test');
    SavedSearchStore.dir = () async => tmp;
    SavedSearchStore.instance
      ..bookmarks = []
      ..history = [];
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  final q = {
    'filename': 'weiss',
    'chars': ['weiss schnee'],
    'labels': ['cowgirl', 'from behind'],
    'mixes': ['M12'],
    'models': ['v5'],
    'albumIds': ['a1', 'a2'],
    'albumMatchAny': true,
    'favorite': true,
    'rating': 5,
    'media': 'image',
  };

  test('search round-trips through json', () {
    final f = searchFromJson(q);
    expect(f.galChars, ['weiss schnee']);
    expect(f.galLabels, ['cowgirl', 'from behind']);
    expect(f.albumMatchAny, isTrue);
    expect(f.display.isFavorite, isTrue);
    expect(f.mediaType, AssetType.image);
    expect(searchToJson(f), q);
  });

  test('history: newest first, no duplicates, capped', () {
    var h = <Map<String, Object?>>[];
    for (var i = 0; i < 40; i++) {
      h = pushSearchHistory(h, {'filename': '$i'});
    }
    h = pushSearchHistory(h, {'filename': '35'});
    expect(h.length, kSearchHistoryLimit);
    expect(h.first['filename'], '35');
    expect(h.where((x) => x['filename'] == '35').length, 1);
  });

  testWidgets('bookmark dialog saves; Bookmarks tab lists, opens and deletes it (iPhone size)', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Map? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => bookmarkSearchDialog(context, searchFromJson(q)),
              child: const Text('bm'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('bm'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bookmark_name')), 'weiss cowgirl');
    await tester.tap(find.byKey(const ValueKey('bookmark_save')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(SavedSearchStore.instance.bookmarks.single.name, 'weiss cowgirl');
    expect(File('${tmp.path}/saved_searches.json').existsSync(), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedSearchList(bookmarks: true, onOpen: (x) => opened = x),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('weiss cowgirl'), findsOneWidget);
    await tester.tap(find.text('weiss cowgirl'));
    expect(opened?['chars'], ['weiss schnee']);
    await tester.tap(find.byKey(const ValueKey('bookmark_delete_weiss cowgirl')));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookmarks_empty')), findsOneWidget);
  });

  testWidgets('Searches tab shows history and empty bookmark dialog refuses an empty search', (tester) async {
    await tester.runAsync(() => SavedSearchStore.instance.addHistory(searchFromJson({'labels': ['cowgirl']})));
    Map? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SavedSearchList(bookmarks: false, onOpen: (x) => opened = x)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search_history_0')));
    expect(opened?['labels'], ['cowgirl']);
  });

  testWidgets('history button opens 3 tabs: Bookmarks, Searches, Recent albums (iPhone size)', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SavedSearchStore.instance.bookmarks = [SavedSearch('my bm', {'labels': ['cowgirl']})];
    SavedSearchStore.instance.history = [{'chars': ['weiss schnee']}];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig()),
          remoteAlbumProvider.overrideWith(_NoAlbums.new),
        ],
        child: const MaterialApp(home: Scaffold(body: Center(child: RecentAlbumsButton()))),
      ),
    );
    await tester.tap(find.byKey(const Key('recent_albums_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tab_bookmarks')), findsOneWidget);
    expect(find.byKey(const Key('tab_searches')), findsOneWidget);
    expect(find.byKey(const Key('recent_albums_empty')), findsOneWidget); // opens on Recent albums
    await tester.tap(find.byKey(const Key('tab_bookmarks')));
    await tester.pumpAndSettle();
    expect(find.text('my bm'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab_searches')));
    await tester.pumpAndSettle();
    expect(find.text('chars: weiss schnee'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _NoAlbums extends RemoteAlbumNotifier {
  @override
  RemoteAlbumState build() => const RemoteAlbumState(albums: []);
  @override
  Future<void> refresh() async {}
}
