// Custom fork: search-as-you-type bar shown above an album.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
              _FieldPicker(albumId: widget.albumId),
            ],
          ),
        ),
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
