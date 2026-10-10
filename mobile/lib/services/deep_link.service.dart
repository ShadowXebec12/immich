import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/memory.model.dart';
import 'package:immich_mobile/domain/models/user.model.dart';
import 'package:immich_mobile/domain/services/asset.service.dart' as beta_asset_service;
import 'package:immich_mobile/domain/services/memory.service.dart';
import 'package:immich_mobile/domain/services/people.service.dart';
import 'package:immich_mobile/domain/services/remote_album.service.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart' as beta_asset_provider;
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/timeline_prime.dart';
import 'package:immich_mobile/utils/wildcard_match.dart';

final deepLinkServiceProvider = Provider(
  (ref) => DeepLinkService(
    ref.watch(timelineFactoryProvider),
    ref.watch(beta_asset_provider.assetServiceProvider),
    ref.watch(remoteAlbumServiceProvider),
    MemoryService(ref.watch(driftProvider).memoryRepository),
    ref.watch(peopleServiceProvider),
    ref.watch(currentUserProvider),
  ),
);

class DeepLinkService {
  final TimelineFactory _betaTimelineFactory;
  final beta_asset_service.AssetService _betaAssetService;
  final RemoteAlbumService _betaRemoteAlbumService;
  final MemoryService _betaMemoryService;
  final PeopleService _betaPeopleService;

  final UserDto? _currentUser;

  const DeepLinkService(
    this._betaTimelineFactory,
    this._betaAssetService,
    this._betaRemoteAlbumService,
    this._betaMemoryService,
    this._betaPeopleService,
    this._currentUser,
  );

  Future<PageRouteInfo?> handleScheme(PlatformDeepLink link, WidgetRef ref) async {
    // get everything after the scheme, since Uri cannot parse path
    final intent = link.uri.host;
    final queryParams = link.uri.queryParameters;

    return switch (intent) {
      "memory" => await _buildMemoryDeepLink(queryParams['id']),
      "asset" => await _buildAssetDeepLink(queryParams['id'] ?? '', ref),
      // Custom fork: albums can also be opened by name, e.g. immichcustom://album?name=ditto*v5
      "album" => await _buildAlbumDeepLink(queryParams['id'] ?? '', name: queryParams['name']),
      // Custom fork: immichcustom://slideshow?album=<name or id>
      "slideshow" => await _buildSlideshowDeepLink(queryParams['album'] ?? queryParams['name'] ?? ''),
      "people" => await _buildPeopleDeepLink(queryParams['id'] ?? ''),
      "activity" => await _buildActivityDeepLink(queryParams['albumId'] ?? ''),
      _ => null,
    };
  }

  Future<PageRouteInfo?> handleMyImmichApp(PlatformDeepLink link, WidgetRef ref) async {
    final path = link.uri.path;

    const uuidRegex = r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
    final assetRegex = RegExp('/photos/($uuidRegex)');
    final albumRegex = RegExp('/albums/($uuidRegex)');
    final peopleRegex = RegExp('/people/($uuidRegex)');

    if (assetRegex.hasMatch(path)) {
      final assetId = assetRegex.firstMatch(path)?.group(1) ?? '';
      // /albums/<albumId>/photos/<assetId> links carry the album context,
      // which drives the like/comment UI in the viewer
      final albumId = albumRegex.firstMatch(path)?.group(1);
      return _buildAssetDeepLink(assetId, ref, albumId: albumId);
    }
    if (albumRegex.hasMatch(path)) {
      final albumId = albumRegex.firstMatch(path)?.group(1) ?? '';
      return _buildAlbumDeepLink(albumId);
    }
    if (peopleRegex.hasMatch(path)) {
      final peopleId = peopleRegex.firstMatch(path)?.group(1) ?? '';
      return _buildPeopleDeepLink(peopleId);
    }

    return null;
  }

  Future<PageRouteInfo?> _buildMemoryDeepLink(String? memoryId) async {
    List<Memory> memories = [];

    if (memoryId == null) {
      if (_currentUser == null) {
        return null;
      }

      memories = await _betaMemoryService.getMemoryLane(_currentUser.id);
    } else {
      final memory = await _betaMemoryService.get(memoryId);
      if (memory != null) {
        memories = [memory];
      }
    }

    if (memories.isEmpty) {
      return null;
    }

    return MemoryRoute(memories: memories, memoryIndex: 0);
  }

  Future<PageRouteInfo?> _buildAssetDeepLink(String assetId, WidgetRef ref, {String? albumId}) async {
    final asset = await _betaAssetService.getRemoteAsset(assetId);
    if (asset == null) {
      return null;
    }

    final album = albumId != null ? await _betaRemoteAlbumService.get(albumId) : null;

    AssetViewer.setAsset(ref, asset);
    return AssetViewerRoute(
      initialIndex: 0,
      timelineService: _betaTimelineFactory.fromAssets([asset], TimelineOrigin.deepLink),
      currentAlbum: album,
    );
  }

  Future<PageRouteInfo?> _buildAlbumDeepLink(String albumId, {String? name}) async {
    final album = albumId.isNotEmpty ? await _betaRemoteAlbumService.get(albumId) : await _findAlbum(name ?? '');

    if (album == null) {
      return null;
    }

    return RemoteAlbumRoute(album: album);
  }

  // Custom fork: album by id, exact name (ignoring case), or first wildcard match
  Future<RemoteAlbum?> _findAlbum(String idOrName) async {
    final wanted = idOrName.trim();
    if (wanted.isEmpty) {
      return null;
    }

    final byId = await _betaRemoteAlbumService.get(wanted);
    if (byId != null) {
      return byId;
    }

    final albums = await _betaRemoteAlbumService.getAll();
    return albums.firstWhereOrNull((a) => a.name.toLowerCase() == wanted.toLowerCase()) ??
        albums.firstWhereOrNull((a) => wildcardMatch(a.name, wanted));
  }

  Future<PageRouteInfo?> _buildSlideshowDeepLink(String idOrName) async {
    final album = await _findAlbum(idOrName);
    if (album == null) {
      return null;
    }

    final timeline = _betaTimelineFactory.remoteAlbum(albumId: album.id);
    if (!await primeTimeline(timeline)) {
      await timeline.dispose();
      return null;
    }

    return SlideshowRoute(timeline: timeline);
  }

  Future<PageRouteInfo?> _buildActivityDeepLink(String albumId) async {
    final album = await _betaRemoteAlbumService.get(albumId);

    if (album == null || album.isActivityEnabled == false) {
      return null;
    }

    return ActivitiesRoute(album: album);
  }

  Future<PageRouteInfo?> _buildPeopleDeepLink(String personId) async {
    final person = await _betaPeopleService.get(personId);

    if (person == null) {
      return null;
    }

    return PersonRoute(person: person);
  }
}
