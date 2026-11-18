// Custom fork: the mix gallery's label sheet (Add / Swap pose, Recent tab with pins and combos,
// one tab per label_groups.txt group, saved combos, staged picks + Save).
// Recent / pins / tab order also come from the mix gallery app's backup on the PC (/appdata), so
// both apps show the same history; this app's own labels are kept in its settings too.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';

/// Each word must appear in the label; `*` inside a word = any run of characters (mix gallery rule).
bool labelMatches(String label, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return true;
  }
  final l = label.toLowerCase();
  for (final word in q.split(RegExp(r'\s+'))) {
    if (word.contains('*')) {
      final pattern = word.split('*').map(RegExp.escape).join('.*');
      if (!RegExp(pattern).hasMatch(l)) {
        return false;
      }
    } else if (!l.contains(word)) {
      return false;
    }
  }
  return true;
}

class LabelHistoryEntry {
  const LabelHistoryEntry(this.labels, this.time);

  final List<String> labels;
  final DateTime time;

  String encode() => jsonEncode({'l': labels, 't': time.millisecondsSinceEpoch});

  static LabelHistoryEntry? decode(String s) {
    try {
      final m = jsonDecode(s) as Map;
      return LabelHistoryEntry([
        for (final l in m['l'] as List) l.toString(),
      ], DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()));
    } catch (_) {
      return null;
    }
  }
}

class SavedCombo {
  const SavedCombo(this.name, this.labels, this.group);

  final String name;
  final List<String> labels;
  final String group;
}

/// Everything the sheet needs from the PC, loaded once per app run.
class LabelSheetData {
  LabelSheetData({
    required this.tabs,
    required this.subs,
    required this.groupOf,
    required this.mixHistory,
    required this.mixPins,
    required this.order,
    required this.combos,
  });

  /// tab name -> all its labels (own + subgroups), in label_groups.txt order
  final List<(String, List<String>)> tabs;

  /// tab -> its "Parent / Sub" subgroups (short name, labels)
  final Map<String, List<(String, List<String>)>> subs;
  final Map<String, String> groupOf;
  final List<LabelHistoryEntry> mixHistory;
  final List<List<String>> mixPins;

  /// mix gallery's own chip order per tab / "tab/subgroup" (drag reorder there)
  final Map<String, List<String>> order;
  final List<SavedCombo> combos;

  List<String> ownLabels(String tab) {
    final inSub = {for (final s in subs[tab] ?? const <(String, List<String>)>[]) ...s.$2};
    return [
      for (final l in tabs.firstWhere((t) => t.$1 == tab, orElse: () => (tab, <String>[])).$2)
        if (!inSub.contains(l)) l,
    ];
  }

  List<String> ordered(List<String> list, String key) {
    final saved = order[key];
    if (saved == null || saved.isEmpty) {
      return list;
    }
    final have = list.toSet();
    final first = [
      for (final l in saved)
        if (have.contains(l)) l,
    ];
    final known = first.toSet();
    return [
      ...first,
      for (final l in list)
        if (!known.contains(l)) l,
    ];
  }

  bool isPose(String label) {
    final g = (groupOf[label.toLowerCase()] ?? '').split(' / ').first;
    return g == 'Pose' || g == 'Framing' || g == 'Secondary pose';
  }

  static LabelSheetData? _cache;

  static Future<LabelSheetData> load({bool force = false}) async {
    if (_cache != null && !force) {
      return _cache!;
    }
    Future<dynamic> get(String path) async {
      final res = await http.get(Uri.parse('$kGalleryServer$path')).timeout(const Duration(seconds: 15));
      return jsonDecode(utf8.decode(res.bodyBytes));
    }

    final results = await Future.wait([
      get('/labels?counts=1'),
      get('/label_groups'),
      get('/appdata?app=mixgallery&kind=state').catchError((_) => <String, dynamic>{}),
      get('/label_combos').catchError((_) => <String, dynamic>{}),
    ]);
    final all = [for (final l in ((results[0] as Map)['all'] as List? ?? [])) l.toString()];
    final real = {for (final l in all) l.toLowerCase(): l};
    final tabs = <(String, List<String>)>[];
    final subs = <String, List<(String, List<String>)>>{};
    final groupOf = <String, String>{};
    final used = <String>{};
    for (final g in results[1] as List) {
      final name = g['name'].toString();
      final labs = [
        for (final l in (g['labels'] as List? ?? []))
          if (real[l.toString().toLowerCase()] != null) real[l.toString().toLowerCase()]!,
      ];
      for (final l in labs) {
        used.add(l.toLowerCase());
        groupOf.putIfAbsent(l.toLowerCase(), () => name);
      }
      final parts = name.split(' / ');
      final i = tabs.indexWhere((t) => t.$1 == parts.first);
      if (parts.length > 1) {
        (subs[parts.first] ??= []).add((parts.skip(1).join(' / '), labs));
        if (i >= 0) {
          tabs[i] = (tabs[i].$1, [...tabs[i].$2, ...labs]);
        } else {
          tabs.add((parts.first, labs));
        }
      } else if (i >= 0) {
        tabs[i] = (tabs[i].$1, [...labs, ...tabs[i].$2]);
      } else {
        tabs.add((name, labs));
      }
    }
    final other = [
      for (final l in all)
        if (!used.contains(l.toLowerCase())) l,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (other.isNotEmpty) {
      tabs.add(('Other', other));
    }

    // mix gallery app backup: {"data": {key: value | {"__json": v} | {"__data": base64}}}
    final state = ((results[2] as Map?)?['data'] as Map?) ?? const {};
    dynamic unwrap(dynamic v) {
      if (v is Map && v.containsKey('__json')) {
        return v['__json'];
      }
      if (v is Map && v.containsKey('__data')) {
        try {
          return jsonDecode(utf8.decode(base64Decode(v['__data'].toString())));
        } catch (_) {
          return null;
        }
      }
      return v;
    }

    final mixHistory = <LabelHistoryEntry>[];
    final hist = unwrap(state['labelHistory']);
    if (hist is List) {
      for (final e in hist) {
        if (e is Map && e['labels'] is List && e['t'] is num) {
          // Swift Date encodes as seconds since 2001-01-01
          final secs = (e['t'] as num).toDouble() + 978307200;
          mixHistory.add(
            LabelHistoryEntry([
              for (final l in e['labels'] as List) l.toString(),
            ], DateTime.fromMillisecondsSinceEpoch((secs * 1000).round())),
          );
        }
      }
    }
    final pinsRaw = unwrap(state['labelPins']);
    final mixPins = <List<String>>[
      if (pinsRaw is List)
        for (final p in pinsRaw)
          if (p is List) [for (final l in p) l.toString()],
    ];
    final orderRaw = unwrap(state['labelSheetOrder']);
    final order = <String, List<String>>{
      if (orderRaw is Map)
        for (final e in orderRaw.entries)
          if (e.value is List) e.key.toString(): [for (final l in e.value as List) l.toString()],
    };
    final combosRaw = (results[3] as Map?)?['combos'] as List? ?? const [];
    final combos = [
      for (final c in combosRaw)
        if (c is Map && c['labels'] is List)
          SavedCombo((c['name'] ?? '').toString().isEmpty ? (c['labels'] as List).join(' + ') : c['name'].toString(), [
            for (final l in c['labels'] as List) l.toString(),
          ], (c['group'] ?? '').toString()),
    ];
    return _cache = LabelSheetData(
      tabs: tabs,
      subs: subs,
      groupOf: groupOf,
      mixHistory: mixHistory,
      mixPins: mixPins,
      order: order,
      combos: combos,
    );
  }
}

/// This app's own history and pins (settings), merged with the mix gallery's in the sheet.
List<LabelHistoryEntry> localHistory(WidgetRef ref) => [
  for (final s in ref.read(appConfigProvider).viewer.labelHistory) ?LabelHistoryEntry.decode(s),
];

List<List<String>> localPins(WidgetRef ref) => [
  for (final s in ref.read(appConfigProvider).viewer.labelPins)
    if (s.isNotEmpty) s.split('\u001f'),
];

Future<void> recordLabelHistory(WidgetRef ref, List<String> labels) async {
  if (labels.isEmpty) {
    return;
  }
  final entry = LabelHistoryEntry(labels.toSet().toList(), DateTime.now());
  final list = [...ref.read(appConfigProvider).viewer.labelHistory, entry.encode()];
  await ref
      .read(settingsProvider)
      .write(.viewerLabelHistory, list.length > 300 ? list.sublist(list.length - 300) : list);
  unawaited(_syncDopusRecent(ref));
}

Future<void> toggleLabelPin(WidgetRef ref, List<String> labels) async {
  final key = labels.join('\u001f');
  final pins = [...ref.read(appConfigProvider).viewer.labelPins];
  pins.contains(key) ? pins.remove(key) : pins.insert(0, key);
  await ref.read(settingsProvider).write(.viewerLabelPins, pins);
}

/// Same lists the mix gallery sends, so the DOpus label button shows this app's recents too.
Future<void> _syncDopusRecent(WidgetRef ref) async {
  final rows = _rows(localHistory(ref));
  try {
    await http
        .post(
          Uri.parse('$kGalleryServer/label_recent'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'recent': [for (final e in rows.where((e) => e.labels.length == 1).take(60)) e.labels.first],
            'combos': [for (final e in rows.where((e) => e.labels.length > 1).take(40)) e.labels.join(' + ')],
            'pins': [for (final p in localPins(ref)) p.join(' + ')],
          }),
        )
        .timeout(const Duration(seconds: 10));
  } catch (_) {}
}

/// newest first, one row per distinct label set
List<LabelHistoryEntry> _rows(List<LabelHistoryEntry> entries) {
  final sorted = [...entries]..sort((a, b) => b.time.compareTo(a.time));
  final seen = <String>{};
  return [
    for (final e in sorted)
      if (seen.add((List.of(e.labels)..sort()).join('\u001f'))) e,
  ];
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) {
    return 'now';
  }
  if (d.inHours < 1) {
    return '${d.inMinutes}m ago';
  }
  if (d.inDays < 1) {
    return '${d.inHours}h ago';
  }
  return '${d.inDays}d ago';
}

/// The sheet itself. [have] = label -> how many of the target photos have it (Swap pose).
class MixLabelSheet extends ConsumerStatefulWidget {
  const MixLabelSheet({
    super.key,
    required this.data,
    required this.current,
    required this.have,
    required this.count,
    required this.onSave,
  });

  final LabelSheetData data;
  final Set<String> current;
  final Map<String, int> have;
  final int count;
  final void Function(List<String> adds, List<String> removes) onSave;

  @override
  ConsumerState<MixLabelSheet> createState() => _MixLabelSheetState();
}

class _MixLabelSheetState extends ConsumerState<MixLabelSheet> {
  String _tab = 'Recent';
  String _query = '';
  late Set<String> _staged = {...widget.current};
  bool _swap = false;
  final Set<String> _swapRemove = {};
  final Set<String> _openSubs = {};
  bool _allRecentCombos = false;

  static const _blue = Color(0xFF2F7BEA);
  static const _chipBg = Color(0x1FFFFFFF);

  int get _changes =>
      _staged.difference(widget.current).length +
      widget.current.difference(_staged).length +
      (_swap ? _swapRemove.difference(widget.current.difference(_staged)).length : 0);

  List<String> get _currentPoses {
    final list = [
      for (final l in widget.have.keys)
        if (widget.data.isPose(l)) l,
    ];
    list.sort();
    return list;
  }

  void _applyCombo(List<String> labels, {required bool toggle}) {
    setState(() {
      if (toggle) {
        _staged.removeAll(labels);
        if (_swap) {
          _swapRemove.clear();
        }
        return;
      }
      _staged.addAll(labels);
      if (_swap && labels.any(widget.data.isPose)) {
        final keep = labels.toSet();
        _swapRemove
          ..clear()
          ..addAll(_currentPoses.where((p) => !keep.contains(p)));
      }
    });
  }

  void _save() {
    final adds = _staged.difference(widget.current).toList()..sort();
    final removes = {...widget.current.difference(_staged), if (_swap) ..._swapRemove}.toList()..sort();
    Navigator.of(context).pop();
    widget.onSave(adds, removes);
  }

  Widget _pill(String text, {required bool on, required VoidCallback onTap, Key? key, Color? onColor}) => Material(
    key: key,
    color: on ? (onColor ?? _blue) : _chipBg,
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    ),
  );

  Widget _chips(List<String> list, {String? orderKey}) {
    final shown = orderKey == null ? list : widget.data.ordered(list, orderKey);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final l in shown)
            _pill(
              _staged.contains(l) ? '$l ✓' : l,
              key: ValueKey('labelsheet_$l'),
              on: _staged.contains(l),
              onTap: () => setState(() => _staged.contains(l) ? _staged.remove(l) : _staged.add(l)),
            ),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Text(
      t,
      style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );

  Widget _recentRow(List<String> labels, DateTime? t, {required bool pinned}) {
    final allOn = labels.every(_staged.contains);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: allOn ? _blue.withAlpha(46) : const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('labelsheet_recent_${labels.join('+')}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => _applyCombo(labels, toggle: allOn),
          onLongPress: () async {
            await toggleLabelPin(ref, labels);
            setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (pinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.push_pin, size: 16, color: Colors.orange),
                  ),
                Expanded(
                  child: Text(
                    labels.join(' + '),
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
                if (t != null) Text(_ago(t), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                if (allOn)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.check, size: 18, color: _blue),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _recent() {
    final history = [...widget.data.mixHistory, ...localHistory(ref)];
    final local = localPins(ref);
    final pins = <List<String>>[...local];
    for (final p in widget.data.mixPins) {
      if (!pins.any((q) => q.join('\u001f') == p.join('\u001f'))) {
        pins.add(p);
      }
    }
    final pinKeys = {for (final p in pins) p.join('\u001f')};
    final rows = _rows(history).where((e) => !pinKeys.contains(e.labels.join('\u001f'))).toList();
    final combos = rows.where((e) => e.labels.length > 1).toList();
    final singles = rows.where((e) => e.labels.length == 1).toList();
    return [
      if (pins.isEmpty && rows.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text("Labels you add show up here.", style: TextStyle(color: Colors.white54)),
        ),
      if (pins.isNotEmpty) _header("Pinned"),
      for (final p in pins) _recentRow(p, null, pinned: true),
      if (combos.isNotEmpty) _header("Recent combos"),
      for (final e in combos.take(_allRecentCombos ? 30 : 5)) _recentRow(e.labels, e.time, pinned: false),
      if (combos.length > 5 && !_allRecentCombos)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _allRecentCombos = true),
            child: Text("More (${(combos.length > 30 ? 30 : combos.length) - 5})"),
          ),
        ),
      if (singles.isNotEmpty) _header("Recent labels"),
      for (final e in singles.take(60)) _recentRow(e.labels, e.time, pinned: false),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text("Hold a row to pin or unpin it.", style: TextStyle(color: Colors.white38, fontSize: 12)),
      ),
    ];
  }

  Widget _subgroup(String key, String title, List<String> list) {
    final isOpen = _openSubs.contains(key) || list.any(_staged.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _openSubs.contains(key) ? _openSubs.remove(key) : _openSubs.add(key)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(isOpen ? Icons.expand_more : Icons.chevron_right, color: Colors.white, size: 20),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text('${list.length}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ),
        if (isOpen) _chips(list, orderKey: key),
      ],
    );
  }

  Widget _comboRow() {
    final combos = widget.data.combos;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text(
            "Combos",
            style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          for (final c in combos.take(3)) ...[
            _pill(
              c.name,
              on: c.labels.every(_staged.contains),
              onColor: _blue,
              onTap: () => _applyCombo(c.labels, toggle: c.labels.every(_staged.contains)),
            ),
            const SizedBox(width: 6),
          ],
          if (combos.isNotEmpty)
            TextButton(
              onPressed: () async {
                final picked = await showModalBottomSheet<SavedCombo>(
                  context: context,
                  backgroundColor: const Color(0xFF1C1C1E),
                  builder: (context) => ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in combos)
                        ListTile(
                          title: Text(c.name, style: const TextStyle(color: Colors.white)),
                          subtitle: c.group.isEmpty
                              ? null
                              : Text(c.group, style: const TextStyle(color: Colors.white54)),
                          onTap: () => Navigator.of(context).pop(c),
                        ),
                    ],
                  ),
                );
                if (picked != null) {
                  _applyCombo(picked.labels, toggle: false);
                }
              },
              child: Text("More (${combos.length})"),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final allLabels = <String>{for (final t in data.tabs) ...t.$2}.toList();
    final body = <Widget>[
      if (!_swap && _query.isEmpty && widget.current.isNotEmpty) ...[
        _header("Already on"),
        _chips(widget.current.toList()..sort()),
      ],
      if (_query.isNotEmpty)
        _chips([
          for (final l in allLabels)
            if (labelMatches(l, _query)) l,
        ])
      else if (_tab == 'Recent')
        ..._recent()
      else ...[
        _chips(data.ownLabels(_tab), orderKey: _tab),
        for (final sg in data.subs[_tab] ?? const <(String, List<String>)>[]) _subgroup('$_tab/${sg.$1}', sg.$1, sg.$2),
      ],
      const SizedBox(height: 24),
    ];

    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Material(
        color: const Color(0xFF1C1C1E),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  TextButton(
                    key: const Key('labelsheet_clear'),
                    onPressed: _changes == 0
                        ? null
                        : () => setState(() {
                            _staged = {...widget.current};
                            _swapRemove.clear();
                          }),
                    child: const Text("Clear", style: TextStyle(fontSize: 17)),
                  ),
                  Expanded(
                    child: Text(
                      widget.count == 1 ? "Labels" : "Labels (${widget.count})",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    key: const Key('labelsheet_save'),
                    onPressed: _changes == 0 ? null : _save,
                    child: Text(
                      (_swap ? "Swap" : "Save") + (_changes == 0 ? "" : " ($_changes)"),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SegmentedButton<bool>(
                  key: const Key('labelsheet_mode'),
                  segments: const [
                    ButtonSegment(value: false, label: Text("Add")),
                    ButtonSegment(value: true, label: Text("Swap pose")),
                  ],
                  selected: {_swap},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _swap = s.first;
                    if (_swap) {
                      _tab = 'Recent';
                    } else {
                      _swapRemove.clear();
                    }
                  }),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
              ),
              if (_swap)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentPoses.isEmpty ? "No pose labels on these photos" : "Tap to choose which to remove",
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final l in _currentPoses)
                            _pill(
                              (widget.have[l] ?? 0) > 1 ? '$l · ${widget.have[l]}' : l,
                              on: _swapRemove.contains(l),
                              onColor: Colors.red.withAlpha(110),
                              onTap: () =>
                                  setState(() => _swapRemove.contains(l) ? _swapRemove.remove(l) : _swapRemove.add(l)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  key: const Key('labelsheet_search'),
                  autocorrect: false,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Search all labels",
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0x1AFFFFFF),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (_query.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in ['Recent', ...data.tabs.map((t) => t.$1)])
                        _pill(
                          t,
                          key: ValueKey('labelsheet_tab_$t'),
                          on: _tab == t,
                          onTap: () => setState(() => _tab = t),
                        ),
                    ],
                  ),
                ),
                _comboRow(),
              ],
              Expanded(
                child: ListView(padding: EdgeInsets.zero, children: body),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
