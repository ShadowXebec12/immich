import 'dart:async';

import 'package:immich_mobile/custom/offline_albums.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/custom/slideshow_queue.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/timeline.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/widgets/album/album_search_bar.widget.dart';
import 'package:immich_mobile/presentation/widgets/album/pending_uploads_banner.widget.dart';
import 'package:immich_mobile/custom/selection_actions.dart';
import 'package:immich_mobile/presentation/widgets/album/recent_albums.widget.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/remote_album_bottom_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/remote_album/album_option.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/album/album_search.provider.dart';
import 'package:immich_mobile/providers/infrastructure/album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/current_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/remote_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/remote_album_sliver_app_bar.dart';

@RoutePage()
class RemoteAlbumPage extends ConsumerStatefulWidget {
  final RemoteAlbum album;

  const RemoteAlbumPage({super.key, required this.album});

  @override
  ConsumerState<RemoteAlbumPage> createState() => _RemoteAlbumPageState();
}

class _RemoteAlbumPageState extends ConsumerState<RemoteAlbumPage> {
  late RemoteAlbum _album;
  @override
  void initState() {
    super.initState();
    _album = widget.album;
    // Custom fork: remember this album for the Recent albums menu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(recordRecentAlbum(ref, widget.album.id));
        // offline album: save photos added since the last save (skips ones already saved)
        unawaited(refreshAlbumOffline(ref, widget.album.id));
      }
    });
  }

  Future<void> addAssets(BuildContext context) async {
    final notifier = ref.read(remoteAlbumProvider.notifier);
    final albumAssets = await notifier.getAssets(_album.id);
    if (!context.mounted) {
      return;
    }

    final newAssets = await context.pushRoute<Set<BaseAsset>>(
      AssetSelectionTimelineRoute(lockedSelectionAssets: albumAssets.toSet()),
    );

    if (newAssets == null || newAssets.isEmpty) {
      return;
    }

    final added = await notifier.addAssetsToAlbum(_album.id, newAssets);
    if (!context.mounted) {
      return;
    }

    if (added > 0) {
      ImmichToast.show(
        context: context,
        msg: context.t.assets_added_to_album_count(count: added),
        toastType: ToastType.success,
      );
    }
  }

  Future<void> addUsers(BuildContext context) async {
    final newUsers = await context.pushRoute<List<String>>(UserSelectionRoute(album: _album));

    if (newUsers == null || newUsers.isEmpty) {
      return;
    }

    try {
      if (!context.mounted) {
        return;
      }

      await ref.read(remoteAlbumProvider.notifier).addUsers(_album.id, newUsers);
      ref.invalidate(remoteAlbumSharedUsersProvider(_album.id));
      if (!context.mounted) {
        return;
      }

      ImmichToast.show(
        context: context,
        msg: context.t.users_added_to_album_count(count: newUsers.length),
        toastType: ToastType.success,
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      ImmichToast.show(context: context, msg: "Failed to add users to album: $e", toastType: ToastType.error);
    }
  }

  Future<void> toggleAlbumOrder() async {
    await ref.read(remoteAlbumProvider.notifier).toggleAlbumOrder(_album.id);

    ref.invalidate(timelineServiceProvider);
  }

  // Custom fork: per-album sort by file name, stored on this phone
  Future<void> toggleNameSort() async {
    final ids = ref.read(appConfigProvider).album.nameSortIds;
    final next = ids.contains(_album.id) ? ids.where((id) => id != _album.id).toList() : [...ids, _album.id];
    await ref.read(settingsProvider).write(.albumNameSortIds, next);
  }

  Future<void> deleteAlbum(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.t.delete_album),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.t.album_delete_confirmation(album: _album.name)),
              const SizedBox(height: 8),
              Text(context.t.album_delete_confirmation_description),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.t.cancel)),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: Text(context.t.delete_album),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        if (!context.mounted) {
          return;
        }

        await ref.read(remoteAlbumProvider.notifier).deleteAlbum(_album.id);
        if (!context.mounted) {
          return;
        }

        ImmichToast.show(context: context, msg: context.t.album_deleted, toastType: ToastType.success);

        unawaited(context.pushRoute(const AlbumsRoute()));
      } catch (e) {
        if (!context.mounted) {
          return;
        }

        ImmichToast.show(
          context: context,
          msg: context.t.album_viewer_appbar_share_err_delete,
          toastType: ToastType.error,
        );
      }
    }
  }

  Future<void> showEditTitleAndDescription(BuildContext context) async {
    final result = await showDialog<_EditAlbumData?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _EditAlbumDialog(album: _album),
    );

    if (!context.mounted) {
      return;
    }

    if (result != null) {
      setState(() {
        _album = _album.copyWith(name: result.name, description: result.description ?? '');
      });
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  Future<void> showActivity(BuildContext context) async {
    unawaited(context.pushRoute(ActivitiesRoute(album: _album)));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isOwner = user != null ? user.id == _album.ownerId : false;
    // Custom fork: in-album search. null = search bar closed
    final isSearching = ref.watch(albumSearchQueryProvider(_album.id).select((query) => query != null));

    return ProviderScope(
      overrides: [
        timelineServiceProvider.overrideWith((ref) {
          final query = ref.watch(albumSearchQueryProvider(_album.id))?.trim() ?? '';
          final labels = ref.watch(albumSearchLabelsProvider(_album.id));
          final field = ref.watch(albumSearchFieldProvider(_album.id));
          final factory = ref.watch(timelineFactoryProvider);
          final byName = ref.watch(appConfigProvider.select((c) => c.album.nameSortIds.contains(_album.id)));
          // #5: Filters sheet (excludes, characters, mixes, model, dates, favorites, match any)
          final full = ref.watch(albumFilterProvider(_album.id)).withLabels(labels);
          if (full.needsFullFilter) {
            final hits = ref.watch(albumFilteredAssetsProvider(albumFilterKey(_album.id, full))).valueOrNull ?? const [];
            final q = query.toLowerCase();
            final shown = q.isEmpty ? hits : hits.where((a) => a.name.toLowerCase().contains(q)).toList();
            final service = factory.fromAssets(shown, TimelineOrigin.remoteAlbum);
            ref.onDispose(service.dispose);
            return service;
          }
          if (labels.isNotEmpty) {
            // Custom fork: label filter (PC gallery server) + the typed text as a file-name filter
            final hits = ref.watch(albumLabelAssetsProvider((_album.id, labels.join('')))).valueOrNull ?? const [];
            final q = query.toLowerCase();
            final shown = q.isEmpty ? hits : hits.where((a) => a.name.toLowerCase().contains(q)).toList();
            final service = factory.fromAssets(shown, TimelineOrigin.remoteAlbum);
            ref.onDispose(service.dispose);
            return service;
          }
          final timelineService = query.isNotEmpty
              ? factory.remoteAlbumSearch(albumId: _album.id, query: query, field: field)
              : byName
              ? factory.remoteAlbumByName(albumId: _album.id)
              : factory.remoteAlbum(albumId: _album.id);
          ref.onDispose(timelineService.dispose);
          return timelineService;
        }),
        currentRemoteAlbumScopedProvider.overrideWithValue(_album),
      ],
      child: Material(
        color: context.colorScheme.surface,
        child: Column(
          children: [
            if (isSearching) AlbumSearchBar(albumId: _album.id),
            OfflineProgressBar(albumId: _album.id),
            Expanded(
              key: const ValueKey('album_timeline'),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: isSearching,
                child: _buildTimeline(context, isOwner: isOwner, isSearching: isSearching),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, {required bool isOwner, required bool isSearching}) {
    // Search results are one flat, undated list (same setup as the search page)
    final hasQuery =
        ref.watch(albumSearchQueryProvider(_album.id).select((query) => (query ?? '').trim().isNotEmpty)) ||
        ref.watch(albumSearchLabelsProvider(_album.id).select((l) => l.isNotEmpty)) ||
        ref.watch(albumFilterProvider(_album.id).select((f) => f.hasExtras));
    final byName = ref.watch(appConfigProvider.select((c) => c.album.nameSortIds.contains(_album.id)));
    final flat = hasQuery || byName;

    return Timeline(
      groupBy: flat ? GroupAssetsBy.none : null,
      snapToMonth: !flat,
      withScrubber: !hasQuery,
      topSliverWidget: PendingUploadsBanner(albumId: _album.id),
      appBar: isSearching
          ? null
          : RemoteAlbumSliverAppBar(
              icon: Icons.photo_album_outlined,
              kebabMenu: _AlbumKebabMenu(
                album: _album,
                onDeleteAlbum: () => deleteAlbum(context),
                onAddUsers: () => addUsers(context),
                onAddPhotos: () => addAssets(context),
                onToggleAlbumOrder: () => toggleAlbumOrder(),
                onEditAlbum: () => showEditTitleAndDescription(context),
                onCreateSharedLink: () => unawaited(context.pushRoute(SharedLinkEditRoute(albumId: _album.id))),
                onShowOptions: () => context.pushRoute(AlbumOptionsRoute(album: _album)),
                onToggleNameSort: () => toggleNameSort(),
                isNameSort: byName,
                onToggleOffline: () => unawaited(toggleAlbumOffline(ref, _album.id, _album.name)),
                isOffline: ref.watch(appConfigProvider.select((c) => c.album.offlineIds.contains(_album.id))),
              ),
              onEditTitle: isOwner ? () => showEditTitleAndDescription(context) : null,
              onActivity: () => showActivity(context),
            ),
      bottomSheet: RemoteAlbumBottomSheet(album: _album),
    );
  }
}

class _EditAlbumData {
  final String name;
  final String? description;

  const _EditAlbumData({required this.name, this.description});
}

class _EditAlbumDialog extends ConsumerStatefulWidget {
  final RemoteAlbum album;

  const _EditAlbumDialog({required this.album});

  @override
  ConsumerState<_EditAlbumDialog> createState() => _EditAlbumDialogState();
}

class _EditAlbumDialogState extends ConsumerState<_EditAlbumDialog> {
  late final TextEditingController titleController;
  late final TextEditingController descriptionController;
  final formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.album.name);
    descriptionController = TextEditingController(
      text: widget.album.description.isEmpty ? '' : widget.album.description,
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (formKey.currentState?.validate() != true) {
      return;
    }

    try {
      final newTitle = titleController.text.trim();
      final newDescription = descriptionController.text.trim();

      await ref
          .read(remoteAlbumProvider.notifier)
          .updateAlbum(widget.album.id, name: newTitle, description: newDescription);
      if (!mounted) {
        return;
      }

      Navigator.of(
        context,
      ).pop(_EditAlbumData(name: newTitle, description: newDescription.isEmpty ? null : newDescription));
    } catch (e) {
      if (!mounted) {
        return;
      }

      ImmichToast.show(context: context, msg: context.t.errors.unable_to_update_album_info, toastType: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 550),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_outlined, color: context.colorScheme.primary, size: 24),
                    const SizedBox(width: 12),
                    Text(context.t.edit_album, style: context.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 24),

                // Album Name
                Text(
                  context.t.album_name.toUpperCase(),
                  style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: titleController,
                  maxLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    filled: true,
                    fillColor: context.colorScheme.surface,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return context.t.name_required;
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Description
                Text(
                  context.t.description.toUpperCase(),
                  style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: descriptionController,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    filled: true,
                    fillColor: context.colorScheme.surface,
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.of(context).pop(null), child: Text(context.t.cancel)),
                    const SizedBox(width: 12),
                    FilledButton(onPressed: _handleSave, child: Text(context.t.save)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumKebabMenu extends ConsumerWidget {
  final RemoteAlbum album;
  final VoidCallback? onDeleteAlbum;
  final VoidCallback? onAddUsers;
  final VoidCallback? onAddPhotos;
  final VoidCallback? onToggleAlbumOrder;
  final VoidCallback? onEditAlbum;
  final VoidCallback? onCreateSharedLink;
  final VoidCallback? onShowOptions;
  final VoidCallback? onToggleNameSort;
  final bool isNameSort;
  final VoidCallback? onToggleOffline;
  final bool isOffline;

  const _AlbumKebabMenu({
    this.onToggleNameSort,
    this.isNameSort = false,
    this.onToggleOffline,
    this.isOffline = false,
    required this.album,
    this.onDeleteAlbum,
    this.onAddUsers,
    this.onAddPhotos,
    this.onToggleAlbumOrder,
    this.onEditAlbum,
    this.onCreateSharedLink,
    this.onShowOptions,
  });

  double _calculateScrollProgress(FlexibleSpaceBarSettings? settings) {
    if (settings?.maxExtent == null || settings?.minExtent == null) {
      return 1.0;
    }

    final deltaExtent = settings!.maxExtent - settings.minExtent;
    if (deltaExtent <= 0.0) {
      return 1.0;
    }

    return (1.0 - (settings.currentExtent - settings.minExtent) / deltaExtent).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final scrollProgress = _calculateScrollProgress(settings);

    final iconColor = Color.lerp(Colors.white, context.primaryColor, scrollProgress);
    final iconShadows = [
      if (scrollProgress < 0.95)
        Shadow(offset: const Offset(0, 2), blurRadius: 5, color: Colors.black.withValues(alpha: 0.5))
      else
        const Shadow(offset: Offset(0, 2), blurRadius: 0, color: Colors.transparent),
    ];

    final user = ref.watch(currentUserProvider);
    final isOwner = user != null && user.id == album.ownerId;

    return FutureBuilder<bool>(
      future: ref
          .watch(remoteAlbumServiceProvider)
          .getUserRole(album.id, user?.id ?? '')
          .then((role) => role == AlbumUserRole.editor),
      builder: (context, snapshot) {
        final canAddPhotos = snapshot.data ?? false;

        return RemoteAlbumOption(
          iconColor: iconColor,
          iconShadows: iconShadows,
          onDeleteAlbum: isOwner ? onDeleteAlbum : null,
          onAddUsers: isOwner ? onAddUsers : null,
          onAddPhotos: isOwner || canAddPhotos ? onAddPhotos : null,
          onToggleAlbumOrder: isOwner ? onToggleAlbumOrder : null,
          onEditAlbum: isOwner ? onEditAlbum : null,
          onCreateSharedLink: isOwner ? onCreateSharedLink : null,
          onShowOptions: onShowOptions,
          onToggleNameSort: onToggleNameSort,
          isNameSort: isNameSort,
          onToggleOffline: onToggleOffline,
          isOffline: isOffline,
          extraItems: [RestoreSelectionMenuItem(albumId: album.id), ...slideshowQueueMenuItems(context, ref, album)],
        );
      },
    );
  }
}
