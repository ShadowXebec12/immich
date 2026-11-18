// Custom fork: in-album search.
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/infrastructure/repositories/timeline.repository.dart';

/// Search text per album id. `null` = search bar closed, '' = open but empty.
final albumSearchQueryProvider = StateProvider.autoDispose.family<String?, String>((ref, albumId) => null);

/// Which field the in-album search matches (Both / Name / Description).
final albumSearchFieldProvider = StateProvider.autoDispose.family<AlbumSearchField, String>(
  (ref, albumId) => AlbumSearchField.both,
);
