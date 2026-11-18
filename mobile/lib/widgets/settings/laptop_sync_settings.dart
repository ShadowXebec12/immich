// Custom fork: Settings > Laptop sync.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/services/laptop_sync.service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LaptopSyncSettings extends ConsumerStatefulWidget {
  const LaptopSyncSettings({super.key});

  @override
  ConsumerState<LaptopSyncSettings> createState() => _LaptopSyncSettingsState();
}

class _LaptopSyncSettingsState extends ConsumerState<LaptopSyncSettings> {
  late final _controller = TextEditingController(text: ref.read(appConfigProvider).laptopSync.serverUrl);
  String _status = '';
  bool _isError = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Working...';
      _isError = false;
    });
    try {
      final message = await action();
      if (mounted) {
        setState(() => _status = message);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '$error';
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _describe(LaptopSyncOutcome outcome) => switch (outcome) {
    LaptopSyncOutcome.notConfigured => 'Enter the laptop address first',
    LaptopSyncOutcome.inSync => 'Already up to date',
    LaptopSyncOutcome.sentToLaptop => 'Saved this phone\'s data to the laptop',
    LaptopSyncOutcome.restoredFromLaptop => 'Restored data from the laptop',
  };

  Future<String> _connect() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      await ref.read(settingsProvider).write(.laptopSyncServerUrl, '');
      return 'Laptop sync is off';
    }
    final count = await ref.read(laptopSyncApiRepositoryProvider).health(url);
    await ref.read(settingsProvider).write(.laptopSyncServerUrl, url);
    final outcome = await ref.read(laptopSyncServiceProvider).sync();
    return 'Connected ($count items on the laptop). ${_describe(outcome)}';
  }

  Future<String> _sync(LaptopSyncForce force) async =>
      _describe(await ref.read(laptopSyncServiceProvider).sync(force: force));

  Future<String> _export() async {
    final bundle = await ref.read(laptopSyncServiceProvider).exportBundle();
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/immich-custom-settings.json');
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert(bundle));
    await Share.shareXFiles([XFile(file.path)]);
    return 'Export file created';
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(appConfigProvider.select((config) => config.laptopSync));
    final connected = sync.serverUrl.isNotEmpty;

    Widget button(String label, IconData icon, Key key, VoidCallback? onPressed) => Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: OutlinedButton.icon(
        key: key,
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Folders, sort orders and the settings of this app are stored on your laptop, so nothing is lost '
          'if the app is deleted. The phone keeps a copy for when the laptop is not reachable.',
          style: context.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('laptop_sync_url'),
          controller: _controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Laptop address',
            hintText: 'http://192.168.1.4:8791',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          children: [
            button('Save and connect', Icons.link_rounded, const Key('laptop_sync_connect'), () => _run(_connect)),
            if (connected)
              button('Sync now', Icons.sync_rounded, const Key('laptop_sync_now'), () => _run(() => _sync(.none))),
            if (connected)
              button(
                'Restore from laptop',
                Icons.download_rounded,
                const Key('laptop_sync_restore'),
                () => _run(() => _sync(.restoreFromLaptop)),
              ),
            if (connected)
              button(
                'Send this phone to laptop',
                Icons.upload_rounded,
                const Key('laptop_sync_send'),
                () => _run(() => _sync(.sendToLaptop)),
              ),
            button('Export to a file', Icons.ios_share_rounded, const Key('laptop_sync_export'), () => _run(_export)),
          ],
        ),
        const SizedBox(height: 8),
        if (_status.isNotEmpty)
          Text(
            _status,
            key: const Key('laptop_sync_status'),
            style: context.textTheme.bodyMedium?.copyWith(color: _isError ? context.colorScheme.error : null),
          ),
        const SizedBox(height: 8),
        Text(
          connected
              ? (sync.settingsStamp.isEmpty ? 'Not synced yet' : 'Last change synced: ${sync.settingsStamp}')
              : 'Not connected',
          style: context.textTheme.bodySmall,
        ),
      ],
    );
  }
}
