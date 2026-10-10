// Custom fork: local album folders.
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/album/album_folders.dart';

void main() {
  const base = AlbumFolders(names: ['Ditto', 'Chars'], map: {'a1': 'Ditto', 'a2': 'Ditto', 'a3': 'Chars'});

  test('folderOf / counts', () {
    expect(base.folderOf('a1'), 'Ditto');
    expect(base.folderOf('zz'), isNull);
    expect(base.countIn('Ditto', ['a1', 'a2', 'a3', 'a4']), 2);
    expect(base.countUnfiled(['a1', 'a2', 'a3', 'a4']), 1);
  });

  test('an album mapped to a deleted folder counts as unfiled', () {
    const stale = AlbumFolders(names: ['Chars'], map: {'a1': 'Gone'});
    expect(stale.folderOf('a1'), isNull);
    expect(stale.countUnfiled(['a1']), 1);
  });

  test('add trims, ignores blanks and duplicates (any case)', () {
    expect(base.add('  New  ').names, ['Ditto', 'Chars', 'New']);
    expect(base.add('   ').names, base.names);
    expect(base.add('ditto').names, base.names);
  });

  test('rename moves the albums along, refuses a clash', () {
    final renamed = base.rename('Ditto', 'Ditto v5');
    expect(renamed.names, ['Ditto v5', 'Chars']);
    expect(renamed.folderOf('a1'), 'Ditto v5');
    expect(renamed.folderOf('a3'), 'Chars');

    expect(base.rename('Ditto', 'chars').names, base.names);
    expect(base.rename('Ditto', 'DITTO').names, ['DITTO', 'Chars']);
    expect(base.rename('Nope', 'X').names, base.names);
  });

  test('remove keeps the albums but unfiles them', () {
    final removed = base.remove('Ditto');
    expect(removed.names, ['Chars']);
    expect(removed.folderOf('a1'), isNull);
    expect(removed.folderOf('a3'), 'Chars');
    expect(removed.map.containsKey('a1'), isFalse);
  });

  test('move into a folder, to another, and out', () {
    final moved = base.move('a4', 'Chars');
    expect(moved.folderOf('a4'), 'Chars');
    expect(base.move('a1', 'Chars').folderOf('a1'), 'Chars');
    expect(base.move('a1', null).folderOf('a1'), isNull);
    // unknown folder = unfiled, never a dangling entry
    expect(base.move('a1', 'Nope').map.containsKey('a1'), isFalse);
  });

  test('instances are not mutated', () {
    base.add('X').move('a9', 'X').remove('Ditto');
    expect(base.names, ['Ditto', 'Chars']);
    expect(base.map.length, 3);
  });
}
