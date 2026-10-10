// Custom fork: uncropped (aspect-ratio) timeline tiles.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/config/timeline_config.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:immich_mobile/presentation/widgets/timeline/fixed/row.dart';
import 'package:immich_mobile/presentation/widgets/timeline/fixed/segment.model.dart';
import 'package:immich_mobile/presentation/widgets/timeline/fixed/segment_builder.dart';
import 'package:immich_mobile/widgets/settings/asset_list_settings/asset_list_layout_settings.dart';

import '../unit/presentation/presentation_context.dart';

void main() {
  test('default thumbnail shape is 2:3 portrait, uncropped', () {
    expect(const TimelineConfig().tileAspectPercent, 67);
  });

  group('FixedSegmentBuilder', () {
    // 3 columns, 360 wide, 2 spacing -> tileWidth 118.67; 2:3 -> tileHeight 177.1
    const spacing = 2.0;
    const tileWidth = (360 - spacing * 2) / 3;
    const tileHeight = tileWidth * 100 / 67;

    test('uncropped rows are tileHeight tall and keep tileWidth', () {
      final segments = FixedSegmentBuilder(
        buckets: [
          TimeBucket(date: DateTime(2026, 9, 1), assetCount: 7), // 3 rows
          TimeBucket(date: DateTime(2026, 8, 1), assetCount: 3), // 1 row
        ],
        tileHeight: tileHeight,
        tileWidth: tileWidth,
        uncropped: true,
        columnCount: 3,
        spacing: spacing,
        groupBy: GroupAssetsBy.month,
      ).generate();

      expect(segments, hasLength(2));
      final first = segments[0] as FixedSegment;
      expect(first.tileHeight, tileHeight);
      expect(first.tileWidth, tileWidth);
      expect(first.uncropped, isTrue);
      expect(first.endOffset - first.startOffset, closeTo(first.headerExtent + 3 * tileHeight + 2 * spacing, 0.001));
      expect(segments[1].startOffset, first.endOffset);
      // scroll math: row 2 of the first segment starts one row + spacing below row 1
      expect(first.indexToLayoutOffset(2) - first.indexToLayoutOffset(1), closeTo(tileHeight + spacing, 0.001));
    });

    test('without tileWidth it stays square (upstream behaviour)', () {
      final segment =
          FixedSegmentBuilder(
                buckets: [TimeBucket(date: DateTime(2026, 9, 1), assetCount: 4)],
                tileHeight: 100,
                columnCount: 4,
              ).generate().single
              as FixedSegment;
      expect(segment.tileWidth, 100);
      expect(segment.uncropped, isFalse);
    });
  });

  group('TimelineRow', () {
    testWidgets('lays tiles out as width x height', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: TimelineRow(
                height: 177,
                widths: const [118, 118, 118],
                spacing: 2,
                textDirection: TextDirection.ltr,
                children: [for (var i = 0; i < 3; i++) Container(key: ValueKey(i), color: Colors.red)],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        final box = tester.getRect(find.byKey(ValueKey(i)));
        expect(box.size, const Size(118, 177));
        expect(box.left, i * 120.0);
      }
    });

    // Visual check: portrait NAI-shaped images (green top bar, yellow bottom bar, red border)
    // in the upstream cropped row vs the uncropped row. The PNG is looked at by a human/agent.
    testWidgets('screenshot: cropped vs uncropped rows', (tester) async {
      final portrait = File('test/fixtures/custom/portrait_832x1216.png').readAsBytesSync();
      final landscape = File('test/fixtures/custom/landscape.png').readAsBytesSync();
      const tileWidth = (360 - 4) / 3;
      const tileHeight = tileWidth * 100 / 67;

      Widget tile(Uint8List bytes, BoxFit fit) => ColoredBox(
        color: Colors.black,
        child: Image.memory(bytes, fit: fit),
      );

      Widget row(BoxFit fit, double height) => TimelineRow(
        height: height,
        widths: const [tileWidth, tileWidth, tileWidth],
        spacing: 2,
        textDirection: TextDirection.ltr,
        children: [tile(portrait, fit), tile(portrait, fit), tile(landscape, fit)],
      );

      tester.view.physicalSize = const Size(360, 20 + tileWidth + 20 + tileHeight + 20);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          RepaintBoundary(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      row(BoxFit.cover, tileWidth),
                      const SizedBox(height: 20),
                      row(BoxFit.contain, tileHeight),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();
      await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/cropped_vs_uncropped.png'));
    });
  });

  group('Thumbnail shape setting', () {
    late PresentationContext context;

    setUp(() async => context = await PresentationContext.create());
    tearDown(() => context.dispose());

    testWidgets('chips show the current shape and save a new one', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpTestWidget(context, const SingleChildScrollView(child: LayoutSettings()));
      await tester.pumpAndSettle();

      ChoiceChip chip(int percent) => tester.widget<ChoiceChip>(find.byKey(ValueKey('tile_shape_$percent')));
      expect(chip(67).selected, isTrue);
      expect(chip(0).selected, isFalse);

      await tester.tap(find.byKey(const ValueKey('tile_shape_0')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      expect(SettingsRepository.instance.appConfig.timeline.tileAspectPercent, 0);
      expect(chip(0).selected, isTrue);
      expect(chip(67).selected, isFalse);
    });
  });
}
