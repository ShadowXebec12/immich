// Custom fork: slideshow duration can go below the upstream 5 second minimum.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:immich_mobile/widgets/settings/asset_viewer_settings/slideshow_settings.dart';

import '../unit/presentation/presentation_context.dart';

void main() {
  late PresentationContext context;

  setUp(() async => context = await PresentationContext.create());
  tearDown(() => context.dispose());

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpTestWidget(context, const SingleChildScrollView(child: SlideshowSettings()));
    await tester.pumpAndSettle();
  }

  testWidgets('duration slider runs 1 to 30 seconds in 1 second steps', (tester) async {
    await pumpSettings(tester);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 1);
    expect(slider.max, 30);
    expect(slider.divisions, 29);
    // upstream default stays 5
    expect(slider.value, 5);
  });

  testWidgets('dragging the slider fully left saves a 1 second duration', (tester) async {
    await pumpSettings(tester);

    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(-2000, 0));
    await tester.pumpAndSettle();

    expect(tester.widget<Slider>(slider).value, 1);
    // setting write is async; let it land in the repository
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    expect(SettingsRepository.instance.appConfig.slideshow.duration, 1);
  });

  testWidgets('can pick 3 seconds', (tester) async {
    await pumpSettings(tester);

    final slider = find.byType(Slider);
    final rect = tester.getRect(slider);
    // Material slider track has 24px padding on each side at this size; step to value 3
    // by dragging from the thumb at 5 two divisions left.
    await tester.drag(slider, const Offset(-2000, 0)); // -> 1
    await tester.pumpAndSettle();
    final track = rect.width - 48;
    await tester.dragFrom(Offset(rect.left + 24, rect.center.dy), Offset(track * 2 / 29, 0));
    await tester.pumpAndSettle();

    expect(tester.widget<Slider>(slider).value, 3);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    expect(SettingsRepository.instance.appConfig.slideshow.duration, 3);
  });
}
