// Custom fork: widgets for the search filters, in-album search bar and album folders.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/presentation/widgets/album/album_folder_bar.widget.dart';
import 'package:immich_mobile/presentation/widgets/album/album_search_bar.widget.dart';
import 'package:immich_mobile/providers/album/album_search.provider.dart';
import 'package:immich_mobile/widgets/search/search_filter/display_option_picker.dart';

import '../unit/factories/remote_album_factory.dart';
import '../unit/presentation/presentation_context.dart';

void main() {
  late PresentationContext context;

  setUp(() async => context = await PresentationContext.create());
  tearDown(() => context.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  group('DisplayOptionPicker', () {
    testWidgets('Not favorite and Favorite exclude each other', (tester) async {
      Map<DisplayOption, bool> last = {};
      await tester.pumpTestWidget(
        context,
        DisplayOptionPicker(
          onSelect: (value) => last = value,
          filter: const SearchDisplayFilters(isNotInAlbum: false, isArchive: false, isFavorite: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('display_option_not_favorite')));
      await tester.pumpAndSettle();
      expect(last[DisplayOption.notFavorite], isTrue);
      expect(last[DisplayOption.favorite], isFalse);

      await tester.tap(find.text('Favorite'));
      await tester.pumpAndSettle();
      expect(last[DisplayOption.favorite], isTrue);
      expect(last[DisplayOption.notFavorite], isFalse);
    });
  });

  group('AlbumSearchBar', () {
    testWidgets('typing updates the album query after a short pause; back closes search', (tester) async {
      late WidgetRef ref;
      await tester.pumpTestWidget(
        context,
        Consumer(
          builder: (_, r, _) {
            ref = r;
            // keep the autoDispose provider alive like the album page does
            r.watch(albumSearchQueryProvider('album-1'));
            return const AlbumSearchBar(albumId: 'album-1');
          },
        ),
      );
      ref.read(albumSearchQueryProvider('album-1').notifier).state = '';
      await tester.pump();

      await tester.enterText(find.byKey(const Key('album_search_field')), 'nobara');
      await tester.pump(const Duration(milliseconds: 100));
      expect(ref.read(albumSearchQueryProvider('album-1')), '', reason: 'debounced, not yet applied');
      await tester.pump(const Duration(milliseconds: 200));
      expect(ref.read(albumSearchQueryProvider('album-1')), 'nobara');

      await tester.enterText(find.byKey(const Key('album_search_field')), 'nobara smile');
      await tester.pump(const Duration(milliseconds: 300));
      expect(ref.read(albumSearchQueryProvider('album-1')), 'nobara smile');
      // a different album is not affected
      expect(ref.read(albumSearchQueryProvider('album-2')), isNull);

      await tester.tap(find.byKey(const Key('album_search_close')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(ref.read(albumSearchQueryProvider('album-1')), isNull);
    });
  });

  group('AlbumFolderBar', () {
    final albums = <RemoteAlbum>[
      RemoteAlbumFactory.create(name: 'Ditto v5'),
      RemoteAlbumFactory.create(name: 'Ditto v4.5 pinned'),
      RemoteAlbumFactory.create(name: 'Nobara'),
    ];

    Future<FolderFilter Function()> pumpBar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      FolderFilter selected;
      await tester.pumpTestWidget(
        context,
        StatefulBuilder(
          builder: (_, setState) => CustomScrollView(
            slivers: [
              AlbumFolderBar(albums: albums, selected: selected, onSelected: (v) => setState(() => selected = v)),
              SliverToBoxAdapter(
                child: Consumer(
                  builder: (context, ref, _) => TextButton(
                    key: const Key('move_first'),
                    onPressed: () => showMoveAlbumToFolderSheet(context, ref, albums.first),
                    child: const Text('move'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      return () => selected;
    }

    testWidgets('create a folder, move an album in, counts update, delete keeps the album', (tester) async {
      final selected = await pumpBar(tester);
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.byKey(const Key('folder_chip_unfiled')), findsNothing);

      // create
      await tester.tap(find.byKey(const Key('folder_chip_new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('folder_name_field')), ' Ditto stuff ');
      await tester.tap(find.byKey(const Key('folder_name_ok')));
      await settle(tester);

      expect(SettingsRepository.instance.appConfig.album.folderNames, ['Ditto stuff']);
      expect(selected(), 'Ditto stuff');
      expect(find.text('Ditto stuff (0)'), findsOneWidget);
      expect(find.text('No folder (3)'), findsOneWidget);

      // move the first album in
      await tester.tap(find.byKey(const Key('move_first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('move_to_Ditto stuff')));
      await settle(tester);

      expect(SettingsRepository.instance.appConfig.album.folderMap, {albums.first.id: 'Ditto stuff'});
      expect(find.text('Ditto stuff (1)'), findsOneWidget);
      expect(find.text('No folder (2)'), findsOneWidget);

      // delete the folder: album survives, mapping is gone, selection falls back to All
      await tester.longPress(find.byKey(const ValueKey('folder_chip_Ditto stuff')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('folder_delete')));
      await settle(tester);

      expect(SettingsRepository.instance.appConfig.album.folderNames, isEmpty);
      expect(SettingsRepository.instance.appConfig.album.folderMap, isEmpty);
      expect(selected(), isNull);
      expect(find.text('All (3)'), findsOneWidget);
    });

    testWidgets('new folder straight from the move sheet', (tester) async {
      await pumpBar(tester);
      await tester.tap(find.byKey(const Key('move_first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('move_to_new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('folder_name_field')), 'Chars');
      await tester.tap(find.byKey(const Key('folder_name_ok')));
      await settle(tester);

      expect(SettingsRepository.instance.appConfig.album.folderNames, ['Chars']);
      expect(SettingsRepository.instance.appConfig.album.folderMap, {albums.first.id: 'Chars'});
      expect(find.text('Chars (1)'), findsOneWidget);
    });
  });
}
