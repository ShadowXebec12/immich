// Custom fork: grid labels in priority order (pose first), shrunk to fit the tile, plus the mix
// gallery's label badges (a chosen label -> 1-3 letters on a colored chip, set in Settings).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';

/// label_groups.txt group -> display tier (lower shows first). Exact names win over prefixes,
/// so "Model / Request type" is not caught by "Model".
const _exactTiers = {
  'framing': 0,
  'pose': 1,
  'secondary pose': 2,
  'style': 3,
  'body': 4,
  'model': 6,
  'model / cross model gen': 6,
  'model / request type': 7,
};
const _prefixTiers = [('secondary pose', 2), ('body', 4)];
const _quickTagTier = 5;
const _otherTier = 8;

int groupTier(String group) {
  final g = group.trim().toLowerCase();
  final exact = _exactTiers[g];
  if (exact != null) {
    return exact;
  }
  for (final (prefix, tier) in _prefixTiers) {
    if (g.startsWith(prefix)) {
      return tier;
    }
  }
  return _otherTier;
}

/// label (lowercase) -> tier, from the gallery's label groups (loaded once).
final labelTiersProvider = FutureProvider<Map<String, int>>((ref) async {
  final groups = await ref.read(galleryLabelsProvider.notifier).groups();
  final out = <String, int>{};
  for (final g in groups) {
    final tier = groupTier(g.name);
    for (final l in g.labels) {
      final key = l.trim().toLowerCase();
      if (!out.containsKey(key) || tier < out[key]!) {
        out[key] = tier;
      }
    }
  }
  for (final q in kQuickTags) {
    final l = q.label?.toLowerCase();
    if (l != null && (out[l] ?? _otherTier) > _quickTagTier) {
      out[l] = _quickTagTier;
    }
  }
  return out;
});

/// [labels] sorted by tier; same tier keeps its original order. Unknown labels go last.
List<String> sortLabels(List<String> labels, Map<String, int> tiers) {
  final indexed = labels.indexed.toList()
    ..sort((a, b) {
      final ta = tiers[a.$2.trim().toLowerCase()] ?? _otherTier;
      final tb = tiers[b.$2.trim().toLowerCase()] ?? _otherTier;
      return ta != tb ? ta.compareTo(tb) : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Font size for [count] labels: 11 for one, smaller as more are shown, never under 7.
double labelFontSize(int count) => (11.5 - count * 1.0).clamp(7.0, 10.5);

// ---------------------------------------------------------------- badges

/// Badge key for a quick tag: its label (test style) or `qt:list` (bad / average / no_name).
String quickTagBadgeKey(QuickTag q) => q.label?.toLowerCase() ?? 'qt:${q.list}';

const kBadgeColors = <(String, Color, Color)>[
  ('White', Color(0xEBEBEBEB), Colors.black),
  ('Yellow', Color(0xF2FAC733), Colors.black),
  ('Red', Color(0xF2E34A4A), Colors.white),
  ('Blue', Color(0xF2388ADE), Colors.white),
  ('Green', Color(0xF2639921), Colors.white),
  ('Purple', Color(0xF27F78DE), Colors.white),
  ('Pink', Color(0xF2D4547D), Colors.white),
];

class LabelBadge {
  const LabelBadge(this.label, this.text, this.color);

  final String label;
  final String text;
  final String color;

  (Color, Color) get colors {
    final c = kBadgeColors.where((e) => e.$1 == color).firstOrNull ?? kBadgeColors.first;
    return (c.$2, c.$3);
  }

  String encode() => '$label=$text=$color';

  static LabelBadge? decode(String s) {
    final parts = s.split('=');
    if (parts.length < 3 || parts[0].trim().isEmpty || parts[1].trim().isEmpty) {
      return null;
    }
    return LabelBadge(parts[0].trim().toLowerCase(), parts[1].trim(), parts[2].trim());
  }
}

/// label (lowercase) -> its badge.
final labelBadgesProvider = Provider<Map<String, LabelBadge>>((ref) {
  final saved = ref.watch(appConfigProvider.select((c) => c.viewer.labelBadges));
  return {
    for (final b in saved.map(LabelBadge.decode).nonNulls) b.label: b,
  };
});

Future<void> _saveBadges(WidgetRef ref, Map<String, LabelBadge> badges) =>
    ref.read(settingsProvider).write(.viewerLabelBadges, [for (final b in badges.values) b.encode()]);

// ---------------------------------------------------------------- grid tile

/// DOpus labels on a grid thumbnail (top left): badges first, then labels in priority order,
/// smaller text when there are more or longer labels.
class GridLabelBadges extends ConsumerWidget {
  const GridLabelBadges({super.key, required this.asset});

  final BaseAsset asset;

  static const _maxShown = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(galleryLabelsProvider.select((m) => m[labelKey(asset)]));
    if (labels == null) {
      // ask after this frame: no provider writes during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(galleryLabelsProvider.notifier).want(asset);
        }
      });
      return const SizedBox.shrink();
    }
    final tiers = ref.watch(labelTiersProvider).valueOrNull ?? const <String, int>{};
    final badgeMap = ref.watch(labelBadgesProvider);
    final sorted = sortLabels(labels, tiers);
    final lists = ref.watch(galleryQuickTagsProvider.select((m) => m[labelKey(asset)])) ?? const <String>{};
    final badges = [
      // quick-tag txt lists (badge key = "qt:<list>"), then labels (test style is a label)
      for (final q in kQuickTags)
        if (q.list != null && lists.contains(q.list) && badgeMap[quickTagBadgeKey(q)] != null)
          badgeMap[quickTagBadgeKey(q)]!,
      for (final l in sorted)
        if (badgeMap[l.trim().toLowerCase()] != null) badgeMap[l.trim().toLowerCase()]!,
    ];
    if (badges.isEmpty && sorted.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = sorted.take(_maxShown).toList();
    final extra = sorted.length - shown.length;
    final size = labelFontSize(shown.length);
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  for (final b in badges)
                    Container(
                      key: ValueKey('grid_badge_${b.label}'),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: b.colors.$1, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        b.text,
                        style: TextStyle(color: b.colors.$2, fontSize: 10, fontWeight: FontWeight.w700, height: 1.2),
                      ),
                    ),
                ],
              ),
            ),
          for (final (i, label) in shown.indexed)
            Container(
              margin: const EdgeInsets.only(bottom: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  i == shown.length - 1 && extra > 0 ? "$label +$extra" : label,
                  maxLines: 1,
                  style: TextStyle(color: Colors.white, fontSize: size, height: 1.2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- settings

/// Settings > Asset viewer: "Label badges" row (like the mix gallery's Settings > Label badges).
class LabelBadgeSettingsTile extends ConsumerWidget {
  const LabelBadgeSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(labelBadgesProvider).length;
    return ListTile(
      key: const Key('label_badges_settings'),
      title: Text("Label badges ($count)"),
      subtitle: const Text("Short letters on grid photos for chosen labels."),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LabelBadgeSettingsPage())),
      ),
    );
  }
}

class LabelBadgeSettingsPage extends ConsumerStatefulWidget {
  const LabelBadgeSettingsPage({super.key});

  @override
  ConsumerState<LabelBadgeSettingsPage> createState() => _LabelBadgeSettingsPageState();
}

class _LabelBadgeSettingsPageState extends ConsumerState<LabelBadgeSettingsPage> {
  final _filter = TextEditingController();
  List<LabelGroup>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(galleryLabelsProvider.notifier)
          .groups()
          .then((g) {
            if (mounted) {
              setState(() => _groups = g);
            }
          })
          .catchError((Object _) {
            if (mounted) {
              setState(() => _error = "Gallery server not reachable");
            }
          }),
    );
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _edit(String label, LabelBadge? current, {String? title}) async {
    final text = TextEditingController(text: current?.text ?? '');
    var color = current?.color ?? 'White';
    final result = await showDialog<LabelBadge?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title ?? label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('badge_text_field'),
                controller: text,
                autofocus: true,
                maxLength: 3,
                decoration: const InputDecoration(labelText: "Badge text (1-3 letters)"),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (name, bg, fg) in kBadgeColors)
                    ChoiceChip(
                      label: Text(name, style: TextStyle(color: color == name ? fg : null)),
                      selected: color == name,
                      selectedColor: bg,
                      onSelected: (_) => setLocal(() => color = name),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            if (current != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(LabelBadge(label, '', '')),
                child: const Text("Remove"),
              ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(LabelBadge(label, text.text.trim(), color)),
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    if (result == null) {
      return;
    }
    final next = {...ref.read(labelBadgesProvider)};
    final key = label.trim().toLowerCase();
    if (result.text.isEmpty) {
      next.remove(key);
    } else {
      next[key] = LabelBadge(key, result.text, result.color);
    }
    await _saveBadges(ref, next);
  }

  Widget _badgeChip(LabelBadge b) {
    final (bg, fg) = b.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(b.text, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final badges = ref.watch(labelBadgesProvider);
    final f = _filter.text.trim().toLowerCase();
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(title: const Text("Label badges")),
      body: ListView(
        children: [
          if (badges.isEmpty)
            const ListTile(title: Text("No badges yet. Pick a label below."))
          else
            for (final b in badges.values)
              ListTile(
                key: ValueKey('badge_row_${b.label}'),
                leading: _badgeChip(b),
                title: Text(b.label.startsWith('qt:') ? 'quick tag: ${b.label.substring(3).replaceAll('_', ' ')}' : b.label),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => unawaited(_edit(b.label, b)),
              ),
          const Divider(),
          const ListTile(dense: true, title: Text("Quick tags", style: TextStyle(fontWeight: FontWeight.w600))),
          for (final q in kQuickTags)
            ListTile(
              key: ValueKey('badge_qt_${q.title}'),
              dense: true,
              title: Text(q.title),
              trailing: badges[quickTagBadgeKey(q)] != null ? _badgeChip(badges[quickTagBadgeKey(q)]!) : null,
              onTap: () => unawaited(_edit(quickTagBadgeKey(q), badges[quickTagBadgeKey(q)], title: q.title)),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _filter,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Filter labels",
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_error != null) ListTile(title: Text(_error!)),
          if (groups == null && _error == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (groups != null)
            for (final g in groups)
              for (final l in g.labels)
                if (f.isEmpty || l.toLowerCase().contains(f))
                  ListTile(
                    dense: true,
                    title: Text(l),
                    subtitle: Text(g.name),
                    trailing: badges[l.trim().toLowerCase()] != null ? _badgeChip(badges[l.trim().toLowerCase()]!) : null,
                    onTap: () => unawaited(_edit(l, badges[l.trim().toLowerCase()])),
                  ),
        ],
      ),
    );
  }
}
