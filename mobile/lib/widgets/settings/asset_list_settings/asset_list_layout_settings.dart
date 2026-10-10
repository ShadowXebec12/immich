import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/widgets/settings/setting_group_title.dart';
import 'package:immich_mobile/widgets/settings/settings_slider_list_tile.dart';

class LayoutSettings extends HookConsumerWidget {
  const LayoutSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tilesPerRow = useState(ref.watch(appConfigProvider.select((s) => s.timeline.tilesPerRow)));
    useValueChanged<int, void>(tilesPerRow.value, (_, _) {
      unawaited(ref.read(settingsProvider).write(.timelineTilesPerRow, tilesPerRow.value));
    });
    final tileAspectPercent = ref.watch(appConfigProvider.select((s) => s.timeline.tileAspectPercent));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingGroupTitle(title: context.t.asset_list_layout_sub_title, icon: Icons.view_module_outlined),
        SettingsSliderListTile(
          valueNotifier: tilesPerRow,
          text: context.t.theme_setting_asset_list_tiles_per_row_title(count: tilesPerRow.value),
          label: "${tilesPerRow.value}",
          maxValue: 6,
          minValue: 2,
          noDivisons: 4,
          onChangeEnd: (value) {
            ref.invalidate(appSettingsServiceProvider);
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text("Thumbnail shape"),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (percent, label) in kTileShapes)
                  ChoiceChip(
                    key: ValueKey('tile_shape_$percent'),
                    label: Text(label),
                    selected: tileAspectPercent == percent,
                    onSelected: (_) => unawaited(ref.read(settingsProvider).write(.timelineTileAspectPercent, percent)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Custom fork. Tile width/height in percent. 0 keeps upstream square cropped tiles;
// anything else shows the whole image in a tile of that shape.
const kTileShapes = [(0, "Square (cropped)"), (100, "Square (full)"), (75, "3:4"), (67, "2:3"), (56, "9:16")];
