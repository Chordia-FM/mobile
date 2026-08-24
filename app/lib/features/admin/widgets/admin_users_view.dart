import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/tokens.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../../catalog/widgets/list_row.dart';
import '../admin_routes.dart';
import '../data/admin_models.dart';
import '../data/admin_providers.dart';
import 'admin_widgets.dart';

/// The account roster: search, filter, sort, and open one.
class AdminUsersView extends ConsumerStatefulWidget {
  const AdminUsersView({super.key});

  @override
  ConsumerState<AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends ConsumerState<AdminUsersView> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _apply(AdminUserQuery query) => unawaited(
    ref.read(adminUsersControllerProvider.notifier).applyFilters(query),
  );

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final users = ref.watch(adminUsersControllerProvider);
    final query = users.value?.query ?? const AdminUserQuery();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 350),
                () => _apply(query.copyWith(search: value.trim())),
              );
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
              hintText: t(AdminKeys.usersSearchPlaceholder),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _FilterMenu(
                  label: t(AdminKeys.usersStatusLabel),
                  value: query.status,
                  options: [
                    ('all', t(AdminKeys.usersStatusAll)),
                    ('active', t(AdminKeys.usersStatusActive)),
                    ('suspended', t(AdminKeys.usersStatusSuspended)),
                  ],
                  onChanged: (status) => _apply(query.copyWith(status: status)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FilterMenu(
                  label: t(AdminKeys.usersSortLabel),
                  value: query.sort,
                  options: [
                    ('created', t(AdminKeys.usersSortCreated)),
                    ('handle', t(AdminKeys.usersSortHandle)),
                    ('plays', t(AdminKeys.usersSortPlays)),
                    ('last_seen', t(AdminKeys.usersSortLastSeen)),
                    ('libraries', t(AdminKeys.usersSortLibraries)),
                  ],
                  onChanged: (sort) => _apply(query.copyWith(sort: sort)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: CatalogBody<AdminUsersState>(
            value: users,
            errorTitle: t(AdminKeys.usersLoadFailed),
            onRetry: () => ref.invalidate(adminUsersControllerProvider),
            skeleton: const _RosterSkeleton(),
            builder: (context, value) => value.rows.isEmpty
                ? CatalogEmpty(message: t(AdminKeys.usersEmpty))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    // One extra row for the footer, which is either "load more" or the total.
                    itemCount: value.rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == value.rows.length) {
                        return _Footer(state: value, locale: locale);
                      }
                      return _UserRow(user: value.rows[index], locale: locale);
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  // A plain `DropdownButton` rather than the form field: the form field takes an *initial* value
  // and would not follow a filter changed from anywhere else, which is the class of bug where a
  // control shows one thing and the list shows another.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        DropdownButton<String>(
          value: value,
          isExpanded: true,
          onChanged: (picked) => picked == null ? null : onChanged(picked),
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option.$1,
                child: Text(option.$2, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ],
    );
  }
}

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user, required this.locale});

  final AdminUserDetail user;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final theme = Theme.of(context);
    return ListRow(
      onTap: () => context.goToAdminUser(user.id),
      leading: CoverArt(
        sha256: artHashOf(user.avatarUrl),
        size: 44,
        shape: BoxShape.circle,
        fallbackIcon: PhosphorIconsFill.user,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (user.isAdmin) ...[
            const SizedBox(width: 6),
            _Tag(label: t(AdminKeys.usersAdminBadge)),
          ],
          if (user.suspended) ...[
            const SizedBox(width: 6),
            _Tag(
              label: t(AdminKeys.usersSuspendedBadge),
              color: theme.colorScheme.errorContainer,
              onColor: theme.colorScheme.onErrorContainer,
            ),
          ],
        ],
      ),
      subtitle: Text(
        '@${user.handle} · ${t(AdminKeys.usersMetaLine, {'libraries': user.libraries, 'plays': formatAdminCount(user.plays, locale), 'seen': user.lastSeenMs == null ? t(AdminKeys.usersNever) : formatAdminDay(user.lastSeenMs!, locale)})}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(PhosphorIconsRegular.caretRight),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.color, this.onColor});

  final String label;
  final Color? color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? scheme.secondaryContainer,
        borderRadius: ChordiaRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: onColor ?? scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state, required this.locale});

  final AdminUsersState state;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          Text(
            '${formatAdminCount(state.rows.length, locale)} / '
            '${formatAdminCount(state.total, locale)} '
            '${t(AdminKeys.usersMatching)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (state.hasMore) ...[
            const SizedBox(height: 8),
            if (state.loadingMore)
              const CircularProgressIndicator()
            else
              OutlinedButton(
                onPressed: () =>
                    ref.read(adminUsersControllerProvider.notifier).loadMore(),
                child: Text(t(AdminKeys.usersLoadMore)),
              ),
          ],
        ],
      ),
    );
  }
}

class _RosterSkeleton extends StatelessWidget {
  const _RosterSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      for (var i = 0; i < 8; i++) ...[
        Row(
          children: [
            const SkeletonBox(width: 44, height: 44, shape: BoxShape.circle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 180 - (i % 3) * 30, height: 14),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 220, height: 11),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    ],
  );
}
