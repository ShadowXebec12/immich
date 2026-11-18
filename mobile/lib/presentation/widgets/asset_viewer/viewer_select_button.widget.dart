// Custom fork: select/deselect the current photo from the viewer, like the mix gallery viewer.
// The viewer runs in its own provider scope, so the grid's selection lives in another container:
// the grid stores that container in [viewerSelectContainerProvider] before it opens the viewer.
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';

/// Container that owns the selection of the grid the viewer was opened from.
final viewerSelectContainerProvider = StateProvider<ProviderContainer?>((ref) => null);

class ViewerSelectButton extends ConsumerStatefulWidget {
  const ViewerSelectButton({super.key, required this.asset});

  final BaseAsset asset;

  @override
  ConsumerState<ViewerSelectButton> createState() => _ViewerSelectButtonState();
}

class _ViewerSelectButtonState extends ConsumerState<ViewerSelectButton> {
  ProviderSubscription<MultiSelectState>? _sub;
  Set<BaseAsset> _selected = const {};

  @override
  void initState() {
    super.initState();
    final container = ref.read(viewerSelectContainerProvider);
    if (container != null) {
      _sub = container.listen<MultiSelectState>(
        multiSelectProvider,
        (_, next) {
          if (mounted) {
            setState(() => _selected = next.selectedAssets);
          }
        },
        fireImmediately: true,
      );
    }
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final container = ref.watch(viewerSelectContainerProvider);
    if (container == null || _sub == null) {
      return const SizedBox.shrink();
    }
    final isSelected = _selected.contains(widget.asset);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selected.isNotEmpty)
          IconButton(
            key: const Key('viewer_clear_selection'),
            tooltip: "Clear selection",
            onPressed: () => container.read(multiSelectProvider.notifier).reset(),
            icon: const Icon(Icons.cancel_rounded, color: Colors.orange),
          ),
        if (_selected.isNotEmpty)
          Text("${_selected.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        IconButton(
          key: const Key('viewer_select'),
          tooltip: isSelected ? "Deselect" : "Select",
          onPressed: () => container.read(multiSelectProvider.notifier).toggleAssetSelection(widget.asset),
          icon: Icon(isSelected ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded),
        ),
      ],
    );
  }
}
