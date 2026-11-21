// Custom fork: mix gallery gen buttons + copy prompt parts, from the viewer's ... menu.
// Same /prompt and /regen routes as the mix gallery app; like the label calls, the app sends
// the Immich asset id + filename and the 8899 server finds the PC file. No image bytes are sent.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/gallery_search.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/services/toast.service.dart';

/// How the server finds the PC file (same fields the label calls send).
Map<String, String> assetRef(BaseAsset asset) => {
  if (asset.remoteId != null) 'immich_id': asset.remoteId!,
  'name': asset.name,
};

/// A gen mode from the mix gallery's Generate menu and the body fields it sends to /regen.
class GenPreset {
  const GenPreset(this.title, this.icon, this.fields, {this.usesStrength = false});

  final String title;
  final IconData icon;
  final Map<String, Object> fields;
  final bool usesStrength;
}

const kGenPresets = [
  GenPreset('Regen', Icons.auto_awesome, {'mode': 'full'}),
  GenPreset('Regen actual', Icons.auto_awesome_outlined, {'mode': 'actual'}),
  GenPreset('i2i', Icons.blur_on, {'mode': 'i2i'}, usesStrength: true),
  GenPreset('Char ref', Icons.person_pin_outlined, {
    'mode': 'full',
    'cref': 1,
    'cref_mode': 'character',
    'cref_strength': '1.00',
    'cref_fidelity': '1.00',
    'cref_info': '1.0',
  }),
  GenPreset('i2i + ref', Icons.person_search_outlined, {
    'mode': 'i2i',
    'cref': 1,
    'cref_mode': 'character',
    'cref_strength': '1.00',
    'cref_fidelity': '1.00',
  }, usesStrength: true),
];

/// Set as template presets (same as the mix gallery's viewer menu, #84): which parts the template keeps.
const kTemplatePresets = <(String, String)>[
  ('mix', "Char + mix"),
  ('mix_settings', "Char + mix + settings"),
  ('full', "+ clothes, background, lips/glasses"),
  ('mix_settings_vibe', "Char + mix + settings + vibe"),
  ('full_vibe', "+ clothes, bg, lips/glasses + vibe"),
];

Map<String, Object> genBody(Map<String, String> ref, GenPreset preset, double strength) => {
  ...ref,
  'pose': '',
  ...preset.fields,
  if (preset.usesStrength) 'strength': strength.toStringAsFixed(2),
};

String _text(Object? v) {
  if (v == null) {
    return '';
  }
  if (v is Map) {
    return _text(v['text']);
  }
  if (v is List) {
    return v.map(_text).where((s) => s.isNotEmpty).join(', ');
  }
  return v.toString().trim();
}

/// The copy buttons, in the mix gallery's order. Empty ones are dropped.
List<(String, String)> promptCopies(Map info) {
  final s = (info['sections'] as Map?) ?? const {};
  final boxes = ((s['char_boxes'] as List?) ?? const []).map((b) => _text(b)).where((t) => t.isNotEmpty);
  final actual = (s['actual'] as Map?) ?? const {};
  final actualBoxes = ((actual['char_boxes'] as List?) ?? const []).map((b) => _text(b)).where((t) => t.isNotEmpty);
  final all = <(String, String)>[
    ('Prompt', [_text(info['prompt']), ...boxes].where((t) => t.isNotEmpty).join('\n')),
    ('Mix', _text(s['artist_mix'])),
    ('Mix ID', _text(info['mix_id'])),
    ('Face', _text(s['face'])),
    ('Body only', _text(s['body'])),
    ('Body + pose', _text(s['body_pose'])),
    ('Pose', _text(s['pose'])),
    ('Clothes', _text(s['clothes'])),
    ('Scene', _text(s['scene'])),
    ('Character', _text(s['character'])),
    ('Seed', _text(info['seed'])),
    ('Hash', _text(info['signed_hash'])),
    ('Cleaned', _text(s['cleaned'])),
    ('Actual', [_text(actual['text']), ...actualBoxes].where((t) => t.isNotEmpty).join('\n')),
  ];
  return all.where((e) => e.$2.isNotEmpty).toList();
}

/// POST /regen for one asset. Returns true when the server took it.
Future<bool> sendGen(ToastService toast, BaseAsset asset, GenPreset preset, double strength) async {
  try {
    final res = await http
        .post(
          Uri.parse('$kGalleryServer/regen'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(genBody(assetRef(asset), preset, strength)),
        )
        .timeout(const Duration(seconds: 120));
    final d = res.statusCode == 200 ? jsonDecode(utf8.decode(res.bodyBytes)) as Map : {};
    if (res.statusCode == 200 && d['ok'] != false) {
      final q = d['queued'];
      toast.success("${preset.title}: ${q != null ? 'queued #$q' : 'started'}");
      return true;
    }
    toast.error("${preset.title} failed: ${d['err'] ?? d['error'] ?? res.statusCode}");
  } catch (_) {
    toast.error("${preset.title} failed: gallery server not reachable");
  }
  return false;
}

/// The last gen sent from the Generate sheet (preset + i2i strength), or null.
(GenPreset, double)? lastGen(List<String> saved) {
  if (saved.isEmpty) {
    return null;
  }
  final preset = kGenPresets.where((p) => p.title == saved.first).firstOrNull;
  if (preset == null) {
    return null;
  }
  final strength = saved.length > 1 ? double.tryParse(saved[1]) ?? 0.78 : 0.78;
  return (preset, strength);
}

String lastGenSummary((GenPreset, double) last) =>
    last.$1.usesStrength ? "${last.$1.title} ${last.$2.toStringAsFixed(2)}" : last.$1.title;

/// "Again" in the viewer menu: same mode + strength as the last gen, on this photo, no sheet.
Future<void> genAgain(WidgetRef ref, BaseAsset asset) async {
  final last = lastGen(ref.read(appConfigProvider).viewer.lastGen);
  final toast = ref.read(toastServiceProvider);
  if (last == null) {
    toast.error("No gen yet: use Generate first");
    return;
  }
  await sendGen(toast, asset, last.$1, last.$2);
}

/// #4: every option of the Generate page (same fields the mix gallery's Generate sheet sends to /regen).
class GenOptions {
  GenOptions();

  String preset = 'Regen';
  String char = '';
  bool charVerbatim = false;
  String mixId = '';
  String mixTitle = '';
  double strength = 0.78;
  bool sameSeed = false;
  bool cref = false;
  String crefMode = 'character';
  double crefStrength = 1.0;
  double crefFidelity = 1.0;
  String model = 'source';
  bool vibe = false;
  double vibeStrength = 0.6;
  bool minimal = false;
  String extraUC = '';
  String extraTags = '';
  String extraTarget = 'main';
  int count = 1;

  static const crefModes = ['character', 'character&style', 'style'];

  bool get isI2i => preset == 'i2i';
  bool get usesStrength => preset == 'i2i' || preset == 'i2i + ref';
  bool get showsCrefSettings => preset == 'Char ref' || (preset == 'i2i + ref' && cref);

  Map<String, Object> toJson() => {
    'preset': preset,
    'char': char,
    'charVerbatim': charVerbatim,
    'mixId': mixId,
    'mixTitle': mixTitle,
    'strength': strength,
    'sameSeed': sameSeed,
    'cref': cref,
    'crefMode': crefMode,
    'crefStrength': crefStrength,
    'crefFidelity': crefFidelity,
    'model': model,
    'vibe': vibe,
    'vibeStrength': vibeStrength,
    'minimal': minimal,
    'extraUC': extraUC,
    'extraTags': extraTags,
    'extraTarget': extraTarget,
    'count': count,
  };

  static GenOptions fromJson(Map j) {
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    String t(String k, String f) => j[k]?.toString() ?? f;
    bool b(String k) => j[k] == true;
    final o = GenOptions()
      ..preset = t('preset', 'Regen')
      ..char = t('char', '')
      ..charVerbatim = b('charVerbatim')
      ..mixId = t('mixId', '')
      ..mixTitle = t('mixTitle', '')
      ..strength = d('strength', 0.78)
      ..sameSeed = b('sameSeed')
      ..cref = b('cref')
      ..crefMode = t('crefMode', 'character')
      ..crefStrength = d('crefStrength', 1.0)
      ..crefFidelity = d('crefFidelity', 1.0)
      ..model = t('model', 'source')
      ..vibe = b('vibe')
      ..vibeStrength = d('vibeStrength', 0.6)
      ..minimal = b('minimal')
      ..extraUC = t('extraUC', '')
      ..extraTags = t('extraTags', '')
      ..extraTarget = t('extraTarget', 'main')
      ..count = (j['count'] as num?)?.toInt() ?? 1;
    if (!kGenPresets.any((p) => p.title == o.preset)) {
      o.preset = 'Regen';
    }
    return o;
  }

  GenOptions copy() => fromJson(toJson());

  /// Short line for "Use last settings": mode, character, mix, strength.
  String get summary => [
    preset,
    if (char.isNotEmpty && !isI2i) char,
    if (mixId.isNotEmpty && !isI2i) "mix $mixId",
    if (usesStrength) strength.toStringAsFixed(2),
  ].join(', ');

  String _f2(double v) => v.toStringAsFixed(2);

  /// The /regen body for one photo ([ref] = immich_id + name; empty for a /regen_many batch).
  Map<String, Object> body(Map<String, String> ref) {
    final b = <String, Object>{...ref, 'pose': ''};
    if (mixId.isNotEmpty && !isI2i) {
      b['mix_id'] = mixId;
    }
    if (model != 'source') {
      b['model'] = model;
    }
    if (vibe) {
      b['vibe'] = 1;
      b['vibe_strength'] = _f2(vibeStrength);
    }
    if (minimal) {
      b['minimal'] = 1;
    }
    if (extraUC.trim().isNotEmpty) {
      b['uc'] = extraUC;
    }
    if (extraTags.trim().isNotEmpty) {
      b['extra_tags'] = extraTags;
      b['extra_tags_target'] = extraTarget;
    }
    if (count > 1) {
      b['count'] = '$count';
    }
    void withChar() {
      if (char.isNotEmpty) {
        b['char'] = char;
        if (charVerbatim) {
          b['char_verbatim'] = 1;
        }
      }
    }

    void crefFields() {
      b['cref'] = 1;
      b['cref_mode'] = crefMode;
      b['cref_strength'] = _f2(crefStrength);
      b['cref_fidelity'] = _f2(crefFidelity);
    }

    switch (preset) {
      case 'Regen actual':
        withChar();
        b['mode'] = 'actual';
      case 'i2i':
        b['mode'] = 'i2i';
        b['strength'] = _f2(strength);
      case 'Char ref':
        withChar();
        b['mode'] = 'full';
        crefFields();
        b['cref_info'] = '1.0';
      case 'i2i + ref':
        withChar();
        b['mode'] = 'i2i';
        b['strength'] = _f2(strength);
        if (cref) {
          crefFields();
        }
      default:
        withChar();
        b['mode'] = 'full';
        if (sameSeed && char.isNotEmpty) {
          b['same_seed'] = 1;
        }
    }
    return b;
  }
}

/// The last Generate page options, or null.
GenOptions? lastGenOptions(String? saved) {
  if (saved == null || saved.isEmpty) {
    return null;
  }
  try {
    return GenOptions.fromJson(jsonDecode(saved) as Map);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- gen queue (#4)

/// Queue entries are "immichId|name".
String genQueueEntry(BaseAsset asset) => "${asset.remoteId}|${asset.name}";

List<Map<String, String>> genQueueItems(List<String> queue) => [
  for (final e in queue)
    if (e.contains('|')) {'immich_id': e.substring(0, e.indexOf('|')), 'name': e.substring(e.indexOf('|') + 1)},
];

/// Adds photos to the gen queue; returns how many were new.
Future<int> addToGenQueue(WidgetRef ref, Iterable<BaseAsset> assets) async {
  final queue = List.of(ref.read(appConfigProvider).viewer.genQueue);
  var added = 0;
  for (final a in assets) {
    if (a.remoteId == null) {
      continue;
    }
    final e = genQueueEntry(a);
    if (!queue.contains(e)) {
      queue.add(e);
      added++;
    }
  }
  await ref.read(settingsProvider).write(.viewerGenQueue, queue);
  final toast = ref.read(toastServiceProvider);
  added > 0 ? toast.success("Queued $added for gen (${queue.length} total)") : toast.info("Already queued");
  return added;
}

/// Many photos = ONE /regen_many request, so the server makes one char gen job (one stop stops it all).
Future<bool> sendGenBatch(ToastService toast, List<Map<String, String>> items, GenOptions o) async {
  try {
    final body = <String, Object>{...o.body(const {}), 'items': items};
    final res = await http
        .post(
          Uri.parse('$kGalleryServer/regen_many'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));
    final d = res.statusCode == 200 ? jsonDecode(utf8.decode(res.bodyBytes)) as Map : {};
    if (res.statusCode == 200 && d['ok'] != false) {
      toast.success("${o.preset}: ${d['queued'] ?? items.length} queued as one job");
      return true;
    }
    toast.error("${o.preset} failed: ${d['error'] ?? d['err'] ?? res.statusCode}");
  } catch (_) {
    toast.error("${o.preset} failed: gallery server not reachable");
  }
  return false;
}

Future<bool> _sendOne(ToastService toast, BaseAsset asset, GenOptions o) async {
  try {
    final res = await http
        .post(
          Uri.parse('$kGalleryServer/regen'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(o.body(assetRef(asset))),
        )
        .timeout(const Duration(seconds: 120));
    final d = res.statusCode == 200 ? jsonDecode(utf8.decode(res.bodyBytes)) as Map : {};
    if (res.statusCode == 200 && d['ok'] != false) {
      final q = d['queued'];
      toast.success("${o.preset}: ${q != null ? 'queued #$q' : 'started'}");
      return true;
    }
    toast.error("${o.preset} failed: ${d['err'] ?? d['error'] ?? res.statusCode}");
  } catch (_) {
    toast.error("${o.preset} failed: gallery server not reachable");
  }
  return false;
}

Future<void> showGenSheet(BuildContext context, WidgetRef ref, BaseAsset asset, {bool copyOnly = false}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _GenSheet(
        asset: asset,
        copyOnly: copyOnly,
        toast: ref.read(toastServiceProvider),
        last: lastGenOptions(ref.read(appConfigProvider).viewer.lastGenOptions),
        queue: ref.read(appConfigProvider).viewer.genQueue,
        saveLast: (o) async {
          await ref.read(settingsProvider).write(.viewerLastGenOptions, jsonEncode(o.toJson()));
          // "Again" in the viewer menu keeps reading mode + strength from here
          await ref.read(settingsProvider).write(.viewerLastGen, [o.preset, o.strength.toStringAsFixed(2)]);
        },
        clearQueue: () => ref.read(settingsProvider).write(.viewerGenQueue, const <String>[]),
      ),
    );

class _GenSheet extends StatefulWidget {
  const _GenSheet({
    required this.asset,
    required this.copyOnly,
    required this.toast,
    required this.last,
    required this.queue,
    required this.saveLast,
    required this.clearQueue,
  });

  final BaseAsset asset;
  final bool copyOnly;
  final ToastService toast;
  final GenOptions? last;
  final List<String> queue;
  final Future<void> Function(GenOptions o) saveLast;
  final Future<void> Function() clearQueue;

  @override
  State<_GenSheet> createState() => _GenSheetState();
}

class _GenSheetState extends State<_GenSheet> {
  String? _path;
  Map? _info;
  String? _error;
  bool _sending = false;
  // the page opens with the last gen's options filled in (mix gallery #90)
  late GenOptions _o = widget.last?.copy() ?? GenOptions();
  late List<String> _queue = widget.queue;
  bool _useQueued = false;
  final _typedChar = TextEditingController();
  late final _extraUC = TextEditingController(text: _o.extraUC);
  late final _extraTags = TextEditingController(text: _o.extraTags);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _typedChar.dispose();
    _extraUC.dispose();
    _extraTags.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ref = assetRef(widget.asset);
    try {
      final uri = Uri.parse('$kGalleryServer/prompt').replace(
        queryParameters: {if (ref['immich_id'] != null) 'immich_id': ref['immich_id'], 'n': ref['name']},
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (!mounted) {
        return;
      }
      if (res.statusCode != 200) {
        setState(() => _error = "Not found on the PC");
        return;
      }
      setState(() {
        _info = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        _path = 'ok';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Gallery server not reachable");
      }
    }
  }

  void _useLast() {
    final last = widget.last;
    if (last == null) {
      return;
    }
    setState(() {
      _o = last.copy();
      _extraUC.text = _o.extraUC;
      _extraTags.text = _o.extraTags;
    });
  }

  Future<void> _start() async {
    if (_sending || (!_useQueued && _path == null)) {
      return;
    }
    _o
      ..extraUC = _extraUC.text
      ..extraTags = _extraTags.text;
    setState(() => _sending = true);
    final o = _o.copy();
    final ok = _useQueued
        ? await sendGenBatch(widget.toast, genQueueItems(_queue), o)
        : await _sendOne(widget.toast, widget.asset, o);
    if (ok) {
      await widget.saveLast(o);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
    if (mounted) {
      setState(() => _sending = false);
    }
  }

  Future<void> _pick({required bool mix}) async {
    final picked = await showModalBottomSheet<(String, String)>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.8, child: _PickList(mix: mix)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (mix) {
        _o
          ..mixId = picked.$1
          ..mixTitle = picked.$2;
      } else {
        _o
          ..char = picked.$1
          ..charVerbatim = false;
      }
    });
  }

  // Set as vibe / char ref / template: char gen commands through the gallery server (/chargen)
  Future<void> _setAs(String title, String cmd, Map<String, Object> args) async {
    if (_path == null || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await http
          .post(
            Uri.parse('$kGalleryServer/chargen'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'cmd': cmd,
              'args': {...assetRef(widget.asset), ...args},
            }),
          )
          .timeout(const Duration(seconds: 120));
      final d = res.statusCode == 200 ? jsonDecode(utf8.decode(res.bodyBytes)) as Map : {};
      if (res.statusCode == 200 && d['ok'] != false) {
        final extra = (d['char'] ?? d['name'] ?? '').toString();
        widget.toast.success(extra.isEmpty ? "$title done" : "$title: $extra");
      } else {
        widget.toast.error("$title failed: ${d['error'] ?? d['err'] ?? res.statusCode}");
      }
    } catch (e) {
      widget.toast.error("$title failed: gallery server not reachable");
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, {Key? key}) =>
      Row(
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Slider(key: key, value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
          Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 13)),
        ],
      );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  List<Widget> _genForm() {
    final o = _o;
    final canStart = !_sending && (_useQueued ? _queue.isNotEmpty : _path != null);
    return [
      Row(
        children: [
          const Expanded(
            child: Text("Generate", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
          FilledButton.icon(
            key: const ValueKey('gen_start'),
            onPressed: canStart ? _start : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(_sending ? "Sending..." : "Start"),
          ),
        ],
      ),
      if (_queue.isNotEmpty)
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                key: const ValueKey('gen_use_queued'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text("Use queued images (${_queue.length})"),
                subtitle: _useQueued ? const Text("One job for all queued photos, not this one") : null,
                value: _useQueued,
                onChanged: (v) => setState(() => _useQueued = v),
              ),
            ),
            TextButton(
              key: const ValueKey('gen_clear_queue'),
              onPressed: () async {
                await widget.clearQueue();
                if (mounted) {
                  setState(() {
                    _queue = const [];
                    _useQueued = false;
                  });
                }
              },
              child: const Text("Clear queue"),
            ),
          ],
        ),
      if (widget.last != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('gen_use_last'),
            onPressed: _useLast,
            icon: const Icon(Icons.history_rounded, size: 18),
            label: Text("Use last settings: ${widget.last!.summary}"),
          ),
        ),
      _section("Mode"),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in kGenPresets)
            ChoiceChip(
              key: ValueKey('gen_${preset.title}'),
              avatar: Icon(preset.icon, size: 18),
              label: Text(preset.title),
              selected: o.preset == preset.title,
              onSelected: (_) => setState(() => o.preset = preset.title),
            ),
        ],
      ),
      if (!o.isI2i) ...[
        _section("Character"),
        Row(
          children: [
            Expanded(
              child: Text(
                o.char.isEmpty ? "Keep source" : o.char,
                style: TextStyle(color: o.char.isEmpty ? Colors.grey : null),
              ),
            ),
            if (o.char.isNotEmpty) TextButton(onPressed: () => setState(() => o.char = ''), child: const Text("Clear")),
            TextButton(
              key: const ValueKey('gen_pick_char'),
              onPressed: () => _pick(mix: false),
              child: const Text("Pick..."),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _typedChar,
                decoration: const InputDecoration(hintText: "or type a name (used verbatim)", isDense: true),
              ),
            ),
            TextButton(
              onPressed: () {
                final t = _typedChar.text.trim();
                if (t.isNotEmpty) {
                  setState(() {
                    o.char = t;
                    o.charVerbatim = true;
                  });
                }
              },
              child: const Text("Use"),
            ),
          ],
        ),
        if (o.preset == 'Regen' && o.char.isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text("Keep the same seed"),
            value: o.sameSeed,
            onChanged: (v) => setState(() => o.sameSeed = v),
          ),
        _section("Mix"),
        Row(
          children: [
            Expanded(
              child: Text(
                o.mixId.isEmpty ? "Keep source" : (o.mixTitle.isEmpty ? o.mixId : o.mixTitle),
                style: TextStyle(color: o.mixId.isEmpty ? Colors.grey : null),
              ),
            ),
            if (o.mixId.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  o
                    ..mixId = ''
                    ..mixTitle = '';
                }),
                child: const Text("Clear"),
              ),
            TextButton(
              key: const ValueKey('gen_pick_mix'),
              onPressed: () => _pick(mix: true),
              child: const Text("Pick..."),
            ),
          ],
        ),
      ],
      if (o.usesStrength)
        _slider(
          "i2i strength",
          o.strength,
          0.05,
          0.99,
          (v) => setState(() => o.strength = (v * 100).round() / 100),
          key: const ValueKey('gen_strength'),
        ),
      _section("Reference"),
      if (o.preset == 'i2i + ref')
        SwitchListTile(
          key: const ValueKey('gen_cref_toggle'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text("Use the base image as character reference"),
          value: o.cref,
          onChanged: (v) => setState(() => o.cref = v),
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text("Use this image as vibe"),
        value: o.vibe,
        onChanged: (v) => setState(() => o.vibe = v),
      ),
      if (o.vibe) _slider("Vibe strength", o.vibeStrength, 0, 1, (v) => setState(() => o.vibeStrength = v)),
      if (o.showsCrefSettings) ...[
        Row(
          children: [
            const SizedBox(width: 110, child: Text("Ref mode", style: TextStyle(fontSize: 13))),
            DropdownButton<String>(
              value: GenOptions.crefModes.contains(o.crefMode) ? o.crefMode : 'character',
              items: [for (final m in GenOptions.crefModes) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => o.crefMode = v ?? 'character'),
            ),
          ],
        ),
        _slider("Ref strength", o.crefStrength, 0, 1, (v) => setState(() => o.crefStrength = v)),
        _slider("Ref fidelity", o.crefFidelity, 0, 1, (v) => setState(() => o.crefFidelity = v)),
      ],
      _section("This gen only"),
      Row(
        children: [
          const SizedBox(width: 110, child: Text("Model", style: TextStyle(fontSize: 13))),
          DropdownButton<String>(
            value: o.model,
            items: const [
              DropdownMenuItem(value: 'source', child: Text("Same as source")),
              DropdownMenuItem(value: 'v4.5', child: Text("v4.5")),
              DropdownMenuItem(value: 'v5', child: Text("v5")),
            ],
            onChanged: (v) => setState(() => o.model = v ?? 'source'),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text("Minimal (only character and mix change)"),
        value: o.minimal,
        onChanged: (v) => setState(() => o.minimal = v),
      ),
      Row(
        children: [
          Text("Repeat: ${o.count}"),
          IconButton(
            onPressed: o.count > 1 ? () => setState(() => o.count--) : null,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            onPressed: o.count < 10 ? () => setState(() => o.count++) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      _section("Extra for this gen"),
      TextField(
        controller: _extraUC,
        decoration: const InputDecoration(hintText: "extra UC (appended to the source UC)", isDense: true),
      ),
      TextField(
        controller: _extraTags,
        decoration: const InputDecoration(hintText: "extra tags", isDense: true),
      ),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'main', label: Text("Main")),
          ButtonSegment(value: 'female', label: Text("Female box")),
          ButtonSegment(value: 'male', label: Text("Male box")),
        ],
        selected: {o.extraTarget},
        onSelectionChanged: (v) => setState(() => o.extraTarget = v.first),
      ),
      _section("Set as"),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            key: const ValueKey('set_vibe'),
            onPressed: _path == null || _sending ? null : () => _setAs("Vibe", 'vibe_register', const {}),
            icon: const Icon(Icons.waves_rounded, size: 18),
            label: const Text("Vibe"),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('set_cref'),
            onPressed: _path == null || _sending
                ? null
                : () => _setAs("Char ref", 'charref', const {'mode': 'character'}),
            icon: const Icon(Icons.person_pin_outlined, size: 18),
            label: const Text("Char ref"),
          ),
          MenuAnchor(
            menuChildren: [
              for (final (key, title) in kTemplatePresets)
                MenuItemButton(
                  onPressed: () => _setAs("Template", 'savetemplate_from_image', {'preset': key}),
                  child: Text(title),
                ),
            ],
            builder: (context, controller, _) => FilledButton.tonalIcon(
              key: const ValueKey('set_template'),
              onPressed: _path == null || _sending
                  ? null
                  : () => controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
              label: const Text("Template ▾"),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final copies = _info == null ? null : promptCopies(_info!);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.asset.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          if (_error == null && !widget.copyOnly) ...[const SizedBox(height: 8), ..._genForm()],
          if (_error == null) ...[
            const SizedBox(height: 8),
            const Text("Copy", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (copies == null)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else if (copies.isEmpty)
              const Text("No prompt found for this image")
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in copies)
                    // #4: tap = copy, long press = Copy and paste (on the PC)
                    CopyTextButton(key: ValueKey('copy_${c.$1}'), label: c.$1, text: c.$2, toast: widget.toast),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// Character (/genchars) or mix (/genmixes) picker with a filter; pops (key, title).
class _PickList extends StatefulWidget {
  const _PickList({required this.mix});

  final bool mix;

  @override
  State<_PickList> createState() => _PickListState();
}

class _PickListState extends State<_PickList> {
  final _filter = TextEditingController();
  List<(String, String, String)>? _items; // key, title, search text
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<(String, String, String)> items;
      if (widget.mix) {
        items = [for (final m in await galleryFacet('mixes')) (m.key, m.title, m.search)];
      } else {
        final res = await http.get(Uri.parse('$kGalleryServer/genchars')).timeout(const Duration(seconds: 30));
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        items = [
          for (final c in (body['all'] as List? ?? const []))
            if (!c.toString().toLowerCase().startsWith('custom char'))
              (c.toString(), c.toString(), c.toString().toLowerCase()),
        ];
      }
      if (mounted) {
        setState(() => _items = items);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Gallery server not reachable");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final words = _filter.text.trim().toLowerCase().split(RegExp(r'[\s,]+')).where((w) => w.isNotEmpty).toList();
    final shown = items == null
        ? const <(String, String, String)>[]
        : items.where((i) => words.every(i.$3.contains)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _filter,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: widget.mix ? "Filter mixes (name, id, artist)" : "Filter characters",
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        if (items == null && _error == null)
          const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) => ListTile(
              dense: true,
              title: Text(shown[i].$2, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(context).pop((shown[i].$1, shown[i].$2)),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- copy buttons (#4)

/// Text to the PC clipboard; [paste] = also Ctrl+V there (only while NovelAI is the PC's active window).
Future<void> copyTextToPc(ToastService toast, String text, {bool paste = false}) async {
  try {
    final res = await http
        .post(
          Uri.parse('$kGalleryServer/clip_text_pc'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text, if (paste) 'paste': 1}),
        )
        .timeout(const Duration(seconds: 15));
    final d = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    if (res.statusCode != 200 || d['ok'] != true) {
      toast.error("PC copy failed: ${d['error'] ?? res.statusCode}");
    } else if (paste && d['pasted'] == false) {
      toast.error("Copied on the PC, not pasted: ${d['note'] ?? 'NovelAI not in front'}");
    } else {
      toast.success(paste ? "Pasted on the PC" : "Copied on the PC");
    }
  } catch (_) {
    toast.error("PC copy failed: gallery server not reachable");
  }
}

/// Tap = copy on the phone. Long press = Copy and paste (PC clipboard + Ctrl+V in NovelAI) or Copy to PC.
Future<void> showCopyMenu(BuildContext context, ToastService toast, String label, String text) async {
  final pick = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(dense: true, title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          ListTile(
            key: const Key('copy_and_paste'),
            leading: const Icon(Icons.content_paste_go_rounded),
            title: const Text("Copy and paste"),
            subtitle: const Text("Pastes on the PC when NovelAI is in front"),
            onTap: () => Navigator.of(context).pop('paste'),
          ),
          ListTile(
            leading: const Icon(Icons.desktop_windows_outlined),
            title: const Text("Copy to PC"),
            onTap: () => Navigator.of(context).pop('pc'),
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text("Copy"),
            onTap: () => Navigator.of(context).pop('copy'),
          ),
        ],
      ),
    ),
  );
  switch (pick) {
    case 'paste':
      await Clipboard.setData(ClipboardData(text: text));
      await copyTextToPc(toast, text, paste: true);
    case 'pc':
      await copyTextToPc(toast, text);
    case 'copy':
      await Clipboard.setData(ClipboardData(text: text));
      toast.success("Copied $label");
  }
}

class CopyTextButton extends StatelessWidget {
  const CopyTextButton({super.key, required this.label, required this.text, required this.toast, this.compact = false});

  final String label;
  final String text;
  final ToastService toast;

  /// compact = the small "Copy" text button used on section headers.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: text));
      toast.success("Copied $label");
    }

    return GestureDetector(
      onLongPress: () => unawaited(showCopyMenu(context, toast, label, text)),
      child: compact
          ? TextButton.icon(
              onPressed: copy,
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text("Copy"),
            )
          : OutlinedButton(onPressed: copy, child: Text(label)),
    );
  }
}
