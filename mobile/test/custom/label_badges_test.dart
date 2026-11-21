import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/gen_menu.dart';
import 'package:immich_mobile/custom/label_badges.dart';

void main() {
  group('groupTier', () {
    test('pose groups first, request type after model, unknown last', () {
      expect(groupTier('Framing'), 0);
      expect(groupTier('Pose'), 1);
      expect(groupTier('Secondary pose / Actions'), 2);
      expect(groupTier('Style'), 3);
      expect(groupTier('Body / Clothing state'), 4);
      expect(groupTier('Model'), 6);
      expect(groupTier('Model / Request type'), 7);
      expect(groupTier('Workflow'), 8);
    });
  });

  test('sortLabels keeps order inside a tier and puts unknown labels last', () {
    final tiers = {'lower body': 0, 'missionary legs up': 1, 'best riz style': 3, 'v4.5': 6};
    expect(
      sortLabels(['v4.5', 'zzz', 'missionary legs up', 'best riz style', 'lower body'], tiers),
      ['lower body', 'missionary legs up', 'best riz style', 'v4.5', 'zzz'],
    );
  });

  test('labelFontSize shrinks with more labels, floor 7', () {
    expect(labelFontSize(1), 10.5);
    expect(labelFontSize(2) < labelFontSize(1), isTrue);
    expect(labelFontSize(10), 7);
  });

  test('LabelBadge round trip and quick tag keys', () {
    final b = LabelBadge.decode('Best Riz Style=P=Yellow')!;
    expect(b.label, 'best riz style');
    expect(b.text, 'P');
    expect(LabelBadge.decode(b.encode())!.color, 'Yellow');
    expect(LabelBadge.decode('x==Red'), isNull);
    expect(quickTagBadgeKey(kQuickTags.first), 'qt:bad');
    expect(quickTagBadgeKey(kQuickTags.last), 'test style');
    expect(LabelBadge.decode('qt:no_name=N=Red')!.label, 'qt:no_name');
  });

  test('lastGen reads the saved preset and strength', () {
    expect(lastGen(const []), isNull);
    expect(lastGen(const ['nope']), isNull);
    final last = lastGen(const ['i2i', '0.65'])!;
    expect(last.$1.title, 'i2i');
    expect(last.$2, 0.65);
    expect(lastGenSummary(last), 'i2i 0.65');
    expect(lastGenSummary(lastGen(const ['Regen'])!), 'Regen');
  });
}
