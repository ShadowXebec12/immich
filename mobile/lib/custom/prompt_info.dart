// Custom fork (#4): the viewer's Info panel shows the NAI prompt like the mix gallery's Prompt sheet:
// quick copy chips, then Mix / Female char box / Male box / Body / Face / Sex acts / Clothes, each with a
// Copy button (long press = Copy and paste on the PC) and Show more / Show less when long.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/custom/gallery_labels.dart';
import 'package:immich_mobile/custom/gen_menu.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/services/toast.service.dart';

/// One readable block: title, text, optional small line under it.
typedef PromptBlock = ({String title, String text, String? sub});

String _str(Object? v) {
  if (v == null) {
    return '';
  }
  if (v is Map) {
    return _str(v['text']);
  }
  if (v is List) {
    return v.map(_str).where((s) => s.isNotEmpty).join(', ');
  }
  return v.toString().trim();
}

/// The sections the Info panel shows, in this order. Empty ones are left out.
List<PromptBlock> promptBlocks(Map info) {
  final s = (info['sections'] as Map?) ?? const {};
  final boxes = [
    for (final b in (s['char_boxes'] as List? ?? const []))
      if (b is Map) (gender: b['gender']?.toString().toLowerCase() ?? '', text: _str(b['text'])),
  ].where((b) => b.text.isNotEmpty).toList();
  final female = boxes.where((b) => b.gender != 'male').toList();
  final male = boxes.where((b) => b.gender == 'male').toList();
  final mix = s['artist_mix'];
  final artists = mix is Map ? (mix['sequence'] as List? ?? const []).map((e) => e.toString()).join(', ') : '';
  final out = <PromptBlock>[
    (title: "Mix", text: _str(mix), sub: artists.isEmpty ? null : "Artists: $artists"),
    for (final (i, b) in female.indexed)
      (title: female.length > 1 ? "Female char box ${i + 1}" : "Female char box", text: b.text, sub: null),
    for (final (i, b) in male.indexed)
      (title: male.length > 1 ? "Male box ${i + 1}" : "Male box", text: b.text, sub: null),
    if (male.isEmpty) (title: "Male box", text: _str(s['male']), sub: null),
    (title: "Body", text: _str(s['body']), sub: null),
    (title: "Face", text: _str(s['face']), sub: null),
    (title: "Sex acts", text: _str(s['sex_acts']), sub: null),
    (title: "Clothes", text: _str(s['clothes']), sub: null),
  ];
  return out.where((b) => b.text.isNotEmpty).toList();
}

/// Last few /prompt answers (swiping the panel up again does not refetch). Small and bounded.
final Map<String, Map> _cache = {};

Future<Map?> loadPromptInfo(BaseAsset asset) async {
  final key = asset.remoteId ?? asset.name;
  final hit = _cache[key];
  if (hit != null) {
    return hit;
  }
  final ref = assetRef(asset);
  final uri = Uri.parse('$kGalleryServer/prompt').replace(
    queryParameters: {if (ref['immich_id'] != null) 'immich_id': ref['immich_id'], 'n': ref['name']},
  );
  final res = await http.get(uri).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) {
    return null;
  }
  final info = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
  if (_cache.length >= 30) {
    _cache.remove(_cache.keys.first);
  }
  _cache[key] = info;
  return info;
}

/// Section title + Copy + text that folds to 4 lines when long.
class PromptSectionBlock extends StatefulWidget {
  const PromptSectionBlock({super.key, required this.block, required this.toast});

  final PromptBlock block;
  final ToastService toast;

  @override
  State<PromptSectionBlock> createState() => _PromptSectionBlockState();
}

class _PromptSectionBlockState extends State<PromptSectionBlock> {
  static const _foldLines = 4;
  bool _open = false;

  bool _isLong(String text, TextStyle style, double width) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: _foldLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final long = tp.didExceedMaxLines;
    tp.dispose();
    return long;
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final style = TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.35);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
      child: LayoutBuilder(
        builder: (context, box) {
          final long = _isLong(b.text, style, box.maxWidth - 8);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  CopyTextButton(
                    key: ValueKey('info_copy_${b.title}'),
                    label: b.title,
                    text: b.text,
                    toast: widget.toast,
                    compact: true,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SelectableText(b.text, style: style, maxLines: long && !_open ? _foldLines : null),
              ),
              if (b.sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(b.sub!, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                ),
              if (long)
                TextButton(
                  key: ValueKey('info_fold_${b.title}'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? "Show less" : "Show more"),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Quick copy chips + the prompt sections + the Image block, for the Info panel.
class PromptInfoSections extends ConsumerStatefulWidget {
  const PromptInfoSections({super.key, required this.asset});

  final BaseAsset asset;

  @override
  ConsumerState<PromptInfoSections> createState() => _PromptInfoSectionsState();
}

class _PromptInfoSectionsState extends ConsumerState<PromptInfoSections> {
  Map? _info;
  bool _loading = true;
  String? _loadedFor;

  void _load() {
    final key = widget.asset.heroTag;
    if (_loadedFor == key) {
      return;
    }
    _loadedFor = key;
    _loading = true;
    _info = null;
    unawaited(
      loadPromptInfo(widget.asset)
          .then((info) {
            if (mounted && _loadedFor == key) {
              setState(() {
                _info = info;
                _loading = false;
              });
            }
          })
          .catchError((Object _) {
            if (mounted && _loadedFor == key) {
              setState(() => _loading = false);
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final toast = ref.read(toastServiceProvider);
    final info = _info;
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
    }
    if (info == null) {
      return const SizedBox.shrink();
    }
    final copies = promptCopies(info);
    final blocks = promptBlocks(info);
    String field(Object? v) => _str(v);
    final image = [
      ("File", widget.asset.name),
      ("Seed", field(info['seed'])),
      ("Mix id", field(info['mix_id'])),
      ("Character", field(info['character'])),
    ].where((e) => e.$2.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (copies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in copies)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CopyTextButton(key: ValueKey('info_quick_${c.$1}'), label: c.$1, text: c.$2, toast: toast),
                    ),
                ],
              ),
            ),
          ),
        for (final b in blocks) ...[const Divider(height: 1), PromptSectionBlock(block: b, toast: toast)],
        if (image.isNotEmpty) ...[
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text("Image", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          for (final (k, v) in image)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text(k, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor))),
                  Expanded(
                    child: Text(v, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  CopyTextButton(label: k, text: v, toast: toast, compact: true),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
