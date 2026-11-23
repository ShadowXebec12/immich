// Custom fork (#5): the Info panel's description: read-only (selectable), folds, and sits in a narrow
// column so the albums the photo is in fit beside it.
import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/gen_menu.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/routing/router.dart';

const kInfoFoldLines = 5;
const kInfoAlbumsShown = 6;

/// Folded view: blank lines removed, so the few lines shown carry text.
String foldedDescription(String text) =>
    text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n');

class InfoDescription extends ConsumerStatefulWidget {
  const InfoDescription({super.key, required this.asset, required this.text});

  final BaseAsset asset;
  final String text;

  @override
  ConsumerState<InfoDescription> createState() => _InfoDescriptionState();
}

class _InfoDescriptionState extends ConsumerState<InfoDescription> {
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final startFolded = ref.watch(appConfigProvider.select((c) => c.viewer.descriptionCollapsed));
    final id = widget.asset.remoteId;
    final albums = id == null ? const <RemoteAlbum>[] : ref.watch(albumsContainingAssetProvider(id)).valueOrNull;
    return InfoDescriptionView(
      text: widget.text,
      open: _open ?? !startFolded,
      onToggle: (open) => setState(() => _open = open),
      albums: albums ?? const [],
      copy: CopyTextButton(
        key: const ValueKey('info_copy_description'),
        label: "Description",
        text: widget.text,
        toast: ref.read(toastServiceProvider),
        compact: true,
      ),
      onAlbum: (album) {
        ref.invalidate(assetViewerProvider);
        unawaited(context.router.popAndPush(RemoteAlbumRoute(album: album)));
      },
    );
  }
}

/// The layout, separate from the providers.
class InfoDescriptionView extends StatelessWidget {
  const InfoDescriptionView({
    super.key,
    required this.text,
    required this.open,
    required this.onToggle,
    required this.albums,
    required this.copy,
    required this.onAlbum,
  });

  final String text;
  final bool open;
  final ValueChanged<bool> onToggle;
  final List<RemoteAlbum> albums;
  final Widget copy;
  final ValueChanged<RemoteAlbum> onAlbum;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13, height: 1.35, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final shownText = open ? text : foldedDescription(text);
    final description = text.trim().isEmpty
        ? Text("No description", style: style.copyWith(color: Theme.of(context).hintColor))
        : SelectableText(
            shownText,
            key: const ValueKey('info_description_text'),
            style: style,
            maxLines: open ? null : kInfoFoldLines,
            scrollPhysics: const NeverScrollableScrollPhysics(),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const ValueKey('info_description_toggle'),
                  onTap: () => onToggle(!open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Flexible(
                          child: Text(
                            "Description",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              copy,
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 62, child: description),
              if (albums.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 38,
                  child: InfoAlbumsColumn(albums: albums, onAlbum: onAlbum),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class InfoAlbumsColumn extends StatefulWidget {
  const InfoAlbumsColumn({super.key, required this.albums, required this.onAlbum});

  final List<RemoteAlbum> albums;
  final ValueChanged<RemoteAlbum> onAlbum;

  @override
  State<InfoAlbumsColumn> createState() => _InfoAlbumsColumnState();
}

class _InfoAlbumsColumnState extends State<InfoAlbumsColumn> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.albums]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final shown = _all ? sorted : sorted.take(kInfoAlbumsShown).toList();
    final hidden = sorted.length - shown.length;
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      key: const ValueKey('info_albums'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("Albums", style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
        for (final album in shown)
          InkWell(
            key: ValueKey('info_album_${album.id}'),
            onTap: () => widget.onAlbum(album),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                album.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.2, color: color),
              ),
            ),
          ),
        if (hidden > 0 || _all && sorted.length > kInfoAlbumsShown)
          InkWell(
            key: const ValueKey('info_albums_more'),
            onTap: () => setState(() => _all = !_all),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                _all ? "Show less" : "+$hidden more",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ),
      ],
    );
  }
}

/// Settings > Asset Viewer.
class DescriptionCollapsedSetting extends ConsumerWidget {
  const DescriptionCollapsedSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
    key: const Key('description_collapsed_setting'),
    title: const Text("Description starts collapsed"),
    subtitle: const Text("In the Info panel. Tap Description to open it."),
    value: ref.watch(appConfigProvider.select((c) => c.viewer.descriptionCollapsed)),
    onChanged: (v) => unawaited(ref.read(settingsProvider).write(.viewerDescriptionCollapsed, v)),
  );
}
