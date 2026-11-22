// UI tests for the Generate page on an iPhone-size screen: open, close (X, drag, back), Use last settings,
// chain / count pushed to the char gen, Repeat sent with the gen.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immich_mobile/custom/gen_menu.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/services/toast.service.dart';

class _Toast extends ToastService {
  final msgs = <String>[];
  @override
  FutureOr<void> success(String message, {toast}) {
    msgs.add(message);
  }
  @override
  FutureOr<void> info(String message, {toast}) {
    msgs.add(message);
  }
  @override
  FutureOr<void> error(String message, {toast}) {
    msgs.add("ERR $message");
  }
}

final _asset = RemoteAsset(
  id: 'asset1',
  name: '1girl, weiss schnee.png',
  ownerId: 'u1',
  checksum: 'c',
  type: AssetType.image,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isEdited: false,
);

void main() {
  late List<(String, Map)> calls;
  late Map<String, Object> countState;
  late MockClient client;

  setUp(() {
    calls = [];
    countState = {'ok': true, 'rep2img': 1, 'repi2i': 1, 'chainstrength': 0.0};
    client = MockClient((req) async {
      final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map;
      calls.add((req.url.path, body));
      switch (req.url.path) {
        case '/prompt':
          return http.Response(jsonEncode({'prompt': 'p'}), 200);
        case '/chargen':
          final a = body['args'] as Map;
          final v = a['value'].toString();
          if (v.isNotEmpty) {
            countState[a['name'] == 'chainstrength' ? 'chainstrength' : a['name']] =
                a['name'] == 'chainstrength' ? double.parse(v) : int.parse(v);
          }
          return http.Response(jsonEncode(countState), 200);
        case '/regen':
          return http.Response(jsonEncode({'ok': true, 'queued': 1}), 200);
      }
      return http.Response('{}', 404);
    });
  });

  Future<void> openSheet(WidgetTester tester, {GenOptions? last, List<GenOptions>? saved}) async {
    tester.view.physicalSize = const Size(1170, 2532); // iPhone 13/14
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => GenSheet(
                    asset: _asset,
                    copyOnly: false,
                    toast: _Toast(),
                    last: last,
                    queue: const [],
                    saveLast: (o) async => saved?.add(o),
                    clearQueue: () async {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('X button closes the Generate page', (tester) async {
    await http.runWithClient(() async {
      await openSheet(tester);
      expect(find.byType(GenSheet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gen_close')));
      await tester.pumpAndSettle();
      expect(find.byType(GenSheet), findsNothing);
    }, () => client);
  });

  testWidgets('drag handle down closes the Generate page', (tester) async {
    await http.runWithClient(() async {
      await openSheet(tester);
      // the grey handle above the page (what a thumb grabs on the phone)
      final top = tester.getTopLeft(find.byType(GenSheet));
      await tester.dragFrom(Offset(top.dx + 195, top.dy - 20), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byType(GenSheet), findsNothing);
    }, () => client);
  });

  testWidgets('Use last settings shows (disabled) with no history, fills the form with history', (tester) async {
    await http.runWithClient(() async {
      await openSheet(tester);
      final btn = find.byKey(const ValueKey('gen_use_last'));
      expect(btn, findsOneWidget);
      expect(find.text('Use last settings (none yet)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gen_close')));
      await tester.pumpAndSettle();

      final last = GenOptions()
        ..preset = 'i2i'
        ..strength = 0.55
        ..count = 3;
      await openSheet(tester, last: last);
      expect(find.textContaining('Use last settings: i2i, 0.55, x3'), findsOneWidget);
      // change mode away, then Use last brings i2i back
      await tester.tap(find.byKey(const ValueKey('gen_Regen')));
      await tester.pump();
      expect(find.byKey(const ValueKey('gen_strength')), findsNothing);
      await tester.tap(btn);
      await tester.pump();
      expect(find.byKey(const ValueKey('gen_strength')), findsOneWidget);
    }, () => client);
  });

  testWidgets('chain / count loads from char gen, pushes changes to both accounts, Repeat goes in /regen', (
    tester,
  ) async {
    countState['rep2img'] = 2;
    await http.runWithClient(() async {
      final saved = <GenOptions>[];
      await openSheet(tester, saved: saved);
      expect(find.text('txt2img per source: 2'), findsOneWidget); // read from the char gen
      final plus = find.byKey(const ValueKey('gen_repi2i_plus'));
      await tester.scrollUntilVisible(plus, 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(plus);
      await tester.tap(plus);
      await tester.pump();
      expect(find.text('i2i chain: 3 long'), findsOneWidget);
      expect(find.byKey(const ValueKey('gen_chain_strength')), findsOneWidget);
      calls.clear();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('gen_start')), -200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.byKey(const ValueKey('gen_start')));
      await tester.pumpAndSettle();
      final sets = calls.where((c) => c.$1 == '/chargen').toList();
      // only the changed value (repi2i), once per account (v4.5 default + v5)
      expect(sets.length, 2);
      expect(sets.map((c) => (c.$2['args'] as Map)['name']).toSet(), {'repi2i'});
      expect(sets.map((c) => c.$2['account']).toSet(), {null, 'v5'});
      expect(calls.last.$1, '/regen');
      expect(saved.single.repi2i, 3);
      expect(find.byType(GenSheet), findsNothing); // closes after a good start
    }, () => client);
  });

  testWidgets('nothing changed = no char gen writes', (tester) async {
    await http.runWithClient(() async {
      await openSheet(tester);
      calls.clear();
      await tester.tap(find.byKey(const ValueKey('gen_start')));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.$1 == '/chargen'), isEmpty);
      expect(calls.single.$1, '/regen');
    }, () => client);
  });
}
