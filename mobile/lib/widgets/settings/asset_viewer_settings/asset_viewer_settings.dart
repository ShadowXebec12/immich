import 'package:flutter/material.dart';
import 'package:immich_mobile/custom/album_search_sheet.dart';
import 'package:immich_mobile/custom/info_description.dart';
import 'package:immich_mobile/custom/label_badges.dart';
import 'package:immich_mobile/custom/pc_move.dart';
import 'package:immich_mobile/custom/search_facets.dart';
import 'package:immich_mobile/custom/viewer_tools.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/image_viewer_quality_setting.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/image_viewer_tap_to_navigate_setting.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/slideshow_settings.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/video_viewer_settings.dart';
import 'package:immich_mobile/widgets/settings/settings_sub_page_scaffold.dart';

class AssetViewerSettings extends StatelessWidget {
  const AssetViewerSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final assetViewerSetting = [
      const ImageViewerQualitySetting(),
      const ImageViewerTapToNavigateSetting(),
      const ViewerGestureSettings(),
      const DescriptionCollapsedSetting(),
      const SearchFacetOrderTile(),
      const LabelBadgeSettingsTile(),
      const AlbumSwipeSearchSetting(),
      const PcMoveConfirmSetting(),
      const VideoViewerSettings(),
      const SlideshowSettings(),
    ];

    return SettingsSubPageScaffold(settings: assetViewerSetting, showDivider: true);
  }
}
