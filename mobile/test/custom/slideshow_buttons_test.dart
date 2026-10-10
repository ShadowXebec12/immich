// Custom fork: favorite / share buttons appear while a slideshow is paused.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/generated/codegen_loader.g.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/presentation/pages/slideshow.page.dart';
import 'package:immich_mobile/utils/option.dart';
import 'package:mocktail/mocktail.dart';

import '../unit/factories/remote_asset_factory.dart';
import '../unit/presentation/presentation_context.dart';

class _FakeTimeline implements TimelineService {
  _FakeTimeline(this.assets);

  final List<BaseAsset> assets;

  @override
  int get totalAssets => assets.length;

  @override
  BaseAsset? getAssetSafe(int index) => index >= 0 && index < assets.length ? assets[index] : null;

  @override
  int? getIndex(String heroTag) {
    final index = assets.indexWhere((a) => a.heroTag == heroTag);
    return index < 0 ? null : index;
  }

  @override
  bool hasRange(int index, int count) => index >= 0 && index + count <= assets.length;

  @override
  Future<void> preloadAssets(int index) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PresentationContext context;

  // Like pumpTestWidget, but without pumpAndSettle: a running slideshow never stops animating.
  Future<void> pumpSlideshow(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: locales.values.toList(),
        path: translationsPath,
        startLocale: locales.values.first,
        fallbackLocale: locales.values.first,
        saveLocale: false,
        useFallbackTranslations: true,
        assetLoader: const CodegenLoader(),
        child: ProviderScope(
          overrides: context.overrides,
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: page,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // image loading has no backend in tests
    tester.takeException();
  }

  // The pause/play button sits in the slideshow's auto-hidden top bar, so press it directly
  Future<void> pressTopBar(WidgetTester tester, IconData icon) async {
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed!();
    await tester.pump();
  }

  setUpAll(() => registerFallbackValue(const Option<bool>.none()));
  setUp(() async => context = await PresentationContext.create());
  tearDown(() => context.dispose());

  testWidgets('buttons show only while paused; heart favorites the current photo and can undo', (tester) async {
    final asset = RemoteAssetFactory.create();
    when(
      () => context.service.asset.service.update(any(), isFavorite: any(named: 'isFavorite')),
    ).thenAnswer((_) async {});

    await pumpSlideshow(tester, SlideshowPage(timeline: _FakeTimeline([asset, RemoteAssetFactory.create()])));

    final favorite = find.byKey(const Key('slideshow_favorite'));
    // playing: nothing over the picture
    expect(favorite, findsNothing);
    expect(find.byKey(const Key('slideshow_share')), findsNothing);

    await pressTopBar(tester, Icons.pause);
    expect(favorite, findsOneWidget);
    expect(find.byKey(const Key('slideshow_share')), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await tester.tap(favorite);
    await tester.pump();
    await tester.pump();
    verify(() => context.service.asset.service.update([asset.id], isFavorite: const Option.some(true))).called(1);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    await tester.tap(favorite);
    await tester.pump();
    await tester.pump();
    verify(() => context.service.asset.service.update([asset.id], isFavorite: const Option.some(false))).called(1);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    // playing again hides them
    await pressTopBar(tester, Icons.play_arrow);
    expect(favorite, findsNothing);
    expect(find.byKey(const Key('slideshow_share')), findsNothing);

    // let the slideshow tear down its timer
    await tester.pumpWidget(const SizedBox());
    tester.takeException();
  });

  testWidgets('a failed favorite puts the heart back', (tester) async {
    final asset = RemoteAssetFactory.create();
    when(
      () => context.service.asset.service.update(any(), isFavorite: any(named: 'isFavorite')),
    ).thenThrow(Exception('offline'));

    await pumpSlideshow(tester, SlideshowPage(timeline: _FakeTimeline([asset])));
    await pressTopBar(tester, Icons.pause);

    await tester.tap(find.byKey(const Key('slideshow_favorite')));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    tester.takeException();
  });
}
