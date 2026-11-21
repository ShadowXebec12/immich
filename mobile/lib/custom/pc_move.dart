// Custom fork (#4): move photos on the PC into the same folders the Everything F-key move AHK uses
// (everything_search_move_fkeys_master ... .ahk, read by the gallery server so they stay in step).
// The server finds each PC file from its Immich id (originalPath through the import mounts), never by
// file name, then moves it. Immich sees the new place at its next library scan.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';

/// One move menu: a model (v4.5 / v3 / v5) and its destination folders.
class PcMoveGroup {
  const PcMoveGroup(this.ver, this.title, this.dests);

  final String ver;
  final String title;
  final List<(int, String)> dests; // (index the server knows, folder name)
}

List<PcMoveGroup>? _groups;

/// The three move menus from the server (cached for the app run).
Future<List<PcMoveGroup>> pcMoveGroups() async {
  final cached = _groups;
  if (cached != null) {
    return cached;
  }
  final res = await http.get(Uri.parse('$kGalleryServer/immich_move_dests')).timeout(const Duration(seconds: 15));
  final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
  final groups = [
    for (final g in (body['groups'] as List? ?? const []))
      PcMoveGroup(g['ver'].toString(), g['title'].toString(), [
        for (final d in (g['dests'] as List? ?? const [])) ((d['i'] as num).toInt(), d['name'].toString()),
      ]),
  ];
  if (groups.isNotEmpty) {
    _groups = groups;
  }
  return groups;
}

/// Moves [assets] on the PC to destination [dest] of model [ver].
Future<void> movePhotosOnPc(WidgetRef ref, List<BaseAsset> assets, String ver, int dest, String folder) async {
  final toast = ref.read(toastServiceProvider);
  final items = [
    for (final a in assets)
      if (a.remoteId != null) {'immich_id': a.remoteId!, 'name': a.name},
  ];
  if (items.isEmpty) {
    toast.error("Not on the server yet");
    return;
  }
  try {
    final res = await http
        .post(
          Uri.parse('$kGalleryServer/immich_move'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ver': ver, 'dest': dest, 'items': items}),
        )
        .timeout(const Duration(seconds: 60));
    final d = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    if (res.statusCode != 200 || d['ok'] != true) {
      toast.error("Move failed: ${d['error'] ?? res.statusCode}");
      return;
    }
    final moved = (d['moved'] as num?)?.toInt() ?? 0;
    final failed = (d['failed'] as List? ?? const []).length;
    final msg = "Moved $moved to $folder${failed > 0 ? ' ($failed not moved)' : ''}";
    failed > 0 ? toast.error(msg) : toast.success(msg);
  } catch (_) {
    toast.error("Move failed: gallery server not reachable");
  }
}

/// Bottom sheet with the three move menus (v4.5 / v3 / v5) for [assets].
Future<void> showPcMoveSheet(BuildContext context, WidgetRef ref, List<BaseAsset> assets) async {
  List<PcMoveGroup> groups;
  try {
    groups = await pcMoveGroups();
  } catch (_) {
    ref.read(toastServiceProvider).error("Gallery server not reachable");
    return;
  }
  if (!context.mounted) {
    return;
  }
  final picked = await showModalBottomSheet<(String, int, String)>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          title: Text(
            "Move ${assets.length} photo${assets.length == 1 ? '' : 's'} on the PC",
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final g in groups)
          ExpansionTile(
            key: ValueKey('move_group_${g.ver}'),
            leading: const Icon(Icons.drive_file_move_outline),
            title: Text(g.title),
            children: [
              for (final (i, name) in g.dests)
                ListTile(
                  key: ValueKey('move_${g.ver}_$i'),
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  title: Text(name),
                  onTap: () => Navigator.of(context).pop((g.ver, i, name)),
                ),
            ],
          ),
      ],
    ),
  );
  if (picked != null) {
    await movePhotosOnPc(ref, assets, picked.$1, picked.$2, picked.$3);
  }
}

/// Viewer ... menu: one submenu per model, loaded when the menu opens.
class PcMoveMenuEntries extends StatefulWidget {
  const PcMoveMenuEntries({super.key, required this.onMove});

  final void Function(String ver, int dest, String folder) onMove;

  @override
  State<PcMoveMenuEntries> createState() => _PcMoveMenuEntriesState();
}

class _PcMoveMenuEntriesState extends State<PcMoveMenuEntries> {
  List<PcMoveGroup>? _list = _groups;

  @override
  void initState() {
    super.initState();
    if (_list == null) {
      unawaited(
        pcMoveGroups()
            .then((g) {
              if (mounted) {
                setState(() => _list = g);
              }
            })
            .catchError((Object _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _list;
    if (groups == null) {
      return const MenuItemButton(leadingIcon: Icon(Icons.drive_file_move_outline), child: Text("Move (loading)"));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups)
          SubmenuButton(
            key: ValueKey('kebab_move_${g.ver}'),
            leadingIcon: const Icon(Icons.drive_file_move_outline),
            menuChildren: [
              for (final (i, name) in g.dests)
                MenuItemButton(onPressed: () => widget.onMove(g.ver, i, name), child: Text(name)),
            ],
            child: Text(g.title),
          ),
      ],
    );
  }
}
