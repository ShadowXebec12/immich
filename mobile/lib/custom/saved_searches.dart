// Custom fork: bookmarked searches + recent search history (shown as tabs in the Recent albums sheet).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/presentation/pages/search/paginated_search.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/option.dart';
import 'package:path_provider/path_provider.dart';

const kSearchHistoryLimit = 30;

/// The parts of a search that are saved: text, albums, gallery filters (model, character, labels, mix),
/// favorites, rating and media type. People, places, camera and dates are not saved.
Map<String, Object?> searchToJson(SearchFilter f) => {
  if ((f.filename ?? '').isNotEmpty) 'filename': f.filename,
  if ((f.description ?? '').isNotEmpty) 'description': f.description,
  if ((f.context ?? '').isNotEmpty) 'context': f.context,
  if (f.albumIds.isNotEmpty) 'albumIds': f.albumIds,
  if (f.albumIds.isNotEmpty && f.albumMatchAny) 'albumMatchAny': true,
  if (f.galModels.isNotEmpty) 'models': f.galModels,
  if (f.galChars.isNotEmpty) 'chars': f.galChars,
  if (f.galLabels.isNotEmpty) 'labels': f.galLabels,
  if (f.galMixes.isNotEmpty) 'mixes': f.galMixes,
  if (f.display.isFavorite) 'favorite': true,
  if (f.display.isNotFavorite) 'notFavorite': true,
  if (f.rating.rating.isSome) 'rating': f.rating.rating.unwrapOrNull ?? 0,
  if (f.mediaType != AssetType.other) 'media': f.mediaType.name,
};

SearchFilter searchFromJson(Map j) {
  List<String> l(String k) => [for (final v in (j[k] as List? ?? const [])) v.toString()];
  final media = AssetType.values.where((t) => t.name == j['media']).firstOrNull ?? AssetType.other;
  final rating = j['rating'] as num?;
  return SearchFilter(
    filename: j['filename'] as String?,
    description: j['description'] as String?,
    context: j['context'] as String?,
    albumIds: l('albumIds'),
    albumMatchAny: j['albumMatchAny'] == true,
    galModels: l('models'),
    galChars: l('chars'),
    galLabels: l('labels'),
    galMixes: l('mixes'),
    people: {},
    location: const SearchLocationFilter(),
    camera: const SearchCameraFilter(),
    date: const SearchDateFilter(),
    display: SearchDisplayFilters(
      isNotInAlbum: false,
      isArchive: false,
      isFavorite: j['favorite'] == true,
      isNotFavorite: j['notFavorite'] == true,
    ),
    rating: rating == null
        ? const SearchRatingFilter()
        : SearchRatingFilter(rating: Option.some(rating == 0 ? null : rating.toInt())),
    mediaType: media,
    tagIds: [],
  );
}

/// One line describing a saved search, e.g. "chars: weiss schnee · labels: cowgirl".
String searchSummary(Map j) {
  String l(String k) => (j[k] as List? ?? const []).join(', ');
  return [
    if (j['filename'] != null) '"${j['filename']}"',
    if (j['description'] != null) 'desc: ${j['description']}',
    if (j['context'] != null) '"${j['context']}"',
    if (l('chars').isNotEmpty) 'chars: ${l('chars')}',
    if (l('labels').isNotEmpty) 'labels: ${l('labels')}',
    if (l('mixes').isNotEmpty) 'mix: ${l('mixes')}',
    if (l('models').isNotEmpty) 'model: ${l('models')}',
    if (l('albumIds').isNotEmpty) '${(j['albumIds'] as List).length} album(s)',
    if (j['favorite'] == true) 'favorites',
    if (j['notFavorite'] == true) 'not favorite',
    if (j['rating'] != null) 'rating ${j['rating'] == 0 ? 'none' : j['rating']}',
    if (j['media'] != null) '${j['media']}',
  ].join(' · ');
}

class SavedSearch {
  SavedSearch(this.name, this.query);
  final String name;
  final Map<String, Object?> query;
  Map<String, Object?> toJson() => {'name': name, 'query': query};
  static SavedSearch fromJson(Map j) =>
      SavedSearch(j['name']?.toString() ?? '', Map<String, Object?>.from(j['query'] as Map? ?? const {}));
}

/// [history] with [q] moved to the front, no duplicates, at most [limit].
List<Map<String, Object?>> pushSearchHistory(
  List<Map<String, Object?>> history,
  Map<String, Object?> q, {
  int limit = kSearchHistoryLimit,
}) {
  final key = jsonEncode(q);
  return [q, ...history.where((h) => jsonEncode(h) != key)].take(limit).toList();
}

/// Bookmarks + history in one small JSON file in the app's support folder.
class SavedSearchStore {
  SavedSearchStore._();
  static final instance = SavedSearchStore._();

  /// Tests point this at a temp folder.
  static Future<Directory> Function() dir = getApplicationSupportDirectory;

  List<SavedSearch> bookmarks = [];
  List<Map<String, Object?>> history = [];
  bool _loaded = false;

  Future<File> _file() async => File('${(await dir()).path}/saved_searches.json');

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final f = await _file();
      if (f.existsSync()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        bookmarks = [for (final b in (j['bookmarks'] as List? ?? const [])) SavedSearch.fromJson(b as Map)];
        history = [for (final h in (j['history'] as List? ?? const [])) Map<String, Object?>.from(h as Map)];
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'bookmarks': [for (final b in bookmarks) b.toJson()],
          'history': history,
        }),
      );
    } catch (_) {}
  }

  Future<void> addHistory(SearchFilter f) async {
    final q = searchToJson(f);
    if (q.isEmpty) {
      return;
    }
    await load();
    history = pushSearchHistory(history, q);
    await _save();
  }

  Future<void> addBookmark(String name, SearchFilter f) async {
    await load();
    final q = searchToJson(f);
    bookmarks = [SavedSearch(name, q), ...bookmarks.where((b) => b.name != name)];
    await _save();
  }

  Future<void> removeBookmark(SavedSearch b) async {
    bookmarks = bookmarks.where((x) => x != b).toList();
    await _save();
  }

  Future<void> clearHistory() async {
    history = [];
    await _save();
  }

  /// Opens the Search page with [q] filled in.
  static void open(BuildContext context, WidgetRef ref, Map q) {
    ref.read(searchPreFilterProvider.notifier)
      ..clear()
      ..setFilter(searchFromJson(q));
    unawaited(context.router.root.navigate(const SearchRoute()));
  }
}

/// App bar button on the Search page: bookmark the current search under a name.
Future<void> bookmarkSearchDialog(BuildContext context, SearchFilter f) async {
  final q = searchToJson(f);
  if (q.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Nothing to bookmark: set a search first")));
    return;
  }
  final ctl = TextEditingController(text: searchSummary(q));
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Bookmark search"),
      content: TextField(
        key: const ValueKey('bookmark_name'),
        controller: ctl,
        autofocus: true,
        decoration: const InputDecoration(labelText: "Name"),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        FilledButton(
          key: const ValueKey('bookmark_save'),
          onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          child: const Text("Save"),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) {
    return;
  }
  await SavedSearchStore.instance.addBookmark(name, f);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bookmarked: $name")));
  }
}

/// Bookmarks tab and Searches tab of the Recent albums sheet. [onOpen] runs a saved query.
class SavedSearchList extends StatefulWidget {
  const SavedSearchList({super.key, required this.bookmarks, required this.onOpen});
  final bool bookmarks;
  final void Function(Map q) onOpen;

  @override
  State<SavedSearchList> createState() => _SavedSearchListState();
}

class _SavedSearchListState extends State<SavedSearchList> {
  final _store = SavedSearchStore.instance;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load().then((_) => mounted ? setState(() => _ready = true) : null));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.bookmarks) {
      if (_store.bookmarks.isEmpty) {
        return const ListTile(
          key: Key('bookmarks_empty'),
          title: Text("No bookmarks yet"),
          subtitle: Text("On the Search page tap the bookmark icon to save a search"),
        );
      }
      return ListView(
        children: [
          for (final b in _store.bookmarks)
            ListTile(
              key: ValueKey('bookmark_${b.name}'),
              leading: const Icon(Icons.bookmark_rounded),
              title: Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(searchSummary(b.query), maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => widget.onOpen(b.query),
              trailing: IconButton(
                key: ValueKey('bookmark_delete_${b.name}'),
                tooltip: "Remove bookmark",
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  unawaited(_store.removeBookmark(b));
                  setState(() {});
                },
              ),
            ),
        ],
      );
    }
    if (_store.history.isEmpty) {
      return const ListTile(key: Key('searches_empty'), title: Text("No searches yet"));
    }
    return ListView(
      children: [
        for (final (i, q) in _store.history.indexed)
          ListTile(
            key: ValueKey('search_history_$i'),
            leading: const Icon(Icons.search_rounded),
            title: Text(searchSummary(q), maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => widget.onOpen(q),
          ),
        TextButton(
          onPressed: () {
            unawaited(_store.clearHistory());
            setState(() {});
          },
          child: const Text("Clear search history"),
        ),
      ],
    );
  }
}
