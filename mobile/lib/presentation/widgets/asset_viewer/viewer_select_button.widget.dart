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
    // #3: the viewer's copy of a photo can be a different object than the grid's: match by id
    final match = _selected.where((a) => a.heroTag == widget.asset.heroTag).firstOrNull;
    final isSelected = match != null;
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
          onPressed: () => isSelected
              ? container.read(multiSelectProvider.notifier).deselectAsset(match)
              : container.read(multiSelectProvider.notifier).selectAsset(widget.asset),
          icon: Icon(
            isSelected ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
            color: isSelected ? Colors.lightBlueAccent : null,
            size: isSelected ? 28 : null,
          ),
        ),
      ],
    );
  }
}

/// #3: always-visible mark on the photo when it is in the grid selection (top bar may be hidden).
class ViewerSelectedBadge extends ConsumerStatefulWidget {
  const ViewerSelectedBadge({super.key, required this.asset});

  final BaseAsset? asset;

  @override
  ConsumerState<ViewerSelectedBadge> createState() => _ViewerSelectedBadgeState();
}

class _ViewerSelectedBadgeState extends ConsumerState<ViewerSelectedBadge> {
  ProviderSubscription<MultiSelectState>? _sub;
  Set<BaseAsset> _selected = const {};

  @override
  void initState() {
    super.initState();
    final container = ref.read(viewerSelectContainerProvider);
    _sub = container?.listen<MultiSelectState>(multiSelectProvider, (_, next) {
      if (mounted) {
        setState(() => _selected = next.selectedAssets);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    if (asset == null || !_selected.any((a) => a.heroTag == asset.heroTag)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            key: const Key('viewer_selected_badge'),
            margin: const EdgeInsets.only(left: 12, top: 60),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.lightBlueAccent, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: Colors.black),
                const SizedBox(width: 4),
                Text(
                  "Selected (${_selected.length})",
                  style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
