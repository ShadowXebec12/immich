// Custom fork: folder chips above the album list, plus the "move to folder" sheet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/album/album_folders.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';

/// Selected folder filter: null = all albums, '' = albums in no folder, otherwise the folder name.
typedef FolderFilter = String?;

const kUnfiledFolder = '';

final albumFoldersProvider = Provider.autoDispose<AlbumFolders>((ref) {
  final album = ref.watch(appConfigProvider.select((c) => c.album));
  return AlbumFolders(names: album.folderNames, map: album.folderMap);
});

Future<void> saveAlbumFolders(WidgetRef ref, AlbumFolders folders) async {
  final settings = ref.read(settingsProvider);
  await settings.write(.albumFolderNames, folders.names);
  await settings.write(.albumFolderMap, folders.map);
}

Future<String?> _askFolderName(BuildContext context, {String initial = '', required String title}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('folder_name_field'),
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: "Folder name"),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        TextButton(
          key: const Key('folder_name_ok'),
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text("OK"),
        ),
      ],
    ),
  );
}

class AlbumFolderBar extends ConsumerWidget {
  const AlbumFolderBar({super.key, required this.albums, required this.selected, required this.onSelected});

  final List<RemoteAlbum> albums;
  final FolderFilter selected;
  final ValueChanged<FolderFilter> onSelected;

  Future<void> _create(BuildContext context, WidgetRef ref, AlbumFolders folders) async {
    final name = await _askFolderName(context, title: "New folder");
    if (name == null || name.isEmpty) {
      return;
    }
    await saveAlbumFolders(ref, folders.add(name));
    onSelected(name);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AlbumFolders folders, String folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(folder, style: context.textTheme.titleMedium)),
            ListTile(
              key: const Key('folder_rename'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text("Rename folder"),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              key: const Key('folder_delete'),
              leading: const Icon(Icons.delete_outline),
              title: const Text("Delete folder"),
              subtitle: const Text("Albums are kept, they just leave the folder"),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) {
      return;
    }

    if (action == 'delete') {
      await saveAlbumFolders(ref, folders.remove(folder));
      if (selected == folder) {
        onSelected(null);
      }
      return;
    }

    final name = await _askFolderName(context, initial: folder, title: "Rename folder");
    if (name == null || name.isEmpty) {
      return;
    }
    final renamed = folders.rename(folder, name);
    await saveAlbumFolders(ref, renamed);
    if (selected == folder && renamed.names.contains(name)) {
      onSelected(name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(albumFoldersProvider);
    final ids = albums.map((a) => a.id).toList();

    Widget chip(String label, FolderFilter value, {VoidCallback? onLongPress, Key? key}) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ChoiceChip(
          key: key,
          label: Text(label),
          selected: selected == value,
          onSelected: (_) => onSelected(value),
        ),
      ),
    );

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      sliver: SliverToBoxAdapter(
        child: SizedBox(
          height: 44,
          child: ListView(
            key: const Key('album_folder_bar'),
            scrollDirection: Axis.horizontal,
            children: [
              chip("All (${ids.length})", null, key: const Key('folder_chip_all')),
              for (final folder in folders.names)
                chip(
                  "$folder (${folders.countIn(folder, ids)})",
                  folder,
                  key: ValueKey('folder_chip_$folder'),
                  onLongPress: () => unawaited(_edit(context, ref, folders, folder)),
                ),
              if (folders.names.isNotEmpty)
                chip("No folder (${folders.countUnfiled(ids)})", kUnfiledFolder, key: const Key('folder_chip_unfiled')),
              ActionChip(
                key: const Key('folder_chip_new'),
                avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text("New folder"),
                onPressed: () => unawaited(_create(context, ref, folders)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet opened by long-pressing an album: pick the folder it lives in.
Future<void> showMoveAlbumToFolderSheet(BuildContext context, WidgetRef ref, RemoteAlbum album) async {
  await showMoveAlbumsToFolderSheet(context, ref, [album]);
}

/// Same sheet for several albums at once. Returns true when they were moved.
Future<bool> showMoveAlbumsToFolderSheet(BuildContext context, WidgetRef ref, List<RemoteAlbum> albums) async {
  if (albums.isEmpty) {
    return false;
  }
  final folders = ref.read(albumFoldersProvider);
  final currents = albums.map((a) => folders.folderOf(a.id)).toSet();
  final current = currents.length == 1 ? currents.first : '\u0000';
  final title = albums.length == 1
      ? "Move \"${albums.first.name}\" to folder"
      : "Move ${albums.length} albums to folder";

  final choice = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(title, style: context.textTheme.titleMedium)),
            for (final folder in folders.names)
              ListTile(
                key: ValueKey('move_to_$folder'),
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder),
                trailing: current == folder ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(context).pop('f:$folder'),
              ),
            ListTile(
              key: const Key('move_to_none'),
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text("No folder"),
              trailing: current == null ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.of(context).pop('none'),
            ),
            ListTile(
              key: const Key('move_to_new'),
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text("New folder..."),
              onTap: () => Navigator.of(context).pop('new'),
            ),
          ],
        ),
      ),
    ),
  );

  if (choice == null || !context.mounted) {
    return false;
  }

  AlbumFolders moveAll(AlbumFolders start, String? target) =>
      albums.fold(start, (acc, album) => acc.move(album.id, target));

  if (choice == 'none') {
    await saveAlbumFolders(ref, moveAll(folders, null));
  } else if (choice == 'new') {
    final name = await _askFolderName(context, title: "New folder");
    if (name == null || name.isEmpty) {
      return false;
    }
    final added = folders.add(name);
    final target = added.names.firstWhere((n) => n.toLowerCase() == name.toLowerCase());
    await saveAlbumFolders(ref, moveAll(added, target));
  } else {
    await saveAlbumFolders(ref, moveAll(folders, choice.substring(2)));
  }
  return true;
}
