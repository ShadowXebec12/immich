// Custom fork: album folders that live only in this app (Immich itself has no album folders).

/// [names] is the ordered folder list, [map] is albumId -> folder name.
class AlbumFolders {
  final List<String> names;
  final Map<String, String> map;

  const AlbumFolders({this.names = const [], this.map = const {}});

  /// Folder of an album, or null when it is not in any (existing) folder.
  String? folderOf(String albumId) {
    final folder = map[albumId];
    return folder != null && names.contains(folder) ? folder : null;
  }

  int countIn(String folder, Iterable<String> albumIds) => albumIds.where((id) => folderOf(id) == folder).length;

  int countUnfiled(Iterable<String> albumIds) => albumIds.where((id) => folderOf(id) == null).length;

  bool exists(String name) => names.any((n) => n.toLowerCase() == name.trim().toLowerCase());

  AlbumFolders add(String name) {
    final clean = name.trim();
    if (clean.isEmpty || exists(clean)) {
      return this;
    }
    return AlbumFolders(names: [...names, clean], map: map);
  }

  AlbumFolders rename(String from, String to) {
    final clean = to.trim();
    if (clean.isEmpty || !names.contains(from) || (exists(clean) && clean.toLowerCase() != from.toLowerCase())) {
      return this;
    }
    return AlbumFolders(
      names: [for (final n in names) n == from ? clean : n],
      map: {for (final e in map.entries) e.key: e.value == from ? clean : e.value},
    );
  }

  /// Deletes the folder only; its albums become unfiled.
  AlbumFolders remove(String name) => AlbumFolders(
    names: [
      for (final n in names)
        if (n != name) n,
    ],
    map: {
      for (final e in map.entries)
        if (e.value != name) e.key: e.value,
    },
  );

  /// Moves an album into [folder], or out of any folder when null.
  AlbumFolders move(String albumId, String? folder) {
    final next = {...map}..remove(albumId);
    if (folder != null && names.contains(folder)) {
      next[albumId] = folder;
    }
    return AlbumFolders(names: names, map: next);
  }
}
