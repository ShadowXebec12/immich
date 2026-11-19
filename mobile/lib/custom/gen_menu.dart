// Custom fork: mix gallery gen buttons + copy prompt parts, from the viewer's ... menu.
// The 8899 server maps the Immich asset to its PC file (/immich_path), then the same
// /prompt and /regen routes the mix gallery app uses do the work. No image bytes are sent.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/services/toast.service.dart';

/// Immich asset -> PC path on the gallery server (null when not found / server off).
Future<String?> pcPathFor(BaseAsset asset) async {
  try {
    final uri = Uri.parse('$kGalleryServer/immich_path').replace(
      queryParameters: {if (asset.remoteId != null) 'immich_id': asset.remoteId, 'n': asset.name},
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      return null;
    }
    final p = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['p']?.toString() ?? '';
    return p.isEmpty ? null : p;
  } catch (_) {
    return null;
  }
}

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

Map<String, Object> genBody(String path, GenPreset preset, double strength) => {
  'p': path,
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

Future<void> showGenSheet(BuildContext context, WidgetRef ref, BaseAsset asset, {bool copyOnly = false}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _GenSheet(asset: asset, copyOnly: copyOnly, toast: ref.read(toastServiceProvider)),
    );

class _GenSheet extends StatefulWidget {
  const _GenSheet({required this.asset, required this.copyOnly, required this.toast});

  final BaseAsset asset;
  final bool copyOnly;
  final ToastService toast;

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
    final p = await pcPathFor(widget.asset);
    if (!mounted) {
      return;
    }
    if (p == null) {
      setState(() => _error = "Not found on the PC (or gallery server off)");
      return;
    }
    setState(() => _path = p);
    try {
      final uri = Uri.parse('$kGalleryServer/prompt').replace(queryParameters: {'p': p});
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (!mounted) {
        return;
      }
      setState(() => _info = res.statusCode == 200 ? jsonDecode(utf8.decode(res.bodyBytes)) as Map : {});
    } catch (_) {
      if (mounted) {
        setState(() => _info = {});
      }
    }
  }

  Future<void> _gen(GenPreset preset) async {
    final p = _path;
    if (p == null || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await http
          .post(
            Uri.parse('$kGalleryServer/regen'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(genBody(p, preset, _strength)),
          )
          .timeout(const Duration(seconds: 120));
      final d = res.statusCode == 200 ? jsonDecode(utf8.decode(res.bodyBytes)) as Map : {};
      if (res.statusCode == 200 && d['ok'] != false) {
        final q = d['queued'];
        widget.toast.success("${preset.title}: ${q != null ? 'queued #$q' : 'started'}");
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        widget.toast.error("${preset.title} failed: ${d['err'] ?? d['error'] ?? res.statusCode}");
      }
    } catch (e) {
      widget.toast.error("${preset.title} failed: gallery server not reachable");
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
