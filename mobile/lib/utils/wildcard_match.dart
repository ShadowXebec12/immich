// Custom fork: forgiving text matching for album names and in-album search.
//
// The query is split on spaces and EVERY term must match, in any order.
// A term may use `*` (any run of characters) and `?` (one character); otherwise it is a plain
// "contains" match. Matching ignores case.

final _whitespace = RegExp(r'\s+');

List<String> _terms(String query) => query.trim().split(_whitespace).where((t) => t.isNotEmpty).toList();

bool wildcardMatch(String text, String query) {
  final haystack = text.toLowerCase();
  for (final term in _terms(query.toLowerCase())) {
    if (term.contains('*') || term.contains('?')) {
      final pattern = term.split('').map((c) => c == '*' ? '.*' : (c == '?' ? '.' : RegExp.escape(c))).join();
      if (!RegExp(pattern).hasMatch(haystack)) {
        return false;
      }
    } else if (!haystack.contains(term)) {
      return false;
    }
  }
  return true;
}

/// SQL LIKE patterns (escape char `\`), one per term; every pattern must match.
List<String> likePatterns(String query) => _terms(query).map((term) {
  final escaped = term.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  return '%${escaped.replaceAll('*', '%').replaceAll('?', '_')}%';
}).toList();
