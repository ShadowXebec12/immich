// Custom fork: album name / in-album search matching.
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/utils/wildcard_match.dart';

void main() {
  group('wildcardMatch', () {
    test('plain text is a case-insensitive contains match', () {
      expect(wildcardMatch('Ditto v4.5 pinned', 'pinned'), isTrue);
      expect(wildcardMatch('Ditto v4.5 pinned', 'DITTO'), isTrue);
      expect(wildcardMatch('Ditto v4.5 pinned', 'v5'), isFalse);
    });

    test('words match in any order and all must match', () {
      expect(wildcardMatch('char ref- ref images', 'images char'), isTrue);
      expect(wildcardMatch('Ditto v5 multiple girls no boys', 'girls ditto no'), isTrue);
      expect(wildcardMatch('Ditto v5 multiple girls no boys', 'girls ditto v4'), isFalse);
    });

    test('* matches any run of characters, ? matches one', () {
      expect(wildcardMatch('Ditto v4.5 pinned', 'ditto*pinned'), isTrue);
      expect(wildcardMatch('Ditto v4.5 pinned', 'd*o'), isTrue);
      expect(wildcardMatch('Ditto v4.5 pinned', 'pinned*ditto'), isFalse);
      expect(wildcardMatch('Ditto v5', 'v?'), isTrue);
      expect(wildcardMatch('Ditto v', 'v?'), isFalse);
    });

    test('regex characters in the query are literal', () {
      expect(wildcardMatch('nobara (jujutsu kaisen)', '(jujutsu'), isTrue);
      expect(wildcardMatch('a.b', 'a.b*'), isTrue);
      expect(wildcardMatch('axb', 'a.b*'), isFalse);
      expect(wildcardMatch('what [x] {y}', '[x] {y}'), isTrue);
    });

    test('empty query matches everything', () {
      expect(wildcardMatch('anything', ''), isTrue);
      expect(wildcardMatch('anything', '   '), isTrue);
      expect(wildcardMatch('', 'x'), isFalse);
    });

    test('non-ASCII names', () {
      expect(wildcardMatch('写真 アルバム', 'アルバム'), isTrue);
      expect(wildcardMatch('Café été', 'CAFÉ'), isTrue);
    });
  });

  group('likePatterns', () {
    test('one pattern per word, wrapped in %', () {
      expect(likePatterns('nobara  smile'), ['%nobara%', '%smile%']);
      expect(likePatterns('   '), isEmpty);
    });

    test('wildcards become LIKE wildcards, LIKE specials are escaped', () {
      expect(likePatterns('s-12*png'), ['%s-12%png%']);
      expect(likePatterns('a?c'), ['%a_c%']);
      expect(likePatterns('50%_off'), [r'%50\%\_off%']);
      expect(likePatterns(r'a\b'), [r'%a\\b%']);
    });
  });
}
