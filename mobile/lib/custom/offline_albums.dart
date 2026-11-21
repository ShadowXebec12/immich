// Custom fork: offline view mode for chosen albums. Saves every photo's thumbnail + full-screen
// preview on the phone (native OfflineStore, never evicted); the image loader serves those first,
// so the album browses, slideshows and zooms (preview size) with no server. Originals are not saved.
import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:openapi/api.dart' show AssetMediaSize;
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';

const _channel = MethodChannel('immich.custom/offline');

/// How many photos are downloaded at the same time.
const kOfflineParallel = 3;

/// albumId -> progress (done, total) while a save runs.
final offlineProgressProvider = StateProvider<Map<String, (int, int)>>((ref) => const {});

final Set<String> _cancelled = {};

Future<List<String>> _albumAssetIds(WidgetRef ref, String albumId) async {
  final db = ref.read(driftProvider);
  final q = db.remoteAlbumAssetEntity.selectOnly()
    ..addColumns([db.remoteAlbumAssetEntity.assetId])
    ..where(db.remoteAlbumAssetEntity.albumId.equals(albumId));
  return [for (final row in await q.get()) row.read(db.remoteAlbumAssetEntity.assetId)!];
}

List<String> offlineUrls(String assetId) => [
  getThumbnailUrlForRemoteId(assetId, type: AssetMediaSize.thumbnail),
  getThumbnailUrlForRemoteId(assetId, type: AssetMediaSize.preview),
];

/// Saves the album's thumbnails + previews (skips ones already saved). Returns photos that failed.
Future<int> saveAlbumOffline(WidgetRef ref, String albumId) async {
  final ids = await _albumAssetIds(ref, albumId);
  _cancelled.remove(albumId);
  var done = 0;
  var failed = 0;
  void report() {
    final next = {...ref.read(offlineProgressProvider)};
    next[albumId] = (done, ids.length);
    ref.read(offlineProgressProvider.notifier).state = next;
  }

  report();
  var i = 0;
  Future<void> worker() async {
    while (i < ids.length && !_cancelled.contains(albumId)) {
      final id = ids[i++];
      try {
        final f = await _channel.invokeMethod<int>('save', {'urls': offlineUrls(id)});
        if ((f ?? 0) > 0) {
          failed++;
        }
      } on MissingPluginException {
        failed++;
      } on PlatformException {
        failed++;
      }
      done++;
      if (done % 10 == 0 || done == ids.length) {
        report();
      }
    }
  }

  await Future.wait([for (var w = 0; w < kOfflineParallel; w++) worker()]);
  final next = {...ref.read(offlineProgressProvider)}..remove(albumId);
  ref.read(offlineProgressProvider.notifier).state = next;
  return failed;
}

Future<void> removeAlbumOffline(WidgetRef ref, String albumId) async {
  final ids = await _albumAssetIds(ref, albumId);
  for (var i = 0; i < ids.length; i += 500) {
    final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
    try {
      await _channel.invokeMethod<int>('remove', {'ids': chunk});
    } on MissingPluginException {
      return;
    }
  }
}

/// Album menu: Keep offline on / off.
Future<void> toggleAlbumOffline(WidgetRef ref, String albumId, String albumName) async {
  final toast = ref.read(toastServiceProvider);
  final ids = ref.read(appConfigProvider).album.offlineIds;
  if (ids.contains(albumId)) {
    _cancelled.add(albumId);
    await ref.read(settingsProvider).write(.albumOfflineIds, ids.where((id) => id != albumId).toList());
    await removeAlbumOffline(ref, albumId);
    toast.success("$albumName: offline copy removed");
    return;
  }
  await ref.read(settingsProvider).write(.albumOfflineIds, [...ids, albumId]);
  toast.info("Saving $albumName for offline...");
  final failed = await saveAlbumOffline(ref, albumId);
  if (_cancelled.contains(albumId)) {
    return;
  }
  failed == 0 ? toast.success("$albumName is offline") : toast.error("$albumName: $failed photos not saved (tap Keep offline to retry)");
}

/// Re-save offline albums (new photos added since), e.g. when such an album is opened on Wi-Fi.
Future<void> refreshAlbumOffline(WidgetRef ref, String albumId) async {
  if (!ref.read(appConfigProvider).album.offlineIds.contains(albumId) ||
      ref.read(offlineProgressProvider).containsKey(albumId)) {
    return;
  }
  await saveAlbumOffline(ref, albumId);
}

/// Thin progress bar under the album app bar while its offline copy is being saved, with Cancel.
class OfflineProgressBar extends ConsumerWidget {
  const OfflineProgressBar({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(offlineProgressProvider.select((m) => m[albumId]));
    if (p == null) {
      return const SizedBox.shrink();
    }
    final (done, total) = p;
    return Material(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Saving offline $done / $total", style: const TextStyle(color: Colors.white, fontSize: 12)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: total == 0 ? null : done / total),
                ],
              ),
            ),
            TextButton(onPressed: () => _cancelled.add(albumId), child: const Text("Cancel")),
          ],
        ),
      ),
    );
  }
}
