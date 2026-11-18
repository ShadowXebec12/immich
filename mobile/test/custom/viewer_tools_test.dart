import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/custom/viewer_tools.dart';
import 'package:immich_mobile/domain/models/album/album_folders.dart';
import 'package:immich_mobile/presentation/widgets/album/album_selector.widget.dart';

void main() {
  group('viewer gestures', () {
    test('defaults when nothing is saved', () {
      expect(gestureActionFor([], ViewerGesture.longPress), ViewerGestureAction.labels);
      expect(gestureActionFor([], ViewerGesture.twoFingerTap), ViewerGestureAction.favorite);
      expect(gestureActionFor([], ViewerGesture.threeFingerTap), ViewerGestureAction.copyName);
    });

    test('saved choice wins, unknown action falls back, setting replaces the old pair', () {
      var saved = withGestureAction([], ViewerGesture.twoFingerTap, ViewerGestureAction.copyImage);
      expect(gestureActionFor(saved, ViewerGesture.twoFingerTap), ViewerGestureAction.copyImage);
      saved = withGestureAction(saved, ViewerGesture.twoFingerTap, ViewerGestureAction.select);
      expect(saved.where((p) => p.startsWith('twoFingerTap=')).length, 1);
      expect(gestureActionFor(saved, ViewerGesture.twoFingerTap), ViewerGestureAction.select);
      expect(gestureActionFor(['longPress=bogus'], ViewerGesture.longPress), ViewerGestureAction.labels);
    });
  });

  group('MultiFingerTapListener', () {
    Future<List<int>> pump(WidgetTester tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: MultiFingerTapListener(
            onTap: taps.add,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
          ),
        ),
      );
      return taps;
    }

    testWidgets('two- and three-finger taps fire, one finger does not', (tester) async {
      final taps = await pump(tester);
      final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
      final b = await tester.startGesture(const Offset(200, 100), pointer: 2);
      await a.up();
      await b.up();
      expect(taps, [2]);

      final c = await tester.startGesture(const Offset(100, 100), pointer: 3);
      final d = await tester.startGesture(const Offset(150, 100), pointer: 4);
      final e = await tester.startGesture(const Offset(200, 100), pointer: 5);
      await c.up();
      await d.up();
      await e.up();
      expect(taps, [2, 3]);

      final f = await tester.startGesture(const Offset(100, 100), pointer: 6);
      await f.up();
      expect(taps, [2, 3]);
    });

    testWidgets('a pinch (fingers move) and a slow hold do not count', (tester) async {
      final taps = await pump(tester);
      final a = await tester.startGesture(const Offset(100, 100), pointer: 1);
      final b = await tester.startGesture(const Offset(200, 100), pointer: 2);
      await b.moveTo(const Offset(300, 100));
      await a.up();
      await b.up();
      expect(taps, isEmpty);

      final c = await tester.startGesture(const Offset(100, 100), pointer: 3);
      final d = await tester.startGesture(const Offset(200, 100), pointer: 4);
      // pointer events carry their own time: the fingers lift 500 ms after touching down
      await c.up(timeStamp: const Duration(milliseconds: 500));
      await d.up(timeStamp: const Duration(milliseconds: 500));
      expect(taps, isEmpty);
    });
  });

  group('album multi-select', () {
    test('selection add / toggle / clear', () {
      final s = AlbumSelection();
      var calls = 0;
      s.addListener(() => calls++);
      s.add('a');
      s.add('a');
      s.add('b');
      expect(s.ids, {'a', 'b'});
      s.toggle('a');
      expect(s.ids, {'b'});
      s.clear();
      expect(s.active, isFalse);
      expect(calls, 4);
    });

    test('moving several albums puts each in the folder', () {
      const start = AlbumFolders(names: ['Ditto', 'Poses'], map: {'a': 'Ditto'});
      final moved = ['a', 'b', 'c'].fold(start, (acc, id) => acc.move(id, 'Poses'));
      expect(['a', 'b', 'c'].map(moved.folderOf), ['Poses', 'Poses', 'Poses']);
    });
  });
}
