import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/gallery_search.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/search_result.model.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/domain/services/search.service.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/providers/infrastructure/search.provider.dart';

final searchPreFilterProvider = NotifierProvider<SearchFilterProvider, SearchFilter?>(SearchFilterProvider.new);

class SearchFilterProvider extends Notifier<SearchFilter?> {
  @override
  SearchFilter? build() {
    return null;
  }

  void setFilter(SearchFilter? filter) {
    state = filter;
  }

  void clear() {
    state = null;
  }
}

class SearchState {
  final List<BaseAsset> assets;
  final int? nextPage;
  final bool isLoading;

  const SearchState({this.assets = const [], this.nextPage = 1, this.isLoading = false});
}

final paginatedSearchProvider = StateNotifierProvider<PaginatedSearchNotifier, SearchState>(
  (ref) => PaginatedSearchNotifier(ref.watch(searchServiceProvider), ref.watch(driftProvider)),
);

class PaginatedSearchNotifier extends StateNotifier<SearchState> {
  final SearchService _searchService;
  final Drift _db;
  final _assetCountController = StreamController<int>.broadcast();

  PaginatedSearchNotifier(this._searchService, this._db) : super(const SearchState());

  Stream<int> get assetCount => _assetCountController.stream;

  Future<void> search(SearchFilter filter) async {
    if (state.nextPage == null || state.isLoading) {
      return;
    }

    state = SearchState(assets: state.assets, nextPage: state.nextPage, isLoading: true);

    SearchResult? result;
    try {
      result = filter.hasGallery ? await _galleryPage(filter, state.nextPage!) : await _searchService.search(filter, state.nextPage!);
    } catch (_) {
      result = null;
    }

    if (result == null) {
      state = SearchState(assets: state.assets, nextPage: state.nextPage);
      return;
    }

    final known = {for (final asset in state.assets) asset.heroTag};
    final assets = [...state.assets, ...result.assets.where((asset) => known.add(asset.heroTag))];
    state = SearchState(assets: assets, nextPage: result.nextPage);

    _assetCountController.add(assets.length);
  }

  static const _kGalleryPage = 300;

  // Custom fork: model / character / label / mix filters come from the PC gallery server. With no
  // other filter the matching assets are paged straight from the local list; otherwise the normal
  // server search runs and its pages are cut down to the matching assets.
  Future<SearchResult?> _galleryPage(SearchFilter filter, int page) async {
    final assets = await galleryFilterAssets(
      _db,
      models: filter.galModels,
      chars: filter.galChars,
      labels: filter.galLabels,
      mixes: filter.galMixes,
    );
    final native = filter.copyWith(galModels: [], galChars: [], galLabels: [], galMixes: []);
    if (native.isEmpty) {
      final start = (page - 1) * _kGalleryPage;
      if (start >= assets.length) {
        return null;
      }
      final end = start + _kGalleryPage > assets.length ? assets.length : start + _kGalleryPage;
      return SearchResult(assets: assets.sublist(start, end), nextPage: end < assets.length ? page + 1 : null);
    }
    final allowed = {for (final a in assets) a.id};
    var p = page;
    for (var tries = 0; tries < 20; tries++) {
      final r = await _searchService.search(native, p);
      if (r == null) {
        return null;
      }
      final kept = r.assets.where((a) => allowed.contains(a.remoteId)).toList();
      if (kept.isNotEmpty || r.nextPage == null) {
        return SearchResult(assets: kept, nextPage: r.nextPage);
      }
      p = r.nextPage!;
    }
    return SearchResult(assets: const [], nextPage: p);
  }

  void clear() {
    state = const SearchState();
    _assetCountController.add(0);
  }

  @override
  void dispose() {
    unawaited(_assetCountController.close());
    super.dispose();
  }
}
