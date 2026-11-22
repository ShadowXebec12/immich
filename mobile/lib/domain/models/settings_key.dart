import 'package:flutter/material.dart';
import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/log.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/models/value_codec.dart';
import 'package:immich_mobile/providers/album/album_sort_by_options.provider.dart';
import 'package:immich_mobile/utils/semver.dart';

enum SettingsKey<T> {
  // Theme
  themePrimaryColor<ImmichColorPreset>(codec: EnumCodec(ImmichColorPreset.values)),
  themeMode<ThemeMode>(codec: EnumCodec(ThemeMode.values)),
  themeDynamic<bool>(),
  themeColorfulInterface<bool>(),

  // Image
  imagePreferRemote<bool>(),
  imageLoadOriginal<bool>(),

  // Viewer
  viewerLoopVideo<bool>(),
  viewerLoadOriginalVideo<bool>(),
  viewerAutoPlayVideo<bool>(),
  viewerTapToNavigate<bool>(),
  // Custom fork: viewer gesture -> action pairs
  viewerGestures<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  viewerLabelHistory<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  viewerLabelPins<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  // Custom fork: last Generate sheet gen [preset title, i2i strength] and grid label badges "label=text=color"
  viewerLastGen<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  viewerLabelBadges<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  // Custom fork (#4): photos queued for one gen job ("immichId|name") and the full last Generate settings (JSON)
  viewerGenQueue<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  viewerLastGenOptions<String?>(),
  viewerConfirmPcMove<bool>(),

  // Network
  networkAutoEndpointSwitching<bool>(),
  networkExternalEndpointList<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  networkCustomHeaders<Map<String, String>>(codec: MapCodec(PrimitiveCodec.string, PrimitiveCodec.string)),
  networkPreferredWifiName<String?>(),
  networkLocalEndpoint<String?>(),

  // Album
  albumSortMode<AlbumSortMode>(codec: EnumCodec(AlbumSortMode.values)),
  albumIsReverse<bool>(),
  albumIsGrid<bool>(),
  // Custom fork: local album folders. albumId -> folder name, plus the folder list (keeps empty folders).
  albumFolderMap<Map<String, String>>(codec: MapCodec(PrimitiveCodec.string, PrimitiveCodec.string)),
  albumFolderNames<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  // Custom fork: ids of recently opened albums, newest first
  albumRecentIds<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  // Custom fork: ids of albums whose photos are sorted by file name
  albumNameSortIds<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  // Custom fork: ids of albums pinned to the top of the album search sheet
  albumPinnedIds<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  // Custom fork: two-finger swipe up opens the album search sheet
  albumSwipeSearch<bool>(),
  // Custom fork: ids of albums kept offline (thumbnails + previews saved on the phone)
  albumOfflineIds<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  // Custom fork (#4): album photos were last added to, and albums queued to play as one slideshow
  albumLastAddedId<String?>(),
  albumSlideshowQueue<List<String>>(codec: ListCodec(PrimitiveCodec.string)),

  // Backup
  backupEnabled<bool>(),
  backupUseCellularForVideos<bool>(),
  backupUseCellularForPhotos<bool>(),
  backupRequireCharging<bool>(),
  backupTriggerDelay<int>(),
  backupSyncAlbums<bool>(),

  // Timeline
  timelineTilesPerRow<int>(),
  timelineGroupAssetsBy<GroupAssetsBy>(codec: EnumCodec(GroupAssetsBy.values)),
  timelineStorageIndicator<bool>(),
  // Custom fork: tile width/height in percent. 0 = upstream square cropped tiles.
  timelineTileAspectPercent<int>(),

  // Log
  logLevel<LogLevel>(codec: EnumCodec(LogLevel.values)),

  // Map
  mapShowFavoriteOnly<bool>(),
  mapRelativeDate<int>(),
  mapCustomFrom<DateTime?>(),
  mapCustomTo<DateTime?>(),
  mapIncludeArchived<bool>(),
  mapThemeMode<ThemeMode>(codec: EnumCodec(ThemeMode.values)),
  mapWithPartners<bool>(),

  // Cleanup
  cleanupKeepFavorites<bool>(),
  cleanupKeepMediaType<AssetKeepType>(codec: EnumCodec(AssetKeepType.values)),
  cleanupKeepAlbumIds<List<String>>(codec: ListCodec(PrimitiveCodec.string)),
  cleanupCutoffDaysAgo<int>(),
  cleanupDefaultsInitialized<bool>(),

  // Share
  shareFileType<ShareAssetType>(codec: EnumCodec(ShareAssetType.values)),

  // Slideshow
  slideshowRepeat<bool>(),
  slideshowDuration<int>(),
  slideshowLook<SlideshowLook>(codec: EnumCodec(SlideshowLook.values)),
  slideshowDirection<SlideshowDirection>(codec: EnumCodec(SlideshowDirection.values)),

  // Custom fork: laptop data store. Both keys stay on this phone and are never synced.
  laptopSyncServerUrl<String>(),
  laptopSyncSettingsStamp<String>(),

  // Feature message
  featureMessageSeenRelease<SemVer>(codec: SemVerCodec());

  final ValueCodec<T>? _codecOverride;

  const SettingsKey({ValueCodec<T>? codec}) : _codecOverride = codec;

  ValueCodec<T> get _codec => _codecOverride ?? ValueCodec.forType(T);

  String encode(T value) => _codec.encode(value);

  T decode(String raw) => _codec.decode(raw);
}
