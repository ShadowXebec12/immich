// Custom fork: viewer quick tags, DOpus label sheet, gestures and copy image.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/label_sheet.dart';
import 'package:immich_mobile/custom/pc_copy.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/asset.provider.dart';
import 'package:immich_mobile/services/action.service.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/viewer_select_button.widget.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';

// ---------------------------------------------------------------- gestures

enum ViewerGestureAction {
  none("Nothing"),
  favorite("Favorite"),
  copyName("Copy file name"),
  copyImage("Copy image"),
  labels("Label sheet"),
  select("Select"),
  addToLastAlbum("Add to last album");

  const ViewerGestureAction(this.title);

  final String title;
}

enum ViewerGesture {
  longPress("Long press", ViewerGestureAction.labels),
  twoFingerTap("Two-finger tap", ViewerGestureAction.favorite),
  threeFingerTap("Three-finger tap", ViewerGestureAction.copyName),
  // #4: two fingers swiped sideways together (two-finger swipe up stays the album search sheet)
  twoFingerSwipeLeft("Two-finger swipe left", ViewerGestureAction.addToLastAlbum),
  twoFingerSwipeRight("Two-finger swipe right", ViewerGestureAction.none);

  const ViewerGesture(this.title, this.defaultAction);

  final String title;
  final ViewerGestureAction defaultAction;
}

/// Saved pairs look like "longPress=labels"; anything missing or unknown uses the default.
ViewerGestureAction gestureActionFor(List<String> saved, ViewerGesture gesture) {
  for (final pair in saved) {
    final parts = pair.split('=');
    if (parts.length == 2 && parts[0] == gesture.name) {
      return ViewerGestureAction.values.where((a) => a.name == parts[1]).firstOrNull ?? gesture.defaultAction;
    }
  }
  return gesture.defaultAction;
}

List<String> withGestureAction(List<String> saved, ViewerGesture gesture, ViewerGestureAction action) => [
  for (final pair in saved)
    if (!pair.startsWith('${gesture.name}=')) pair,
  '${gesture.name}=${action.name}',
];

void runViewerGesture(BuildContext context, WidgetRef ref, ViewerGesture gesture, BaseAsset asset) {
  final action = gestureActionFor(ref.read(appConfigProvider).viewer.gestures, gesture);
  unawaited(runViewerAction(context, ref, action, asset));
}

Future<void> runViewerAction(BuildContext context, WidgetRef ref, ViewerGestureAction action, BaseAsset asset) async {
  final toast = ref.read(toastServiceProvider);
  switch (action) {
    case ViewerGestureAction.none:
      return;
    case ViewerGestureAction.favorite:
      final remoteId = asset.remoteId;
      if (remoteId == null) {
        toast.error("Not on the server yet");
        return;
      }
      final favorite = !asset.isFavorite;
      await ref.read(assetServiceProvider).update([remoteId], isFavorite: .some(favorite));
      toast.success(favorite ? "Favorited" : "Unfavorited");
      if (favorite) {
        EventStream.shared.emit(const ViewerAdvanceEvent());
      }
    case ViewerGestureAction.copyName:
      await Clipboard.setData(ClipboardData(text: asset.name));
      toast.success("Copied file name");
    case ViewerGestureAction.copyImage:
      final error = await copyImageToClipboard(asset);
      error == null ? toast.success("Copied image") : toast.error(error);
    case ViewerGestureAction.labels:
      if (context.mounted) {
        await showLabelSheet(context, ref, asset);
      }
    case ViewerGestureAction.select:
      final container = ref.read(viewerSelectContainerProvider);
      container?.read(multiSelectProvider.notifier).toggleAssetSelection(asset);
    case ViewerGestureAction.addToLastAlbum:
      await addToLastAlbum(ref, asset);
  }
}

/// #4: add this photo to the album photos were last added to (any add-to-album in this app).
Future<void> addToLastAlbum(WidgetRef ref, BaseAsset asset) async {
  final toast = ref.read(toastServiceProvider);
  final albumId = ref.read(appConfigProvider).album.lastAddedId;
  final remoteId = asset.remoteId;
  if (albumId == null) {
    toast.error("No last album yet: add a photo to an album first");
    return;
  }
  if (remoteId == null) {
    toast.error("Not on the server yet");
    return;
  }
  final name = ref.read(remoteAlbumProvider).albums.where((a) => a.id == albumId).firstOrNull?.name ?? "last album";
  try {
    final r = await ref.read(remoteAlbumProvider.notifier).addAssets(albumId, [remoteId]);
    r.added > 0 ? toast.success("Added to $name") : toast.info("Already in $name");
  } catch (_) {
    toast.error("Couldn't add to $name");
  }
}

const _clipboardChannel = MethodChannel('immich.custom/clipboard');

/// Downloads the original (with the app's login) on the iOS side and puts it on the clipboard.
Future<String?> copyImageToClipboard(BaseAsset asset) async {
  final remoteId = asset.remoteId;
  if (remoteId == null) {
    return "Not on the server yet";
  }
  try {
    final ok = await _clipboardChannel.invokeMethod<bool>('copyImageUrl', {
      'url': getOriginalUrlForRemoteId(remoteId, edited: asset.isEdited),
    });
    return ok == true ? null : "Couldn't copy the image";
  } on PlatformException catch (e) {
    return e.message ?? "Couldn't copy the image";
  } on MissingPluginException {
    return "Copy image needs the iOS app";
  }
}

/// Two- and three-finger taps (no recognizer for those in Flutter). A tap = all fingers down and up
/// again within 350 ms without moving, so pinch-zoom never counts.
class MultiFingerTapListener extends StatefulWidget {
  const MultiFingerTapListener({super.key, required this.onTap, this.onSwipe, required this.child});

  final void Function(int fingers) onTap;

  /// #4: two fingers moved sideways together; true = to the left.
  final void Function(bool left)? onSwipe;
  final Widget child;

  @override
  State<MultiFingerTapListener> createState() => _MultiFingerTapListenerState();
}

class _MultiFingerTapListenerState extends State<MultiFingerTapListener> {
  final _down = <int, Offset>{};
  final _first = <int, Offset>{};
  final _last = <int, Offset>{};
  int _maxFingers = 0;
  Duration? _start;
  bool _moved = false;

  void _reset() {
    _maxFingers = 0;
    _start = null;
    _moved = false;
    _first.clear();
    _last.clear();
  }

  /// Two fingers, both moved > 80 px the same way sideways, little up/down, finger gap kept (not a pinch).
  bool? _swipeLeft(Duration end) {
    final start = _start;
    if (_maxFingers != 2 || _first.length != 2 || start == null || end - start > const Duration(milliseconds: 800)) {
      return null;
    }
    final ids = _first.keys.toList();
    final d0 = _last[ids[0]]! - _first[ids[0]]!;
    final d1 = _last[ids[1]]! - _first[ids[1]]!;
    final gapStart = (_first[ids[0]]! - _first[ids[1]]!).distance;
    final gapEnd = (_last[ids[0]]! - _last[ids[1]]!).distance;
    if (d0.dy.abs() > 70 || d1.dy.abs() > 70 || (gapEnd - gapStart).abs() > 60) {
      return null;
    }
    if (d0.dx < -80 && d1.dx < -80) {
      return true;
    }
    if (d0.dx > 80 && d1.dx > 80) {
      return false;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) {
      if (_down.isEmpty) {
        _reset();
        _start = e.timeStamp;
      }
      _down[e.pointer] = e.position;
      _first[e.pointer] = e.position;
      _last[e.pointer] = e.position;
      if (_down.length > _maxFingers) {
        _maxFingers = _down.length;
      }
    },
    onPointerMove: (e) {
      final from = _down[e.pointer];
      if (from != null) {
        _last[e.pointer] = e.position;
        if ((e.position - from).distance > 20) {
          _moved = true;
        }
      }
    },
    onPointerUp: (e) {
      _down.remove(e.pointer);
      if (_down.isEmpty) {
        final start = _start;
        if (!_moved && _maxFingers >= 2 && start != null && e.timeStamp - start < const Duration(milliseconds: 350)) {
          widget.onTap(_maxFingers);
        } else if (_moved && widget.onSwipe != null) {
          final left = _swipeLeft(e.timeStamp);
          if (left != null) {
            widget.onSwipe!(left);
          }
        }
        _reset();
      }
    },
    onPointerCancel: (e) {
      _down.remove(e.pointer);
      if (_down.isEmpty) {
        _reset();
      }
    },
    child: widget.child,
  );
}

// ---------------------------------------------------------------- labels

/// What a label or quick tag applies to: the grid selection when there is one, else this photo.
List<BaseAsset> labelTargets(WidgetRef ref, BaseAsset asset) {
  final selected = ref.read(viewerSelectContainerProvider)?.read(multiSelectProvider).selectedAssets;
  return selected != null && selected.isNotEmpty ? selected.toList() : [asset];
}

/// #3: drop the grid selection once a batch label / quick tag / rating went through (mix gallery #78).
/// #4: [always] = labels and ratings clear it after a single photo too (quick tags keep the old rule).
void clearSelectionAfterBatch(WidgetRef ref, int count, {bool always = false}) {
  if (count < 2 && !always) {
    return;
  }
  final container = ref.read(viewerSelectContainerProvider);
  if (container != null) {
    container.read(multiSelectProvider.notifier).reset();
    return;
  }
  try {
    ref.read(multiSelectProvider.notifier).reset();
  } catch (_) {
    // not under a grid scope: nothing selected to clear
  }
}

Future<void> applyLabel(WidgetRef ref, BaseAsset asset, String label, {required bool add}) async {
  final toast = ref.read(toastServiceProvider);
  final targets = labelTargets(ref, asset);
  toast.info(add ? "Labeling ${targets.length == 1 ? '' : '${targets.length} '}as $label..." : "Removing $label...");
  final error = await ref.read(galleryLabelsProvider.notifier).setLabel(targets, label, add: add);
  if (error != null) {
    toast.error(error);
    return;
  }
  toast.success(add ? "Labeled $label" : "Removed $label");
  clearSelectionAfterBatch(ref, targets.length, always: true);
  if (add && targets.length == 1) {
    EventStream.shared.emit(const ViewerAdvanceEvent());
  }
}

/// Quick tags under the photo: bad / average / no name (PC quick-tag txts) and test style (label).
class ViewerQuickTagBar extends ConsumerStatefulWidget {
  const ViewerQuickTagBar({super.key, required this.asset});

  final BaseAsset asset;

  @override
  ConsumerState<ViewerQuickTagBar> createState() => _ViewerQuickTagBarState();
}

class _ViewerQuickTagBarState extends ConsumerState<ViewerQuickTagBar> {
  Set<String> _lists = {};
  String? _loadedFor;

  void _load() {
    final asset = widget.asset;
    if (_loadedFor == asset.heroTag) {
      return;
    }
    _loadedFor = asset.heroTag;
    _lists = {};
    ref.read(galleryLabelsProvider.notifier).want(asset);
    unawaited(
      ref.read(galleryLabelsProvider.notifier).quickTagsOf(asset).then((lists) {
        if (mounted && _loadedFor == asset.heroTag) {
          setState(() => _lists = lists);
        }
      }),
    );
  }

  Future<void> _tap(QuickTag tag, bool isOn) async {
    final asset = widget.asset;
    if (tag.label != null) {
      await applyLabel(ref, asset, tag.label!, add: !isOn);
      return;
    }
    final toast = ref.read(toastServiceProvider);
    final targets = labelTargets(ref, asset);
    final notifier = ref.read(galleryLabelsProvider.notifier);
    for (final target in targets) {
      final error = await notifier.setQuickTag(target, tag.list!, add: !isOn);
      if (error != null) {
        toast.error(error);
        return;
      }
    }
    if (mounted && targets.length == 1 && _loadedFor == asset.heroTag) {
      setState(() => _lists = isOn ? ({..._lists}..remove(tag.list)) : {..._lists, tag.list!});
    }
    toast.success(isOn ? "Removed ${tag.title}" : "Added to ${tag.title}");
    clearSelectionAfterBatch(ref, targets.length);
    if (!isOn && targets.length == 1) {
      EventStream.shared.emit(const ViewerAdvanceEvent());
    }
  }

  Future<void> _pcPasteMenu(BuildContext context) async {
    final keys = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.desktop_windows_outlined),
            title: const Text("Copy image on the PC"),
            onTap: () => Navigator.of(context).pop(''),
          ),
          for (final (k, title) in kPcPasteKeys)
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(title),
              onTap: () => Navigator.of(context).pop(k),
            ),
        ],
      ),
    );
    if (keys != null) {
      await copyToPc(ref, widget.asset, keys: keys, title: keys.isEmpty ? "Copy to PC" : "Paste on PC");
    }
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final labels = ref.watch(galleryLabelsProvider.select((m) => m[labelKey(widget.asset)])) ?? const [];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final tag in kQuickTags)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Chip(
                key: ValueKey('quick_tag_${tag.title}'),
                text: tag.title,
                on: tag.list != null ? _lists.contains(tag.list) : labels.contains(tag.label),
                onTap: (on) => unawaited(_tap(tag, on)),
              ),
            ),
          _Chip(
            key: const ValueKey('viewer_label_button'),
            text: labels.isEmpty ? "Label" : "Label (${labels.length})",
            icon: Icons.label_outline_rounded,
            on: false,
            onTap: (_) => unawaited(showLabelSheet(context, ref, widget.asset)),
          ),
          const SizedBox(width: 6),
          // like the mix gallery's Copy to PC button: tap = copy on the PC, long press = paste + Alt keys
          GestureDetector(
            onLongPress: () => unawaited(_pcPasteMenu(context)),
            child: _Chip(
              key: const ValueKey('viewer_pc_copy'),
              text: "PC",
              icon: Icons.desktop_windows_outlined,
              on: false,
              onTap: (_) => unawaited(copyToPc(ref, widget.asset)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text, required this.on, required this.onTap, this.icon});

  final String text;
  final bool on;
  final IconData? icon;
  final void Function(bool on) onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: on ? Colors.white : Colors.black45,
    shape: const StadiumBorder(side: BorderSide(color: Colors.white54, width: 0.5)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: () => onTap(on),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: on ? Colors.black : Colors.white),
              const SizedBox(width: 4),
            ],
            Text(text, style: TextStyle(fontSize: 13, color: on ? Colors.black : Colors.white)),
          ],
        ),
      ),
    ),
  );
}

/// The mix gallery label sheet (lib/custom/label_sheet.dart) for this photo, or for the grid
/// selection when there is one. Save applies the picks in one DOpus call per add / remove.
Future<void> showLabelSheet(BuildContext context, WidgetRef ref, BaseAsset asset) =>
    showLabelSheetFor(context, ref, labelTargets(ref, asset));

Future<void> showLabelSheetFor(BuildContext context, WidgetRef ref, List<BaseAsset> targets) async {
  if (targets.isEmpty) {
    return;
  }
  final notifier = ref.read(galleryLabelsProvider.notifier);
  for (final t in targets) {
    notifier.want(t);
  }
  final LabelSheetData data;
  try {
    data = await LabelSheetData.load();
  } catch (_) {
    ref.read(toastServiceProvider).error("PC server not reachable");
    return;
  }
  if (!context.mounted) {
    return;
  }
  final cache = ref.read(galleryLabelsProvider);
  final have = <String, int>{};
  for (final t in targets) {
    for (final l in cache[labelKey(t)] ?? const <String>[]) {
      have[l] = (have[l] ?? 0) + 1;
    }
  }
  // "on" = on every target photo (one photo: its labels)
  final current = {
    for (final e in have.entries)
      if (e.value == targets.length) e.key,
  };
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF1C1C1E),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: MixLabelSheet(
        data: data,
        current: current,
        have: have,
        count: targets.length,
        onSave: (adds, removes) => unawaited(_saveLabels(ref, targets, adds, removes)),
      ),
    ),
  );
}

Future<void> _saveLabels(WidgetRef ref, List<BaseAsset> targets, List<String> adds, List<String> removes) async {
  final toast = ref.read(toastServiceProvider);
  final notifier = ref.read(galleryLabelsProvider.notifier);
  toast.info("Labeling ${targets.length == 1 ? '' : '${targets.length} photos '}...");
  final errors = [
    if (removes.isNotEmpty) await notifier.setLabels(targets, removes, add: false),
    if (adds.isNotEmpty) await notifier.setLabels(targets, adds, add: true),
  ].nonNulls.toList();
  if (errors.isNotEmpty) {
    toast.error(errors.first);
    return;
  }
  for (final l in adds) {
    notifier.recent
      ..remove(l)
      ..insert(0, l);
  }
  await recordLabelHistory(ref, adds);
  clearSelectionAfterBatch(ref, targets.length, always: true);
  toast.success(
    [
      if (adds.isNotEmpty) "Added ${adds.join(', ')}",
      if (removes.isNotEmpty) "Removed ${removes.join(', ')}",
    ].join(' · '),
  );
  if (adds.isNotEmpty && targets.length == 1) {
    EventStream.shared.emit(const ViewerAdvanceEvent());
  }
}

/// Quick tag menu for the grid selection (bad / average / no name / test style).
Future<void> showQuickTagMenu(BuildContext context, WidgetRef ref, List<BaseAsset> targets) async {
  final picked = await showModalBottomSheet<QuickTag>(
    context: context,
    useSafeArea: true,
    builder: (context) => ListView(
      shrinkWrap: true,
      children: [
        ListTile(title: Text("Quick tag ${targets.length} photo${targets.length == 1 ? '' : 's'}")),
        for (final tag in kQuickTags)
          ListTile(
            key: ValueKey('quick_tag_menu_${tag.title}'),
            leading: const Icon(Icons.bookmark_add_outlined),
            title: Text(tag.title),
            onTap: () => Navigator.of(context).pop(tag),
          ),
      ],
    ),
  );
  if (picked == null) {
    return;
  }
  final toast = ref.read(toastServiceProvider);
  final notifier = ref.read(galleryLabelsProvider.notifier);
  String? error;
  if (picked.label != null) {
    error = await notifier.setLabels(targets, [picked.label!], add: true);
  } else {
    for (final t in targets) {
      error = await notifier.setQuickTag(t, picked.list!, add: true);
      if (error != null) {
        break;
      }
    }
  }
  if (error == null) {
    toast.success("Added ${targets.length} to ${picked.title}");
    clearSelectionAfterBatch(ref, targets.length);
  } else {
    toast.error(error);
  }
}

/// Stars: Immich's own rating (shown in Immich) + the mix gallery ratings json on the PC.
/// [fromSelection]: the stars went to the grid selection (then it is cleared); the viewer's star row
/// rates only the photo on screen and leaves the selection alone (#4).
Future<void> rateAssets(WidgetRef ref, List<BaseAsset> targets, int stars, {bool fromSelection = false}) async {
  final toast = ref.read(toastServiceProvider);
  final service = ref.read(actionServiceProvider);
  final notifier = ref.read(galleryLabelsProvider.notifier);
  String? error;
  for (final t in targets) {
    final id = t.remoteId;
    if (id == null) {
      continue;
    }
    try {
      await service.updateRating(id, stars == 0 ? null : stars);
    } catch (_) {
      error = "Immich rating failed";
    }
    error ??= await notifier.rate(t, stars);
  }
  if (error == null) {
    toast.success(stars == 0 ? "Rating cleared" : "Rated $stars");
    if (fromSelection) {
      clearSelectionAfterBatch(ref, targets.length, always: true);
    }
  } else {
    toast.error(error);
  }
}

Future<void> showRateMenu(BuildContext context, WidgetRef ref, List<BaseAsset> targets) async {
  final stars = await showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Rate ${targets.length} photo${targets.length == 1 ? '' : 's'}"),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: ValueKey('rate_menu_$i'),
                  iconSize: 36,
                  icon: const Icon(Icons.star_rounded, color: Colors.amber),
                  onPressed: () => Navigator.of(context).pop(i),
                ),
            ],
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(0), child: const Text("Clear rating")),
        ],
      ),
    ),
  );
  if (stars != null) {
    await rateAssets(ref, targets, stars, fromSelection: true);
  }
}

/// Star row in the viewer (like the mix gallery); tap the lit star again to clear.
class ViewerStarRow extends ConsumerStatefulWidget {
  const ViewerStarRow({super.key, required this.asset});

  final BaseAsset asset;

  @override
  ConsumerState<ViewerStarRow> createState() => _ViewerStarRowState();
}

class _ViewerStarRowState extends ConsumerState<ViewerStarRow> {
  final Map<String, int> _set = {};

  @override
  Widget build(BuildContext context) {
    final exif = ref.watch(assetExifProvider(widget.asset)).valueOrNull;
    final stars = _set[widget.asset.heroTag] ?? exif?.rating ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            key: ValueKey('viewer_star_$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final value = stars == i ? 0 : i;
              setState(() => _set[widget.asset.heroTag] = value);
              unawaited(rateAssets(ref, [widget.asset], value));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(
                i <= stars ? Icons.star_rounded : Icons.star_border_rounded,
                color: i <= stars ? Colors.amber : Colors.white70,
                size: 26,
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> showGestureSettings(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      final saved = ref.watch(appConfigProvider.select((c) => c.viewer.gestures));
      return ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text("Viewer gestures")),
          for (final gesture in ViewerGesture.values)
            ListTile(
              title: Text(gesture.title),
              trailing: DropdownButton<ViewerGestureAction>(
                key: ValueKey('gesture_${gesture.name}'),
                value: gestureActionFor(saved, gesture),
                items: [for (final a in ViewerGestureAction.values) DropdownMenuItem(value: a, child: Text(a.title))],
                onChanged: (a) {
                  if (a != null) {
                    unawaited(ref.read(settingsProvider).write(.viewerGestures, withGestureAction(saved, gesture, a)));
                  }
                },
              ),
            ),
        ],
      );
    },
  ),
);

/// Settings > Preferences > Asset Viewer: viewer gesture picker.
class ViewerGestureSettings extends ConsumerWidget {
  const ViewerGestureSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(appConfigProvider.select((c) => c.viewer.gestures));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(title: Text("Viewer gestures", style: TextStyle(fontWeight: FontWeight.w600))),
        for (final gesture in ViewerGesture.values)
          ListTile(
            title: Text(gesture.title),
            trailing: DropdownButton<ViewerGestureAction>(
              value: gestureActionFor(saved, gesture),
              items: [for (final a in ViewerGestureAction.values) DropdownMenuItem(value: a, child: Text(a.title))],
              onChanged: (a) {
                if (a != null) {
                  unawaited(ref.read(settingsProvider).write(.viewerGestures, withGestureAction(saved, gesture, a)));
                }
              },
            ),
          ),
      ],
    );
  }
}

/// Tag button next to the viewer's back arrow (like the mix gallery): tap = recent labels,
/// long press = the full label sheet.
class ViewerLabelButton extends ConsumerWidget {
  const ViewerLabelButton({super.key, required this.asset});

  final BaseAsset asset;

  Future<void> _recentMenu(BuildContext context, WidgetRef ref) async {
    final recent = ref.read(galleryLabelsProvider.notifier).recent;
    if (recent.isEmpty) {
      await showLabelSheet(context, ref, asset);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final height = box?.size.height ?? 0;
    final current = ref.read(galleryLabelsProvider)[labelKey(asset)] ?? const [];
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(origin.dx, origin.dy + height, origin.dx + 1, 0),
      items: [
        for (final label in recent)
          CheckedPopupMenuItem(value: label, checked: current.contains(label), child: Text(label)),
        const PopupMenuItem(value: '\u0000all', child: Text("All labels...")),
      ],
    );
    if (picked == null || !context.mounted) {
      return;
    }
    if (picked == '\u0000all') {
      await showLabelSheet(context, ref, asset);
      return;
    }
    await applyLabel(ref, asset, picked, add: !current.contains(picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    key: const Key('viewer_tag_button'),
    onLongPress: () => unawaited(showLabelSheet(context, ref, asset)),
    child: IconButton(
      tooltip: "Labels",
      icon: const Icon(Icons.sell_outlined),
      onPressed: () => unawaited(_recentMenu(context, ref)),
    ),
  );
}
