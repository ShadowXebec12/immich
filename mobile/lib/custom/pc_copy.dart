// Custom fork: "Copy to PC" (same as the mix gallery app): the PC copies the image, optionally pastes it
// into NovelAI and presses Alt keys (only while NovelAI is the PC's active window). Plus phone copy items.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/viewer_tools.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';

/// keys: '' = copy only, 'c' / 'm' / 'i' / 'mi' = paste + Alt keys.
const kPcPasteKeys = <(String, String)>[
  ('c', "Paste + Alt+C"),
  ('mi', "Paste + Alt+M, Alt+I"),
  ('m', "Paste + Alt+M"),
  ('i', "Paste + Alt+I"),
];

Future<void> copyToPc(WidgetRef ref, BaseAsset asset, {String keys = '', String title = "Copy to PC"}) async {
  final toast = ref.read(toastServiceProvider);
  try {
    final res = await http
        .post(
          Uri.parse('$kGalleryServer/copyimage'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            if (asset.remoteId != null) 'immich_id': asset.remoteId,
            'name': asset.name,
            if (keys.isNotEmpty) 'keys': keys,
          }),
        )
        .timeout(const Duration(seconds: 25));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['ok'] != true) {
      toast.error("$title failed: ${body['err'] ?? res.statusCode}");
    } else if (body['pasted'] == false) {
      toast.error("Copied on the PC, not pasted: ${body['note'] ?? 'NovelAI not in front'}");
    } else {
      toast.success(keys.isEmpty ? "Image copied on the PC" : "$title sent");
    }
  } catch (e) {
    toast.error("$title failed: $e");
  }
}

/// Kebab menu entries: Copy (phone) and Copy to PC (with the paste + Alt key variants).
List<Widget> copyMenuEntries(BuildContext context, WidgetRef ref, BaseAsset asset) => [
  SubmenuButton(
    key: const ValueKey('kebab_copy'),
    leadingIcon: const Icon(Icons.copy_rounded),
    menuChildren: [
      MenuItemButton(
        onPressed: () => unawaited(runViewerAction(context, ref, ViewerGestureAction.copyName, asset)),
        child: const Text("File name"),
      ),
      MenuItemButton(
        onPressed: () => unawaited(runViewerAction(context, ref, ViewerGestureAction.copyImage, asset)),
        child: const Text("Image (phone clipboard)"),
      ),
      MenuItemButton(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: asset.remoteId ?? ''));
          ref.read(toastServiceProvider).success("Copied asset id");
        },
        child: const Text("Asset id"),
      ),
    ],
    child: const Text("Copy"),
  ),
  SubmenuButton(
    key: const ValueKey('kebab_copy_pc'),
    leadingIcon: const Icon(Icons.desktop_windows_outlined),
    menuChildren: [
      MenuItemButton(
        leadingIcon: const Icon(Icons.desktop_windows_outlined),
        onPressed: () => unawaited(copyToPc(ref, asset)),
        child: const Text("Copy image"),
      ),
      for (final (keys, title) in kPcPasteKeys)
        MenuItemButton(
          leadingIcon: const Icon(Icons.keyboard_outlined),
          onPressed: () => unawaited(copyToPc(ref, asset, keys: keys, title: title)),
          child: Text(title),
        ),
    ],
    child: const Text("Copy to PC"),
  ),
];
