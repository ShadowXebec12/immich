// Move on PC: "are you sure" dialog (setting, on by default), Undo on the result bar. iPhone size.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immich_mobile/custom/pc_move.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/domain/models/config/viewer_config.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';

final _asset = RemoteAsset(
  id: 'asset1',
  name: 'a.png',
  ownerId: 'u1',
  checksum: 'c',
  type: AssetType.image,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isEdited: false,
);

void main() {
  late List<String> calls;
  late MockClient client;
  setUp(() {
    calls = [];
    client = MockClient((req) async {
      calls.add(req.url.path);
      if (req.url.path == '/immich_move') {
        return http.Response(jsonEncode({'ok': true, 'moved': 1, 'failed': [], 'undo': 'tok1'}), 200);
      }
      if (req.url.path == '/immich_move_undo') {
        expect(jsonDecode(req.body)['undo'], 'tok1');
        return http.Response(jsonEncode({'ok': true, 'undone': 1, 'failed': []}), 200);
      }
      return http.Response('{}', 404);
    });
  });

  Future<void> pump(WidgetTester tester, {bool confirm = true}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig(viewer: ViewerConfig(confirmPcMove: confirm))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => movePhotosOnPc(context, ref, [_asset], 'v4.5', 101, 'impainted raws'),
                child: const Text('move'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('move'));
    await tester.pumpAndSettle();
  }

  testWidgets('Cancel in the "are you sure" dialog moves nothing', (tester) async {
    await http.runWithClient(() async {
      await pump(tester);
      expect(find.text('Move on PC?'), findsOneWidget);
      expect(find.textContaining('impainted raws'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pc_move_cancel')));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    }, () => client);
  });

  testWidgets('Move then Undo calls the server with the undo token', (tester) async {
    await http.runWithClient(() async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('pc_move_ok')));
      await tester.pumpAndSettle();
      expect(calls, ['/immich_move']);
      expect(find.text('Moved 1 to impainted raws'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(calls, ['/immich_move', '/immich_move_undo']);
      expect(find.textContaining('Undone: 1'), findsOneWidget);
    }, () => client);
  });

  testWidgets('setting off: no dialog, moves at once', (tester) async {
    await http.runWithClient(() async {
      await pump(tester, confirm: false);
      expect(find.text('Move on PC?'), findsNothing);
      expect(calls, ['/immich_move']);
    }, () => client);
  });
}
