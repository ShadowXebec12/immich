// Custom fork (#5): the order of the filter chips on the Search page, set in Settings > Asset Viewer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';

const kSearchFacets = <(String, String)>[
  ('albums', "Albums"),
  ('chars', "Characters"),
  ('labels', "Labels"),
  ('request', "Request type"),
  ('male', "Male type"),
  ('body', "Body type"),
  ('mixes', "Mix"),
  ('location', "Location"),
  ('tags', "Tags"),
  ('models', "Model"),
  ('date', "Date"),
  ('media', "Media type"),
  ('rating', "Star rating"),
  ('display', "Display options"),
];

/// [saved] order first (unknown ids dropped, no duplicates), then any facet it does not list.
List<String> orderedFacetIds(List<String> saved) {
  final known = {for (final f in kSearchFacets) f.$1};
  final out = <String>[];
  for (final id in saved) {
    if (known.contains(id) && !out.contains(id)) {
      out.add(id);
    }
  }
  for (final f in kSearchFacets) {
    if (!out.contains(f.$1)) {
      out.add(f.$1);
    }
  }
  return out;
}

class SearchFacetOrderTile extends StatelessWidget {
  const SearchFacetOrderTile({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    key: const Key('search_facet_order_settings'),
    title: const Text("Search filter order"),
    subtitle: const Text("Drag the filter chips on the Search page into your order."),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => unawaited(
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchFacetOrderPage())),
    ),
  );
}

class SearchFacetOrderPage extends ConsumerWidget {
  const SearchFacetOrderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = orderedFacetIds(ref.watch(appConfigProvider.select((c) => c.viewer.searchFacetOrder)));
    final titles = {for (final f in kSearchFacets) f.$1: f.$2};
    return Scaffold(
      appBar: AppBar(
        title: const Text("Search filter order"),
        actions: [
          TextButton(
            key: const Key('search_facet_reset'),
            onPressed: () => unawaited(ref.read(settingsProvider).write(.viewerSearchFacetOrder, const <String>[])),
            child: const Text("Reset"),
          ),
        ],
      ),
      body: ReorderableListView(
        onReorder: (from, to) {
          final next = [...ids];
          final moved = next.removeAt(from);
          next.insert(to > from ? to - 1 : to, moved);
          unawaited(ref.read(settingsProvider).write(.viewerSearchFacetOrder, next));
        },
        children: [
          for (final id in ids)
            ListTile(
              key: ValueKey('facet_$id'),
              title: Text(titles[id]!),
              trailing: const Icon(Icons.drag_handle_rounded),
            ),
        ],
      ),
    );
  }
}
