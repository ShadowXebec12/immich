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

Future<void> showGenSheet(BuildContext context, WidgetRef ref, BaseAsset asset, {bool copyOnly = false}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _GenSheet(
        asset: asset,
        copyOnly: copyOnly,
        toast: ref.read(toastServiceProvider),
        saveLast: (preset, strength) =>
            ref.read(settingsProvider).write(.viewerLastGen, [preset.title, strength.toStringAsFixed(2)]),
      ),
    );

class _GenSheet extends StatefulWidget {
  const _GenSheet({required this.asset, required this.copyOnly, required this.toast, required this.saveLast});

  final BaseAsset asset;
  final bool copyOnly;
  final ToastService toast;
  final Future<void> Function(GenPreset preset, double strength) saveLast;

  @override
  State<_GenSheet> createState() => _GenSheetState();
}

class _GenSheetState extends State<_GenSheet> {
  String? _path;
  Map? _info;
  String? _error;
  double _strength = 0.78;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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

  Future<void> _gen(GenPreset preset) async {
    if (_path == null || _sending) {
      return;
    }
    setState(() => _sending = true);
    final ok = await sendGen(widget.toast, widget.asset, preset, _strength);
    if (ok) {
      await widget.saveLast(preset, _strength);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
    if (mounted) {
      setState(() => _sending = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final copies = _info == null ? null : promptCopies(_info!);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.asset.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          if (_error == null && !widget.copyOnly) ...[
            const SizedBox(height: 12),
            const Text("Generate", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in kGenPresets)
                  FilledButton.tonalIcon(
                    key: ValueKey('gen_${preset.title}'),
                    onPressed: _path == null || _sending ? null : () => _gen(preset),
                    icon: Icon(preset.icon, size: 18),
                    label: Text(preset.title),
                  ),
              ],
            ),
            Row(
              children: [
                const Text("i2i strength", style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Slider(
                    value: _strength,
                    min: 0.1,
                    max: 0.99,
                    divisions: 89,
                    onChanged: (v) => setState(() => _strength = v),
                  ),
                ),
                Text(_strength.toStringAsFixed(2), style: const TextStyle(fontSize: 13)),
              ],
            ),
            const Text("Set as", style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
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
          ],
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
                    OutlinedButton(
                      key: ValueKey('copy_${c.$1}'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: c.$2));
                        widget.toast.success("Copied ${c.$1}");
                      },
                      child: Text(c.$1),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
