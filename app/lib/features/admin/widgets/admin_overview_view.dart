import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/art/art_cache.dart';
import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../../widgets/cover_art.dart';
import '../../catalog/widgets/catalog_state.dart';
import '../data/admin_providers.dart';
import 'admin_widgets.dart';

/// The windows the overview can be read over, in days. `365` renders as "1y".
const _windows = [7, 30, 90, 365];

/// Hub-wide numbers: who is listening, who is signed up, and what is in the catalog.
class AdminOverviewView extends ConsumerStatefulWidget {
  const AdminOverviewView({super.key});

  @override
  ConsumerState<AdminOverviewView> createState() => _AdminOverviewViewState();
}

class _AdminOverviewViewState extends ConsumerState<AdminOverviewView> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final overview = ref.watch(adminOverviewProvider(_days));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminOverviewProvider(_days));
        await ref.read(adminOverviewProvider(_days).future);
      },
      child: CatalogBody<AdminOverview>(
        value: overview,
        errorTitle: t(AdminKeys.overviewLoadFailed),
        onRetry: () => ref.invalidate(adminOverviewProvider(_days)),
        skeleton: const _OverviewSkeleton(),
        builder: (context, value) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            AdminSection(
              title: t(AdminKeys.overviewWindow),
              description: t(AdminKeys.overviewInWindow, {'days': _days}),
              trailing: DropdownButton<int>(
                value: _days,
                onChanged: (days) =>
                    days == null ? null : setState(() => _days = days),
                items: [
                  for (final days in _windows)
                    DropdownMenuItem(
                      value: days,
                      child: Text(
                        days == 365
                            ? t(AdminKeys.overviewYear)
                            : t(AdminKeys.overviewDays, {'count': days}),
                      ),
                    ),
                ],
              ),
            ),
            _Activity(activity: value.activity, series: value.playsSeries),
            _People(people: value.people),
            _Catalog(catalog: value.catalog),
            _TopList(
              title: t(AdminKeys.overviewTopArtists),
              entities: value.topArtists,
              circular: true,
            ),
            _TopList(
              title: t(AdminKeys.overviewTopAlbums),
              entities: value.topAlbums,
            ),
            _TopList(
              title: t(AdminKeys.overviewTopTracks),
              entities: value.topTracks,
            ),
          ],
        ),
      ),
    );
  }
}

class _Activity extends ConsumerWidget {
  const _Activity({required this.activity, required this.series});

  final AdminActivity activity;
  final List<AdminDayPoint> series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;

    // The busiest day is derived here rather than asked for: the series is already on the wire,
    // and a second endpoint for a max over thirty rows would be a request to compute nothing.
    AdminDayPoint? busiest;
    for (final point in series) {
      if (busiest == null || point.plays > busiest.plays) busiest = point;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSection(title: t(AdminKeys.overviewActivity)),
        AdminStatGrid(
          children: [
            AdminStat(
              label: t(AdminKeys.overviewPlays),
              value: formatAdminCount(activity.playsToday, locale),
              caption: t(AdminKeys.overviewDaily),
            ),
            AdminStat(
              label: t(AdminKeys.overviewPlaysWindow),
              value: formatAdminCount(activity.plays30d, locale),
              caption: t(AdminKeys.overviewDauWau, {
                'dau': activity.dau,
                'wau': activity.wau,
              }),
            ),
            AdminStat(
              label: t(AdminKeys.overviewActiveListeners),
              value: formatAdminCount(activity.mau, locale),
              caption: t(AdminKeys.overviewMonthly),
            ),
            AdminStat(
              label: t(AdminKeys.overviewListeningHours),
              value: t(AdminKeys.overviewHoursValue, {
                'hours': formatAdminCount(
                  listeningHours(activity.msPlayed30d),
                  locale,
                ),
              }),
              caption: t(AdminKeys.overviewListeningTime),
            ),
          ],
        ),
        if (busiest == null || busiest.plays == 0)
          CatalogEmpty(message: t(AdminKeys.overviewNoPlays))
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              t(AdminKeys.overviewBusiestDay, {'day': busiest.day}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _People extends ConsumerWidget {
  const _People({required this.people});

  final AdminPeople people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSection(title: t(AdminKeys.overviewPeople)),
        AdminStatGrid(
          children: [
            AdminStat(
              label: t(AdminKeys.overviewAccountsTotal),
              value: formatAdminCount(people.total, locale),
              caption: t(AdminKeys.overviewNewThisMonth, {
                'count': people.new30d,
              }),
            ),
            AdminStat(
              label: t(AdminKeys.overviewSignupsTotal),
              value: formatAdminCount(people.new7d, locale),
              caption: t(AdminKeys.overviewAccountsGained),
            ),
            AdminStat(
              label: t(AdminKeys.overviewCoverageVerified),
              value: formatAdminCount(people.verified, locale),
              caption: t(AdminKeys.overviewAccountHealth),
            ),
            AdminStat(
              label: t(AdminKeys.overviewCoverage2fa),
              value: formatAdminCount(people.withTotp, locale),
              caption: t(AdminKeys.overviewWithTotp, {
                'count': people.withTotp,
              }),
            ),
            AdminStat(
              label: t(AdminKeys.overviewModeration),
              value: formatAdminCount(people.suspended, locale),
            ),
            AdminStat(
              label: t(AdminKeys.usersAdminBadge),
              value: formatAdminCount(people.admins, locale),
              caption: t(AdminKeys.overviewAdminCount, {
                'count': people.admins,
              }),
            ),
          ],
        ),
      ],
    );
  }
}

class _Catalog extends ConsumerWidget {
  const _Catalog({required this.catalog});

  final AdminCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSection(title: t(AdminKeys.tabsContent)),
        AdminStatGrid(
          children: [
            AdminStat(
              label: t(AdminKeys.overviewArtists),
              value: formatAdminCount(catalog.artists, locale),
              caption: t(AdminKeys.overviewAlbumsTracks, {
                'albums': formatAdminCount(catalog.albums, locale),
                'tracks': formatAdminCount(catalog.tracks, locale),
              }),
            ),
            AdminStat(
              label: t(AdminKeys.overviewServers),
              value: '${catalog.serversOnline}/${catalog.serversTotal}',
              caption: t(AdminKeys.overviewLibrariesCount, {
                'count': catalog.libraries,
              }),
            ),
            AdminStat(
              label: t(AdminKeys.overviewPlaylists),
              value: formatAdminCount(catalog.playlists, locale),
              caption: t(AdminKeys.overviewLabelsCount, {
                'count': catalog.labels,
              }),
            ),
          ],
        ),
      ],
    );
  }
}

class _TopList extends ConsumerWidget {
  const _TopList({
    required this.title,
    required this.entities,
    this.circular = false,
  });

  final String title;
  final List<AdminTopEntity> entities;
  final bool circular;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSection(title: title),
        if (entities.isEmpty)
          CatalogEmpty(message: t(AdminKeys.overviewNoData))
        else
          for (final entity in entities)
            ListTile(
              dense: true,
              leading: CoverArt(
                sha256: artHashOf(entity.imageUrl),
                size: 40,
                shape: circular ? BoxShape.circle : BoxShape.rectangle,
                fallbackIcon: circular
                    ? Icons.person_rounded
                    : Icons.album_rounded,
              ),
              title: Text(
                entity.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: entity.subtitle == null
                  ? null
                  : Text(
                      entity.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: Text(formatAdminCount(entity.plays, locale)),
            ),
      ],
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const SkeletonBox(width: 160, height: 20),
      const SizedBox(height: 16),
      for (var row = 0; row < 4; row++) ...[
        const Row(
          children: [
            Expanded(child: SkeletonBox(height: 84)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 84)),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ],
  );
}
