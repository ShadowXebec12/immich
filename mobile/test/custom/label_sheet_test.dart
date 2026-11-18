import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/custom/label_sheet.dart';

import '../unit/presentation/presentation_context.dart';

void main() {
  late PresentationContext context;

  setUp(() async => context = await PresentationContext.create());
  tearDown(() => context.dispose());

  LabelSheetData data() => LabelSheetData(
    tabs: [
      ('Pose', ['doggystyle', 'cowgirl', 'missionary']),
      ('Framing', ['close up', 'lower body']),
    ],
    subs: const {},
    groupOf: const {
      'doggystyle': 'Pose',
      'cowgirl': 'Pose',
      'missionary': 'Pose',
      'close up': 'Framing',
      'lower body': 'Framing',
    },
    mixHistory: [
      LabelHistoryEntry(const ['close up', 'lower body'], DateTime.now().subtract(const Duration(hours: 2))),
      LabelHistoryEntry(const ['cowgirl'], DateTime.now().subtract(const Duration(hours: 1))),
    ],
    mixPins: const [
      ['doggystyle', 'lower body'],
    ],
    order: const {
      'Pose': ['missionary', 'doggystyle'],
    },
    combos: const [],
  );

  test('label search: every word, * wildcard', () {
    expect(labelMatches('after sex cowgirl', 'sex cow'), isTrue);
    expect(labelMatches('after sex cowgirl', 'cow sex'), isTrue);
    expect(labelMatches('pov crotch', 'pov*crotch'), isTrue);
    expect(labelMatches('pov crotch', 'missionary'), isFalse);
  });

  test('saved mix gallery order first, new labels after', () {
    expect(data().ordered(['doggystyle', 'cowgirl', 'missionary'], 'Pose'), ['missionary', 'doggystyle', 'cowgirl']);
  });

  testWidgets('Recent tab shows pins and history; staging + Save returns adds and removes', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    List<String>? adds;
    List<String>? removes;
    await tester.pumpTestWidget(
      context,
      Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => MixLabelSheet(
            data: data(),
            current: const {'missionary'},
            have: const {'missionary': 1},
            count: 1,
            onSave: (a, r) {
              adds = a;
              removes = r;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('doggystyle + lower body'), findsOneWidget);
    expect(find.text('close up + lower body'), findsOneWidget);
    expect(find.text('Recent labels'), findsOneWidget);

    // tap a recent combo: both labels staged
    await tester.tap(find.byKey(const ValueKey('labelsheet_recent_close up+lower body')));
    await tester.pump();
    // Pose tab in the mix gallery order, untick the label already on
    await tester.tap(find.byKey(const ValueKey('labelsheet_tab_Pose')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('labelsheet_missionary')).last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('labelsheet_save')));
    await tester.pumpAndSettle();
    expect(adds, ['close up', 'lower body']);
    expect(removes, ['missionary']);
  });

  testWidgets('Swap pose: a pose combo marks the old pose for removal', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    List<String>? adds;
    List<String>? removes;
    await tester.pumpTestWidget(
      context,
      Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => MixLabelSheet(
            data: data(),
            current: const {'missionary'},
            have: const {'missionary': 1},
            count: 1,
            onSave: (a, r) {
              adds = a;
              removes = r;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Swap pose'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('labelsheet_recent_doggystyle+lower body')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('labelsheet_save')));
    await tester.pumpAndSettle();
    expect(adds, ['doggystyle', 'lower body']);
    expect(removes, ['missionary']);
  });
}
