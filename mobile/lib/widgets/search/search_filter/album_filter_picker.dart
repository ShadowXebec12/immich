// Custom fork: pick one or more albums to search in.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/utils/wildcard_match.dart';

class AlbumFilterPicker extends ConsumerStatefulWidget {
  const AlbumFilterPicker({
    super.key,
    required this.onSelect,
    this.initialSelection = const {},
    this.initialMatchAny = false,
  });

  /// Called with the selected albums and whether "in any album" is on.
  final void Function(List<RemoteAlbum> albums, bool matchAny) onSelect;
  final Set<String> initialSelection;
  final bool initialMatchAny;

  @override
  ConsumerState<AlbumFilterPicker> createState() => _AlbumFilterPickerState();
}

class _AlbumFilterPickerState extends ConsumerState<AlbumFilterPicker> {
  late final Set<String> _selected = {...widget.initialSelection};
  late bool _matchAny = widget.initialMatchAny;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _notify();
      if (ref.read(remoteAlbumProvider).albums.isEmpty) {
        unawaited(ref.read(remoteAlbumProvider.notifier).refresh());
      }
    });
  }

  void _notify() {
    final albums = ref.read(remoteAlbumProvider).albums.where((a) => _selected.contains(a.id)).toList();
    widget.onSelect(albums, _matchAny);
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(remoteAlbumProvider.select((s) => s.albums));
    // keep the parent's label in sync once albums arrive
    ref.listen(remoteAlbumProvider.select((s) => s.albums), (_, _) => _notify());

    final shown = albums.where((a) => _query.trim().isEmpty || wildcardMatch(a.name, _query)).toList()
      ..sort((a, b) {
        final selectedOrder = (_selected.contains(b.id) ? 1 : 0) - (_selected.contains(a.id) ? 1 : 0);
        return selectedOrder != 0 ? selectedOrder : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            key: const Key('album_filter_search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: "Find album (words in any order, * = anything)",
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        SwitchListTile(
          key: const Key('album_filter_match_any'),
          title: const Text("In any selected album"),
          subtitle: Text(
            _matchAny ? "Shows photos that are in at least one" : "Off: only photos that are in all of them",
          ),
          value: _matchAny,
          onChanged: (value) {
            setState(() => _matchAny = value);
            _notify();
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final album = shown[index];
              return CheckboxListTile(
                key: ValueKey('album_filter_${album.id}'),
                dense: true,
                title: Text(album.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text("${album.assetCount} items"),
                value: _selected.contains(album.id),
                onChanged: (value) {
                  setState(() => value == true ? _selected.add(album.id) : _selected.remove(album.id));
                  _notify();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
