// Custom fork: DOpus labels and quick tags through the PC mix gallery server (8899).
// The server finds the PC file from the Immich asset id (originalPath + import mounts),
// applies the label through DOpus and reads it back.
import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

const kGalleryLan = 'http://192.168.1.4:8899';

/// #6: the gallery runs on the same PC as Immich, so it is reached the way Immich is right now: the home
/// address on Wi-Fi, the Tailscale address on mobile data. Any other host falls back to the home address.
String galleryServerFor(String? immichEndpoint) {
  final host = Uri.tryParse(immichEndpoint ?? '')?.host ?? '';
  final tailscale = RegExp(r'^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.').hasMatch(host) || host.endsWith('.ts.net');
  return host.startsWith('192.168.') || tailscale ? 'http://$host:8899' : kGalleryLan;
}

String get kGalleryServer {
  try {
    return galleryServerFor(Store.tryGet(StoreKey.serverEndpoint));
  } catch (_) {
    return kGalleryLan; // store not open yet
  }
}

/// #6: says which address failed and how, so a screenshot of the error tells the cause.
String galleryErrorText(Object e) {
  final host = Uri.tryParse(kGalleryServer)?.host ?? '';
  if (e is TimeoutException) {
    return 'PC server timed out ($host)';
  }
  final detail = e is http.ClientException ? e.message : e.runtimeType.toString();
  final short = detail.length > 60 ? detail.substring(0, 60) : detail;
  return 'PC server not reachable ($host): $short';
}

/// Quick tags shown in the viewer. `list` = a quick-tag txt on the PC, `label` = a DOpus label.
class QuickTag {
  const QuickTag(this.title, {this.list, this.label});

  final String title;
  final String? list;
  final String? label;
}

const kQuickTags = [
  QuickTag('bad', list: 'bad'),
  QuickTag('average', list: 'average'),
  QuickTag('no name', list: 'no_name'),
  QuickTag('test style', label: 'test style'),
];

class LabelGroup {
  const LabelGroup(this.name, this.labels);

  final String name;
  final List<String> labels;
}

/// Asset name key used for the label cache (the server keys labels by filename).
String labelKey(BaseAsset asset) => asset.name.trim().toLowerCase();

Map<String, dynamic> _item(BaseAsset asset) => {
  if (asset.remoteId != null) 'immich_id': asset.remoteId,
  'name': asset.name,
};

/// filename (lower) -> labels. Filled on demand for grid tiles and the viewer.
class GalleryLabelsNotifier extends Notifier<Map<String, List<String>>> {
  final _requested = <String>{};
  final _pending = <String, Map<String, dynamic>>{};
  Timer? _timer;
  List<LabelGroup>? _groups;

  /// Labels added this session, newest first (viewer tag button menu).
  final List<String> recent = [];

  @override
  Map<String, List<String>> build() {
    ref.onDispose(() => _timer?.cancel());
    return const {};
  }

  /// Ask for this asset's labels (batched; each name once per app run).
  void want(BaseAsset asset) {
    // by Immich id: two photos can share a file name but not their stars
    final key = asset.remoteId ?? labelKey(asset);
    if (labelKey(asset).isEmpty || _requested.contains(key)) {
      return;
    }
    _requested.add(key);
    _pending[key] = _item(asset);
    _timer ??= Timer(const Duration(milliseconds: 200), _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    final keys = _pending.keys.take(400).toList();
    final items = [for (final k in keys) _pending.remove(k)!];
    final batch = [for (final it in items) it['name'].toString()];
    if (_pending.isNotEmpty) {
      _timer = Timer(const Duration(milliseconds: 50), _flush);
    }
    try {
      final res = await http
          .post(
            Uri.parse('$kGalleryServer/imglabels_batch'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'paths': batch, 'items': items, 'qt': 1}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        return;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      final labels = (decoded['labels'] as Map?) ?? {};
      final next = {...state};
      for (final entry in labels.entries) {
        next[entry.key.toString().trim().toLowerCase()] = [for (final l in (entry.value as List? ?? [])) l.toString()];
      }
      state = next;
      // quick-tag lists (bad / average / no_name ...) for the grid badges; found by Immich id on the PC
      final qt = (decoded['qt'] as Map?) ?? {};
      final qtNext = {...ref.read(galleryQuickTagsProvider)};
      for (final name in batch) {
        final key = name.trim().toLowerCase();
        qtNext[key] = {for (final l in (qt[key] as List? ?? const [])) l.toString()};
      }
      ref.read(galleryQuickTagsProvider.notifier).state = qtNext;
      // star ratings for the grid, by Immich id (the PC follows hardlinks by NTFS file id)
      final stars = (decoded['stars'] as Map?) ?? {};
      final starsNext = {...ref.read(galleryStarsProvider)};
      for (final it in items) {
        final id = it['immich_id']?.toString();
        if (id != null) {
          starsNext[id] = (stars[id] as num?)?.toInt() ?? 0;
        }
      }
      ref.read(galleryStarsProvider.notifier).state = starsNext;
    } catch (_) {
      // PC server off: no badges, nothing else breaks. Let these be asked again later.
      _requested.removeAll(keys);
    }
  }

  Future<List<LabelGroup>> groups() async {
    if (_groups != null) {
      return _groups!;
    }
    final res = await http.get(Uri.parse('$kGalleryServer/label_groups')).timeout(const Duration(seconds: 15));
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return _groups = [
      for (final g in list)
        LabelGroup(g['name'].toString(), [for (final l in (g['labels'] as List? ?? [])) l.toString()]),
    ];
  }

  void _setLabels(Iterable<String> keys, String label, bool add) {
    final next = {...state};
    for (final key in keys) {
      final cur = [...?next[key]];
      if (add && !cur.contains(label)) {
        cur.add(label);
      }
      if (!add) {
        cur.remove(label);
      }
      next[key] = cur;
    }
    state = next;
  }

  /// Add or remove one DOpus label on [assets]. Returns an error text, or null when done.
  Future<String?> setLabel(List<BaseAsset> assets, String label, {required bool add}) async {
    if (assets.isEmpty) {
      return 'Nothing selected';
    }
    final op = add ? 'add' : 'remove';
    try {
      final http.Response res;
      if (assets.length == 1) {
        res = await http
            .post(
              Uri.parse('$kGalleryServer/label'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({..._item(assets.first), 'label': label, 'op': op}),
            )
            .timeout(const Duration(seconds: 90));
      } else {
        res = await http
            .post(
              Uri.parse('$kGalleryServer/label_batch'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'items': [for (final a in assets) _item(a)],
                'labels': [label],
                'op': op,
              }),
            )
            .timeout(const Duration(seconds: 180));
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      if (res.statusCode != 200 || body['ok'] != true) {
        return (body['err'] ?? 'Label failed (${res.statusCode})').toString();
      }
      if (add) {
        recent
          ..remove(label)
          ..insert(0, label);
        if (recent.length > 10) {
          recent.removeLast();
        }
      }
      if (assets.length == 1) {
        _setLabels([labelKey(assets.first)], label, add);
        return null;
      }
      // batch results are keyed by PC path: match them back by filename
      final results = (body['results'] as Map?) ?? {};
      final done = {
        for (final e in results.entries)
          if (e.value == true) e.key.toString().split(RegExp(r'[\\/]')).last.trim().toLowerCase(),
      };
      _setLabels(assets.map(labelKey).where(done.contains), label, add);
      final failed = assets.where((a) => !done.contains(labelKey(a))).length;
      return failed == 0 ? null : '$failed of ${assets.length} not labeled';
    } catch (e) {
      return galleryErrorText(e);
    }
  }

  /// Several labels in one DOpus call (label sheet Save). Returns an error text, or null when done.
  Future<String?> setLabels(List<BaseAsset> assets, List<String> labels, {required bool add}) async {
    if (assets.isEmpty || labels.isEmpty) {
      return null;
    }
    try {
      final res = await http
          .post(
            Uri.parse('$kGalleryServer/label_batch'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'items': [for (final a in assets) _item(a)],
              'labels': labels,
              'op': add ? 'add' : 'remove',
            }),
          )
          .timeout(const Duration(seconds: 180));
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      if (res.statusCode != 200 || body['ok'] != true) {
        return (body['err'] ?? 'Label failed (${res.statusCode})').toString();
      }
      final results = (body['results'] as Map?) ?? {};
      final done = {
        for (final e in results.entries)
          if (e.value == true) e.key.toString().split(RegExp(r'[\\/]')).last.trim().toLowerCase(),
      };
      final keys = assets.map(labelKey).where(done.contains).toList();
      for (final label in labels) {
        _setLabels(keys, label, add);
      }
      final failed = assets.length - keys.length;
      return failed == 0 ? null : '$failed of ${assets.length} not labeled';
    } catch (e) {
      return galleryErrorText(e);
    }
  }

  /// Star rating in the mix gallery's ratings json (0 clears). Returns an error text, or null.
  Future<String?> rate(BaseAsset asset, int stars) async {
    try {
      final res = await http
          .post(
            Uri.parse('$kGalleryServer/rate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({..._item(asset), 'value': stars}),
          )
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      if (res.statusCode != 200 || body['ok'] != true) {
        return (body['err'] ?? 'Rating failed').toString();
      }
      final id = asset.remoteId;
      if (id != null) {
        ref.read(galleryStarsProvider.notifier).state = {...ref.read(galleryStarsProvider), id: stars};
      }
      return null;
    } catch (e) {
      return galleryErrorText(e);
    }
  }

  /// Quick-tag txt membership of one asset (keys like "bad", "no_name").
  Future<Set<String>> quickTagsOf(BaseAsset asset) async {
    final id = _item(asset)['immich_id'];
    final uri = Uri.parse(
      '$kGalleryServer/quicktag_membership',
    ).replace(queryParameters: {'n': asset.name, if (id != null) 'immich_id': id.toString()});
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      return {
        for (final k in (body['lists'] as List? ?? [])) k.toString(),
        for (final k in (body['folder'] as List? ?? [])) k.toString(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Add or remove [asset] in a quick-tag txt. Returns an error text, or null when done.
  Future<String?> setQuickTag(BaseAsset asset, String list, {required bool add}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$kGalleryServer/${add ? 'quicktag_append' : 'quicktag_remove'}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({..._item(asset), 'list': list}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        return (body['err'] ?? 'Quick tag failed (${res.statusCode})').toString();
      }
      final key = labelKey(asset);
      final qt = {...ref.read(galleryQuickTagsProvider)};
      final cur = {...?qt[key]};
      add ? cur.add(list) : cur.remove(list);
      qt[key] = cur;
      ref.read(galleryQuickTagsProvider.notifier).state = qt;
      return null;
    } catch (e) {
      return galleryErrorText(e);
    }
  }
}

final galleryLabelsProvider = NotifierProvider<GalleryLabelsNotifier, Map<String, List<String>>>(
  GalleryLabelsNotifier.new,
);

/// filename (lower) -> quick-tag list keys it is in (bad, average, no_name, ...), for grid badges.
final galleryQuickTagsProvider = StateProvider<Map<String, Set<String>>>((ref) => const {});

/// Immich asset id -> stars from the PC gallery (0 = unrated), for the grid and the viewer.
final galleryStarsProvider = StateProvider<Map<String, int>>((ref) => const {});
