// Custom fork: long-press a back button = the list of screens behind this one (albums, slideshows,
// viewers), newest first, plus "Back to start". Tap one to jump straight back to it.
import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/routing/router.dart';

String _titleOf(RouteData data, int position) {
  final args = data.args;
  if (args is RemoteAlbumRouteArgs) {
    return args.album.name;
  }
  if (data.name == SlideshowRoute.name) {
    return "Slideshow";
  }
  if (data.name == AssetViewerRoute.name) {
    return "Photo viewer";
  }
  if (position == 0) {
    return "Start";
  }
  return data.name.replaceAll('Route', '');
}

IconData _iconOf(RouteData data) {
  if (data.args is RemoteAlbumRouteArgs) {
    return Icons.photo_album_outlined;
  }
  if (data.name == SlideshowRoute.name) {
    return Icons.slideshow_rounded;
  }
  if (data.name == AssetViewerRoute.name) {
    return Icons.image_outlined;
  }
  return Icons.home_outlined;
}

Future<void> showRouteHistory(BuildContext context) async {
  final router = context.router.root;
  final pages = router.stack;
  if (pages.length < 2) {
    return;
  }
  unawaited(HapticFeedback.mediumImpact());
  final behind = [for (var i = pages.length - 2; i >= 0; i--) (i, pages[i])];
  final picked = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            key: const Key('route_history_start'),
            leading: const Icon(Icons.first_page_rounded),
            title: const Text("Back to start", style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.of(context).pop(0),
          ),
          const Divider(height: 1),
          for (final (i, page) in behind)
            ListTile(
              dense: true,
              leading: Icon(_iconOf(page.routeData)),
              title: Text(_titleOf(page.routeData, i), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text("${pages.length - 1 - i} back"),
              onTap: () => Navigator.of(context).pop(i),
            ),
        ],
      ),
    ),
  );
  if (picked == null) {
    return;
  }
  final target = pages[picked];
  router.popUntil((route) => identical(route.settings, target));
}

/// Back button: tap = back one screen, long press = history.
class HistoryBackButton extends StatelessWidget {
  const HistoryBackButton({super.key, this.color, this.shadows});

  final Color? color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: () => unawaited(showRouteHistory(context)),
    child: IconButton(
      icon: Icon(Platform.isIOS ? Icons.arrow_back_ios_new_rounded : Icons.arrow_back, color: color, shadows: shadows),
      onPressed: () => context.maybePop(),
    ),
  );
}
