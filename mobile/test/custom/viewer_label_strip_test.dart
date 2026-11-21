// Custom fork #4: the viewer label strip only shows the chosen labels and never overflows,
// on narrow / normal / wide screens with few, many and very long labels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/label_badges.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';

class _FakeLabels extends GalleryLabelsNotifier {
  _FakeLabels(this.labels);

  final List<String> labels;

  @override
  Map<String, List<String>> build() => {'a.png': labels};

  @override
  void want(BaseAsset asset) {}

  @override
  Future<List<LabelGroup>> groups() async => const [
    LabelGroup('Pose', ['ass pinup', 'doggystyle', 'cowgirl lower body standing very long pose name here']),
    LabelGroup('Body', ['body hyper thick', 'body pear-shaped']),
    LabelGroup('Body / Clothing state', ['nude']),
    LabelGroup('Style', ['best riz', 'main style']),
    LabelGroup('Framing', ['upper body']),
    LabelGroup('Inpaint', ['impaint needed female body', 'some impaint needed']),
    LabelGroup('Workflow', ['test style', 'request']),
    LabelGroup('Model / Request type', ['char ref']),
    LabelGroup('Workflow / Meta', ['Vibe transfer']),
  ];
}

final _asset = RemoteAsset(
  id: 'id1',
  name: 'a.png',
  ownerId: 'o',
  checksum: 'c',
  type: AssetType.image,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isEdited: false,
);

Future<void> _pump(WidgetTester tester, double width, List<String> labels) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [galleryLabelsProvider.overrideWith(() => _FakeLabels(labels))],
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Column(children: [ViewerLabelStrip(asset: _asset)]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.resetPhysicalSize();
  });

  test('filter: pose, body, style + ref / vibe / test style / impaint only', () {
    expect(viewerStripLabel('ass pinup', 'pose'), isTrue);
    expect(viewerStripLabel('body hyper thick', 'body'), isTrue);
    expect(viewerStripLabel('best riz', 'style'), isTrue);
    expect(viewerStripLabel('char ref', 'model / request type'), isTrue);
    expect(viewerStripLabel('Vibe transfer', 'workflow / meta'), isTrue);
    expect(viewerStripLabel('test style', 'workflow'), isTrue);
    expect(viewerStripLabel('some impaint needed', 'inpaint'), isTrue);
    expect(viewerStripLabel('nude', 'body / clothing state'), isFalse);
    expect(viewerStripLabel('upper body', 'framing'), isFalse);
    expect(viewerStripLabel('request', 'workflow'), isFalse);
  });

  const many = [
    'ass pinup', 'upper body', 'nude', 'body hyper thick', 'body pear-shaped', 'best riz', 'main style',
    'request', 'test style', 'char ref', 'Vibe transfer', 'impaint needed female body', 'some impaint needed',
    'cowgirl lower body standing very long pose name here', 'doggystyle',
  ];

  for (final width in [320.0, 390.0, 430.0, 1024.0]) {
    for (final labels in [
      const ['ass pinup'],
      const ['ass pinup', 'nude', 'best riz'],
      many,
    ]) {
      testWidgets('width $width, ${labels.length} labels: one 22 px row, no overflow, only chosen labels', (
        tester,
      ) async {
        await _pump(tester, width, labels);
        expect(tester.takeException(), isNull);
        final strip = find.byKey(const Key('viewer_label_strip'));
        expect(strip, findsOneWidget);
        expect(tester.getSize(strip).height, 22);
        expect(tester.getSize(strip).width, lessThanOrEqualTo(width));
        expect(find.text('nude'), findsNothing);
        expect(find.text('upper body'), findsNothing);
        expect(find.text('ass pinup'), findsOneWidget);
      });
    }
  }

  testWidgets('no chosen labels: nothing shown', (tester) async {
    await _pump(tester, 390, const ['nude', 'upper body']);
    expect(find.byKey(const Key('viewer_label_strip')), findsNothing);
  });
}
