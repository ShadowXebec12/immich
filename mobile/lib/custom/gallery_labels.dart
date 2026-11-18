// Custom fork: DOpus labels and quick tags through the PC mix gallery server (8899).
// The server finds the PC file from the Immich asset id (originalPath + import mounts),
// applies the label through DOpus and reads it back.
import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';

const kGalleryServer = 'http://192.168.1.4:8899';

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
  final _pending = <String, String>{};
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
    final key = labelKey(asset);
    if (key.isEmpty || _requested.contains(key)) {
      return;
    }
    _requested.add(key);
    _pending[key] = asset.name;
    _timer ??= Timer(const Duration(milliseconds: 200), _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    final batch = _pending.values.take(400).toList();
    for (final name in batch) {
      _pending.remove(name.trim().toLowerCase());
    }
    if (_pending.isNotEmpty) {
      _timer = Timer(const Duration(milliseconds: 50), _flush);
    }
    try {
      final res = await http
          .post(
            Uri.parse('$kGalleryServer/imglabels_batch'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'paths': batch}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        return;
      }
      final labels = (jsonDecode(utf8.decode(res.bodyBytes))['labels'] as Map?) ?? {};
      final next = {...state};
      for (final entry in labels.entries) {
        next[entry.key.toString().trim().toLowerCase()] = [for (final l in (entry.value as List? ?? [])) l.toString()];
      }
      state = next;
    } catch (_) {
      // PC server off: no badges, nothing else breaks. Let these be asked again later.
      for (final name in batch) {
        _requested.remove(name.trim().toLowerCase());
      }
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
    } on TimeoutException {
      return 'PC server took too long';
    } catch (e) {
      return 'PC server not reachable';
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
    } on TimeoutException {
      return 'PC server took too long';
    } catch (_) {
      return 'PC server not reachable';
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
      return res.statusCode == 200 && body['ok'] == true ? null : (body['err'] ?? 'Rating failed').toString();
    } catch (_) {
      return 'PC server not reachable';
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
      return null;
    } catch (_) {
      return 'PC server not reachable';
    }
  }
}

final galleryLabelsProvider = NotifierProvider<GalleryLabelsNotifier, Map<String, List<String>>>(
  GalleryLabelsNotifier.new,
);
