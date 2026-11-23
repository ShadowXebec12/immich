import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/info_description.dart';
import 'package:immich_mobile/custom/prompt_info.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/appears_in_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/asset_owner_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/date_time_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/drag_handle.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/location_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/people_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/rating_details.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_details/technical_details.widget.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/asset.provider.dart';

class AssetDetails extends ConsumerWidget {
  final BaseAsset asset;
  final double minHeight;

  const AssetDetails({super.key, required this.asset, required this.minHeight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exifInfo = ref.watch(assetExifProvider(asset)).valueOrNull;

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            offset: const Offset(0, -3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            // Custom fork (#4): description (with Copy) and the NAI prompt sections first, like the
            // mix gallery's Prompt sheet; Immich's own details stay below, folded.
            InfoDescription(asset: asset, text: exifInfo?.description ?? ''),
            PromptInfoSections(asset: asset),
            const Divider(height: 1),
            ExpansionTile(
              key: const ValueKey('info_immich_details'),
              title: const Text("Details", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text("Date, people, location, camera, albums", style: TextStyle(fontSize: 12)),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DateTimeDetails(asset: asset, exifInfo: exifInfo),
                AssetOwnerDetails(asset: asset),
                PeopleDetails(asset: asset),
                LocationDetails(asset: asset, exifInfo: exifInfo),
                TechnicalDetails(asset: asset, exifInfo: exifInfo),
                RatingDetails(exifInfo: exifInfo),
                AppearsInDetails(asset: asset),
              ],
            ),
            SizedBox(height: context.padding.bottom + 48),
          ],
        ),
      ),
    );
  }
}
