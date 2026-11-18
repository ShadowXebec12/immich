// Custom fork: copy the file names of the selected photos to the clipboard.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/presentation/actions/action.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';

/// One name per line, in the order the photos were selected, no trailing line break.
String joinAssetNames(Iterable<BaseAsset> assets) => assets.map((asset) => asset.name).join('\n');

class CopyNamesAction extends AssetActionBuilder {
  const CopyNamesAction({required super.source});

  @override
  ActionItem? create(BuildContext context, WidgetRef ref) {
    final count = ref.watch(assetsActionProvider(source).select((assets) => assets.length));
    if (count == 0) {
      return null;
    }

    return .new(
      icon: Icons.copy_all_rounded,
      label: count == 1 ? "Copy name" : "Copy names",
      onAction: () async {
        final assets = ref.read(assetsActionProvider(source)).toList(growable: false);
        if (assets.isEmpty) {
          return;
        }
        final toastService = ref.read(toastServiceProvider);
        final clearSelection = ref.read(clearSelectionProvider(source));
        await Clipboard.setData(ClipboardData(text: joinAssetNames(assets)));
        toastService.success(assets.length == 1 ? "Copied 1 file name" : "Copied ${assets.length} file names");
        clearSelection();
      },
    );
  }
}
