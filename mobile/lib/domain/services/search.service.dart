import 'package:immich_mobile/domain/models/asset/base_asset.model.dart' hide AssetVisibility;
import 'package:immich_mobile/domain/models/search_result.model.dart';
import 'package:immich_mobile/extensions/asset_extensions.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/search_api.repository.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart' hide AssetVisibility, SearchFilter;

class SearchService {
  final _log = Logger("SearchService");
  final SearchApiRepository _searchApiRepository;

  SearchService(this._searchApiRepository);

  Future<List<String>?> getSearchSuggestions(
    SearchSuggestionType type, {
    String? country,
    String? state,
    String? make,
    String? model,
  }) async {
    try {
      return await _searchApiRepository.getSearchSuggestions(
        type,
        country: country,
        state: state,
        make: make,
        model: model,
      );
    } catch (e) {
      _log.warning("Failed to get search suggestions", e);
    }
    return [];
  }

  // Custom fork: the server only does "in all albums", so "in any album" runs one search per album
  // and merges the pages (newest first, duplicates dropped).
  Future<SearchResult?> _searchAnyAlbum(SearchFilter filter, int page) async {
    final responses = await Future.wait(
      filter.albumIds.map((id) => _searchApiRepository.search(filter.copyWith(albumIds: [id]), page)),
    );

    final seen = <String>{};
    final assets = <BaseAsset>[];
    int? nextPage;
    for (final response in responses) {
      if (response == null) {
        continue;
      }
      for (final item in response.assets.items) {
        if (seen.add(item.id)) {
          assets.add(item.toDto());
        }
      }
      if (response.assets.nextPage != null) {
        nextPage = page + 1;
      }
    }

    if (assets.isEmpty) {
      return null;
    }

    assets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return SearchResult(assets: assets, nextPage: nextPage);
  }

  Future<SearchResult?> search(SearchFilter filter, int page) async {
    try {
      if (filter.albumMatchAny && filter.albumIds.length > 1) {
        return await _searchAnyAlbum(filter, page);
      }

      final response = await _searchApiRepository.search(filter, page);

      if (response == null || response.assets.items.isEmpty) {
        return null;
      }

      return SearchResult(
        assets: response.assets.items.map((e) => e.toDto()).toList(),
        nextPage: response.assets.nextPage?.toInt(),
      );
    } catch (error, stackTrace) {
      _log.severe("Failed to search for assets", error, stackTrace);
    }
    return null;
  }
}
