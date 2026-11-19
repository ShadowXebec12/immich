import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/custom/gen_menu.dart';

void main() {
  test('i2i body carries strength, regen does not', () {
    final i2i = genBody({'immich_id': 'abc', 'name': 'a b.png'}, kGenPresets.firstWhere((p) => p.title == 'i2i'), 0.7);
    expect(i2i['immich_id'], 'abc');
    expect(i2i['name'], 'a b.png');
    expect(i2i['mode'], 'i2i');
    expect(i2i['strength'], '0.70');
    final regen = genBody({'name': 'x.png'}, kGenPresets.first, 0.7);
    expect(regen['mode'], 'full');
    expect(regen.containsKey('strength'), isFalse);
  });

  test('char ref sends cref fields', () {
    final b = genBody({'name': 'x.png'}, kGenPresets.firstWhere((p) => p.title == 'Char ref'), 0.5);
    expect(b['cref'], 1);
    expect(b['cref_mode'], 'character');
  });

  test('copy parts read sections, map text and drop empties', () {
    final copies = promptCopies({
      'prompt': 'main prompt',
      'mix_id': 'M12',
      'seed': 123,
      'sections': {
        'artist_mix': {'text': 'artist:a, artist:b'},
        'face': 'smile, blush',
        'body': '',
        'char_boxes': [
          {'text': 'girl box', 'gender': 'f'},
        ],
        'actual': {'text': 'actual main', 'char_boxes': []},
      },
    });
    final m = {for (final c in copies) c.$1: c.$2};
    expect(m['Prompt'], 'main prompt\ngirl box');
    expect(m['Mix'], 'artist:a, artist:b');
    expect(m['Face'], 'smile, blush');
    expect(m['Mix ID'], 'M12');
    expect(m['Seed'], '123');
    expect(m['Actual'], 'actual main');
    expect(m.containsKey('Body only'), isFalse);
  });

  test('no info gives no copies', () {
    expect(promptCopies({}), isEmpty);
  });
}
