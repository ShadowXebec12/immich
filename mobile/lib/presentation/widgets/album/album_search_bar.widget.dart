// Custom fork: search-as-you-type bar shown above an album.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/album_filter_sheet.dart';
import 'package:immich_mobile/custom/gallery_search.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/timeline.repository.dart';
import 'package:immich_mobile/providers/album/album_search.provider.dart';

class AlbumSearchBar extends ConsumerStatefulWidget {
  const AlbumSearchBar({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumSearchBar> createState() => _AlbumSearchBarState();
}

class _AlbumSearchBarState extends ConsumerState<AlbumSearchBar> {
  static const _debounce = Duration(milliseconds: 60);

  final _controller = TextEditingController();
  Timer? _timer;

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted) {
        ref.read(albumSearchQueryProvider(widget.albumId).notifier).state = value;
      }
    });
    setState(() {});
  }

  void _close() {
    _timer?.cancel();
    ref.read(albumSearchQueryProvider(widget.albumId).notifier).state = null;
    ref.read(albumSearchLabelsProvider(widget.albumId).notifier).state = const [];
    ref.read(albumFilterProvider(widget.albumId).notifier).state = const AlbumFilter();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                key: const Key('album_search_close'),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _close,
              ),
              Expanded(
                child: TextField(
                  key: const Key('album_search_field'),
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: "Filter this album (* = anything)",
                    border: InputBorder.none,
                    isDense: true,
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _controller.clear();
                              _onChanged('');
                            },
                          ),
                  ),
                  onChanged: _onChanged,
                ),
              ),
              _FilterButton(albumId: widget.albumId),
              _LabelButton(albumId: widget.albumId),
              _FieldPicker(albumId: widget.albumId),
            ],
          ),
        ),
      ),
    );
  }
}

/// #5: the mix gallery style Filters sheet for this album.
class _FilterButton extends ConsumerWidget {
  const _FilterButton({required this.albumId});

  final String albumId;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final labels = ref.read(albumSearchLabelsProvider(albumId).notifier);
    final filter = ref.read(albumFilterProvider(albumId).notifier);
    final picked = await showAlbumFilterSheet(context, ref, filter.state.withLabels(labels.state));
    if (picked == null) {
      return;
    }
    labels.state = picked.labels;
    filter.state = picked.withLabels(const []);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(albumSearchLabelsProvider(albumId));
    final full = ref.watch(albumFilterProvider(albumId)).withLabels(labels);
    final loading =
        full.needsFullFilter &&
        ref.watch(albumFilteredAssetsProvider(albumFilterKey(albumId, full)).select((a) => a.isLoading));
    final active = full.activeCount;
    return IconButton(
      key: const Key('album_filter_button'),
      tooltip: "Filters",
      visualDensity: VisualDensity.compact,
      onPressed: () => unawaited(_open(context, ref)),
      icon: loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Badge(
              isLabelVisible: active > 0,
              label: Text("$active"),
              child: Icon(Icons.tune_rounded, color: active > 0 ? context.colorScheme.primary : null),
            ),
    );
  }
}

/// Custom fork: filter the album by DOpus labels (PC gallery server).
class _LabelButton extends ConsumerWidget {
  const _LabelButton({required this.albumId});

  final String albumId;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    var picked = ref.read(albumSearchLabelsProvider(albumId)).toSet();
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text("Labels (all must match)", style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Clear")),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Apply")),
              ],
            ),
            Expanded(
              child: GalleryFacetPicker(
                load: () => galleryFacet('labels'),
                initial: picked,
                onChanged: (v) => picked = v,
              ),
            ),
          ],
        ),
      ),
    );
    if (apply == null) {
      return;
    }
    ref.read(albumSearchLabelsProvider(albumId).notifier).state = apply ? picked.toList() : const [];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(albumSearchLabelsProvider(albumId));
    final loading = labels.isNotEmpty &&
        ref.watch(albumLabelAssetsProvider((albumId, labels.join(''))).select((a) => a.isLoading));
    return IconButton(
      key: const Key('album_search_labels'),
      tooltip: "Filter by labels",
      onPressed: () => unawaited(_pick(context, ref)),
      icon: loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Badge(
              isLabelVisible: labels.isNotEmpty,
              label: Text("${labels.length}"),
              child: Icon(Icons.label_outline, color: labels.isNotEmpty ? context.colorScheme.primary : null),
            ),
    );
  }
}

/// Both / Name / Description switch for the in-album filter.
class _FieldPicker extends ConsumerWidget {
  const _FieldPicker({required this.albumId});

  final String albumId;

  static const _labels = {
    AlbumSearchField.both: "Both",
    AlbumSearchField.name: "Name",
    AlbumSearchField.description: "Desc",
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final field = ref.watch(albumSearchFieldProvider(albumId));
    return PopupMenuButton<AlbumSearchField>(
      key: const Key('album_search_field_picker'),
      initialValue: field,
      onSelected: (value) => ref.read(albumSearchFieldProvider(albumId).notifier).state = value,
      itemBuilder: (context) => [
        for (final entry in _labels.entries) PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          _labels[field]!,
          style: TextStyle(color: context.colorScheme.primary, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
