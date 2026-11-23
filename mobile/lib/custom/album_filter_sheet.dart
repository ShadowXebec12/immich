// Custom fork (#5): in-album Filters sheet, modeled on the mix gallery's FilterSheet: every category is a
// tab on screen, labels are chips (tap: include, again: exclude, again: off), Clear / Apply at the bottom.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/gallery_search.dart';
import 'package:immich_mobile/providers/album/album_search.provider.dart';

const _kUngrouped = "Ungrouped";
const _kOtherTabs = ["Chars", "Mixes", "Model", "Dates"];
const _kInclude = Color(0xFF1F5E2E);
const _kExclude = Color(0xFF7A2424);

/// off -> include -> exclude -> off.
(List<String>, List<String>) cycleLabel(List<String> include, List<String> exclude, String label) {
  if (include.contains(label)) {
    return ([...include]..remove(label), [...exclude, label]);
  }
  if (exclude.contains(label)) {
    return (include, [...exclude]..remove(label));
  }
  return ([...include, label], exclude);
}

Future<AlbumFilter?> showAlbumFilterSheet(BuildContext context, WidgetRef ref, AlbumFilter initial) =>
    showModalBottomSheet<AlbumFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: AlbumFilterSheet(
          initial: initial,
          loadGroups: () => ref.read(galleryLabelsProvider.notifier).groups(),
          loadCounts: () async => {for (final i in await galleryFacet('labels')) i.key: i.count},
          loadFacet: galleryFacet,
        ),
      ),
    );

class AlbumFilterSheet extends StatefulWidget {
  const AlbumFilterSheet({
    super.key,
    required this.initial,
    required this.loadGroups,
    required this.loadCounts,
    required this.loadFacet,
  });

  final AlbumFilter initial;
  final Future<List<LabelGroup>> Function() loadGroups;
  final Future<Map<String, int>> Function() loadCounts;
  final Future<List<GalleryFacetItem>> Function(String kind) loadFacet;

  @override
  State<AlbumFilterSheet> createState() => _AlbumFilterSheetState();
}

class _AlbumFilterSheetState extends State<AlbumFilterSheet> {
  late AlbumFilter _draft = widget.initial;
  final _query = TextEditingController();
  late final TextEditingController _from = TextEditingController(text: widget.initial.dateFrom);
  late final TextEditingController _to = TextEditingController(text: widget.initial.dateTo);
  List<LabelGroup> _groups = const [];
  Map<String, int> _counts = const {};
  String _tab = "";
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final groups = await widget.loadGroups();
      if (!mounted) {
        return;
      }
      setState(() {
        _groups = groups;
        _tab = groups.isNotEmpty ? groups.first.name : "Chars";
        _loading = false;
      });
      final counts = await widget.loadCounts();
      if (mounted) {
        setState(() => _counts = counts);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = "PC server not reachable";
          _loading = false;
          if (_tab.isEmpty) {
            _tab = "Dates";
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  List<String> get _tabs => [
    for (final g in _groups) g.name,
    if (_groups.isNotEmpty) _kUngrouped,
    ..._kOtherTabs,
  ];

  Set<String> get _grouped => {for (final g in _groups) ...g.labels};

  List<String> _namesOf(String tab) {
    if (tab == _kUngrouped) {
      final grouped = _grouped;
      final rest = {..._counts.keys, ..._draft.labels, ..._draft.exclude}.where((l) => !grouped.contains(l)).toList()
        ..sort((a, b) => (_counts[b] ?? 0).compareTo(_counts[a] ?? 0));
      return rest;
    }
    return _groups.where((g) => g.name == tab).firstOrNull?.labels.toSet().toList() ?? const [];
  }

  int _badge(String tab) => switch (tab) {
    "Chars" => _draft.chars.length,
    "Mixes" => _draft.mixes.length,
    "Model" => _draft.models.length,
    "Dates" => (_draft.dateFrom.isEmpty ? 0 : 1) + (_draft.dateTo.isEmpty ? 0 : 1),
    _ => () {
      final names = _namesOf(tab).toSet();
      return _draft.labels.where(names.contains).length + _draft.exclude.where(names.contains).length;
    }(),
  };

  void _cycle(String label) {
    final (include, exclude) = cycleLabel(_draft.labels, _draft.exclude, label);
    setState(() => _draft = _draft.copyWith(labels: include, exclude: exclude));
  }

  Widget _tabButton(String tab, double width) {
    final on = tab == _tab;
    final n = _badge(tab);
    return SizedBox(
      width: width,
      height: 32,
      child: Material(
        color: on ? Colors.white.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('album_filter_tab_$tab'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _tab = tab),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  n > 0 ? "$tab $n" : tab,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? Colors.black : (n > 0 ? Theme.of(context).colorScheme.primary : null),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label) {
    final state = _draft.labels.contains(label) ? 1 : (_draft.exclude.contains(label) ? 2 : 0);
    final count = _counts[label] ?? 0;
    return Material(
      color: state == 1 ? _kInclude : (state == 2 ? _kExclude : Colors.white.withValues(alpha: 0.1)),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey('album_filter_label_$label'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _cycle(label),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Text(
            count > 0 ? "$label  $count" : label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: state == 0 ? null : Colors.white,
              decoration: state == 2 ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _labelBody() {
    final q = _query.text.trim().toLowerCase();
    final names = q.isEmpty
        ? _namesOf(_tab)
        : {
            for (final t in _tabs)
              if (!_kOtherTabs.contains(t)) ..._namesOf(t),
          }.where((l) => l.toLowerCase().contains(q)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: TextField(
            key: const Key('album_filter_search'),
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: "Search every label",
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: names.isEmpty
                  ? const Text("No labels here")
                  : Wrap(spacing: 6, runSpacing: 6, children: [for (final n in names) _chip(n)]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _datesBody() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      TextField(
        key: const Key('album_filter_from'),
        controller: _from,
        keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(labelText: "From (YYYY-MM-DD)", border: OutlineInputBorder(), isDense: true),
        onChanged: (v) => setState(() => _draft = _draft.copyWith(dateFrom: v.trim())),
      ),
      const SizedBox(height: 10),
      TextField(
        key: const Key('album_filter_to'),
        controller: _to,
        keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(labelText: "To (YYYY-MM-DD)", border: OutlineInputBorder(), isDense: true),
        onChanged: (v) => setState(() => _draft = _draft.copyWith(dateTo: v.trim())),
      ),
    ],
  );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (_tab) {
      "Chars" => GalleryFacetPicker(
        key: const ValueKey('album_filter_chars'),
        load: () => widget.loadFacet('chars'),
        initial: _draft.chars.toSet(),
        onChanged: (v) => setState(() => _draft = _draft.copyWith(chars: v.toList())),
      ),
      "Mixes" => GalleryFacetPicker(
        key: const ValueKey('album_filter_mixes'),
        load: () => widget.loadFacet('mixes'),
        initial: _draft.mixes.toSet(),
        onChanged: (v) => setState(() => _draft = _draft.copyWith(mixes: v.toList())),
      ),
      "Model" => GalleryFacetPicker(
        key: const ValueKey('album_filter_models'),
        load: () async => [for (final m in kGalleryModels) GalleryFacetItem(m, m, 0)],
        initial: _draft.models.toSet(),
        onChanged: (v) => setState(() => _draft = _draft.copyWith(models: v.toList())),
      ),
      "Dates" => _datesBody(),
      _ => _labelBody(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = _draft.activeCount;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              FilterChip(
                key: const Key('album_filter_fav'),
                label: const Text("Favorites"),
                selected: _draft.favorites,
                onSelected: (v) => setState(() => _draft = _draft.copyWith(favorites: v)),
              ),
              const Spacer(),
              SegmentedButton<bool>(
                key: const Key('album_filter_match'),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text("All")),
                  ButtonSegment(value: true, label: Text("Any")),
                ],
                selected: {_draft.labelAny},
                onSelectionChanged: _draft.labels.length < 2
                    ? null
                    : (v) => setState(() => _draft = _draft.copyWith(labelAny: v.first)),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 142),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, box) {
                final width = (box.maxWidth - 4 * 5) / 5;
                return Wrap(spacing: 5, runSpacing: 5, children: [for (final t in _tabs) _tabButton(t, width)]);
              },
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 8),
        Expanded(child: _body()),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('album_filter_clear'),
                    onPressed: () {
                      _from.clear();
                      _to.clear();
                      setState(() => _draft = const AlbumFilter());
                    },
                    child: const Text("Clear"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('album_filter_apply'),
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: Text(active > 0 ? "Apply ($active)" : "Apply"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
