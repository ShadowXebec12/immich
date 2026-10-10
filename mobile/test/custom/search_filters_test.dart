// Custom fork: non-favorites filter, album filter, "in any album" merging.
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart' hide AssetVisibility;
import 'package:immich_mobile/domain/services/search.service.dart';
import 'package:immich_mobile/infrastructure/repositories/search_api.repository.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openapi/api.dart' hide SearchFilter;

class _MockSearchApi extends Mock implements SearchApi {}

class _MockSearchApiRepository extends Mock implements SearchApiRepository {}

SearchFilter _filter({
  bool isFavorite = false,
  bool isNotFavorite = false,
  List<String> albumIds = const [],
  bool albumMatchAny = false,
  String? context,
}) => SearchFilter(
  context: context,
  people: const {},
  location: const SearchLocationFilter(),
  camera: const SearchCameraFilter(),
  date: const SearchDateFilter(),
  rating: const SearchRatingFilter(),
  display: SearchDisplayFilters(
    isNotInAlbum: false,
    isArchive: false,
    isFavorite: isFavorite,
    isNotFavorite: isNotFavorite,
  ),
  mediaType: AssetType.other,
  albumIds: albumIds,
  albumMatchAny: albumMatchAny,
);

AssetResponseDto _asset(String id, DateTime created) => AssetResponseDto(
  checksum: 'c$id',
  createdAt: created,
  duration: 0,
  fileCreatedAt: created,
  fileModifiedAt: created,
  hasMetadata: true,
  height: 1216,
  id: id,
  isArchived: false,
  isEdited: false,
  isFavorite: false,
  isOffline: false,
  isTrashed: false,
  localDateTime: created,
  originalFileName: '$id.png',
  originalPath: '/import/$id.png',
  ownerId: 'owner',
  thumbhash: null,
  type: AssetTypeEnum.IMAGE,
  updatedAt: created,
  visibility: AssetVisibility.timeline,
  width: 832,
);

SearchResponseDto _response(List<AssetResponseDto> items, {String? nextPage}) => SearchResponseDto(
  albums: SearchAlbumResponseDto(count: 0, total: 0),
  assets: SearchAssetResponseDto(
    count: items.length,
    items: items,
    nextCursor: null,
    nextPage: nextPage,
    total: items.length,
  ),
);

void main() {
  setUpAll(() {
    registerFallbackValue(MetadataSearchDto());
    registerFallbackValue(SmartSearchDto());
    registerFallbackValue(_filter());
  });

  group('SearchFilter.isEmpty', () {
    test('album filter or non-favorite filter alone is a real search', () {
      expect(_filter().isEmpty, isTrue);
      expect(_filter(albumIds: ['a']).isEmpty, isFalse);
      expect(_filter(isNotFavorite: true).isEmpty, isFalse);
    });
  });

  group('SearchApiRepository request', () {
    late _MockSearchApi api;
    late SearchApiRepository sut;

    setUp(() {
      api = _MockSearchApi();
      sut = SearchApiRepository(api);
      when(() => api.searchAssets(any())).thenAnswer((_) async => _response([]));
      when(() => api.searchSmart(any())).thenAnswer((_) async => _response([]));
    });

    Future<MetadataSearchDto> sent(SearchFilter filter) async {
      await sut.search(filter, 1);
      return verify(() => api.searchAssets(captureAny())).captured.single as MetadataSearchDto;
    }

    test('favorite: true / false / not sent', () async {
      expect((await sent(_filter(isFavorite: true))).isFavorite, const Optional<bool?>.present(true));
      expect((await sent(_filter(isNotFavorite: true))).isFavorite, const Optional<bool?>.present(false));
      expect((await sent(_filter())).isFavorite.isPresent, isFalse);
    });

    test('album ids are sent only when chosen', () async {
      expect((await sent(_filter(albumIds: ['a', 'b']))).albumIds.orElse(null), ['a', 'b']);
      expect((await sent(_filter())).albumIds.isPresent, isFalse);
    });

    test('smart (context) search carries the same filters', () async {
      await sut.search(_filter(context: 'beach', isNotFavorite: true, albumIds: ['a']), 2);
      final dto = verify(() => api.searchSmart(captureAny())).captured.single as SmartSearchDto;
      expect(dto.isFavorite, const Optional<bool?>.present(false));
      expect(dto.albumIds.orElse(null), ['a']);
    });
  });

  group('SearchService "in any album"', () {
    late _MockSearchApiRepository repo;
    late SearchService sut;
    final d1 = DateTime(2026, 1, 1);
    final d2 = DateTime(2026, 1, 2);
    final d3 = DateTime(2026, 1, 3);

    setUp(() {
      repo = _MockSearchApiRepository();
      sut = SearchService(repo);
    });

    test('one request per album, merged newest first without duplicates', () async {
      when(() => repo.search(any(), any())).thenAnswer((invocation) async {
        final filter = invocation.positionalArguments[0] as SearchFilter;
        return switch (filter.albumIds.single) {
          'a' => _response([_asset('x', d1), _asset('shared', d2)], nextPage: '2'),
          'b' => _response([_asset('shared', d2), _asset('y', d3)]),
          _ => _response([]),
        };
      });

      final result = await sut.search(_filter(albumIds: ['a', 'b', 'c'], albumMatchAny: true), 1);

      expect(result!.assets.map((a) => (a as RemoteAsset).id), ['y', 'shared', 'x']);
      expect(result.nextPage, 2);
      final filters = verify(() => repo.search(captureAny(), 1)).captured.cast<SearchFilter>();
      expect(filters.map((f) => f.albumIds), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('no next page once every album is exhausted; null when nothing found', () async {
      when(() => repo.search(any(), any())).thenAnswer((_) async => _response([_asset('x', d1)]));
      expect((await sut.search(_filter(albumIds: ['a', 'b'], albumMatchAny: true), 3))!.nextPage, isNull);

      when(() => repo.search(any(), any())).thenAnswer((_) async => _response([]));
      expect(await sut.search(_filter(albumIds: ['a', 'b'], albumMatchAny: true), 1), isNull);
    });

    test('"in all albums" (default) and a single album stay one request', () async {
      when(() => repo.search(any(), any())).thenAnswer((_) async => _response([_asset('x', d1)]));

      await sut.search(_filter(albumIds: ['a', 'b']), 1);
      await sut.search(_filter(albumIds: ['a'], albumMatchAny: true), 1);

      final filters = verify(() => repo.search(captureAny(), 1)).captured.cast<SearchFilter>();
      expect(filters.map((f) => f.albumIds), [
        ['a', 'b'],
        ['a'],
      ]);
    });
  });
}
