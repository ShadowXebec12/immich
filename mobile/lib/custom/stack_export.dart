// Custom fork: export a stack: save its photos to the phone, or one PDF of the stack made on the PC
// (gallery server /pdf_immich finds each original by its Immich id), then the share sheet.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/data/db/main/database.dart';
import 'package:immich_mobile/data/db/main/table/remote/asset.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/repositories/download.repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Every photo of a stack, oldest first (the order they were made).
Future<List<RemoteAsset>> stackAssets(Drift db, String stackId) async {
  final q = db.remoteAssetEntity.select()
    ..where((r) => r.stackId.equals(stackId) & r.deletedAt.isNull())
    ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]);
  return q.map((r) => r.toDto()).get();
}

/// Safe file name part from a photo name.
String pdfFileName(String first, int count) {
  final base = first.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '').replaceAll(RegExp(r'[^\w\- ]+'), '_');
  final short = base.length > 40 ? base.substring(0, 40) : base;
  return "stack $short ($count).pdf";
}

Future<void> exportStackPdf(BuildContext context, WidgetRef ref, List<RemoteAsset> assets) async {
  final toast = ref.read(toastServiceProvider);
  if (assets.isEmpty) {
    return;
  }
  toast.info("Making PDF of ${assets.length} photos on the PC...");
  try {
    final res = await http
        .post(
          Uri.parse('$kGalleryServer/pdf_immich'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'items': [
              for (final a in assets) {'immich_id': a.id, 'name': a.name},
            ],
          }),
        )
        .timeout(const Duration(minutes: 3));
    if (res.statusCode != 200 || !(res.headers['content-type'] ?? '').contains('pdf')) {
      String err = "${res.statusCode}";
      try {
        err = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['err']?.toString() ?? err;
      } catch (_) {}
      toast.error("PDF failed: $err");
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${pdfFileName(assets.first.name, assets.length)}');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    if (!context.mounted) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  } catch (e) {
    toast.error("PDF failed: gallery server not reachable");
  }
}

Future<void> saveStackImages(WidgetRef ref, List<RemoteAsset> assets) async {
  final toast = ref.read(toastServiceProvider);
  toast.info("Saving ${assets.length} photos...");
  try {
    final ok = await ref.read(downloadRepositoryProvider).downloadAllAssets(assets);
    final saved = ok.where((b) => b).length;
    saved == assets.length ? toast.success("Saved $saved photos") : toast.error("Saved $saved of ${assets.length}");
  } catch (e) {
    toast.error("Save failed: $e");
  }
}

/// Export menu for a stack: Save images / PDF.
Future<void> showStackExportSheet(BuildContext context, WidgetRef ref, List<RemoteAsset> assets) async {
  final pick = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (context) => ListView(
      shrinkWrap: true,
      children: [
        ListTile(title: Text("Stack: ${assets.length} photos")),
        ListTile(
          key: const Key('stack_export_save'),
          leading: const Icon(Icons.download_rounded),
          title: const Text("Save images to Photos"),
          onTap: () => Navigator.of(context).pop('save'),
        ),
        ListTile(
          key: const Key('stack_export_pdf'),
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text("Export as PDF"),
          subtitle: const Text("Made on the PC, then the share sheet (Save to Files, etc.)"),
          onTap: () => Navigator.of(context).pop('pdf'),
        ),
      ],
    ),
  );
  if (pick == 'save') {
    await saveStackImages(ref, assets);
  } else if (pick == 'pdf' && context.mounted) {
    await exportStackPdf(context, ref, assets);
  }
}

/// Viewer menu entry: export the stack this photo belongs to.
Future<void> exportStackOf(BuildContext context, WidgetRef ref, BaseAsset asset) async {
  final stackId = asset is RemoteAsset ? asset.stackId : null;
  if (stackId == null) {
    return;
  }
  final assets = await stackAssets(ref.read(driftProvider), stackId);
  if (context.mounted) {
    await showStackExportSheet(context, ref, assets);
  }
}
