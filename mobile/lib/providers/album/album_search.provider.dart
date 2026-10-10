// Custom fork: in-album search.
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Search text per album id. `null` = search bar closed, '' = open but empty.
final albumSearchQueryProvider = StateProvider.autoDispose.family<String?, String>((ref, albumId) => null);
