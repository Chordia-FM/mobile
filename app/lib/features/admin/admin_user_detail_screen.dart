import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import '../catalog/widgets/catalog_state.dart';
import 'data/admin_providers.dart';
import 'widgets/admin_audit_view.dart';
import 'widgets/admin_widgets.dart';

/// One account, in full: what it is, what it owns, where it is signed in, and what has been done
/// to it.
///
/// Read-only. Suspend, delete, badge and plan edits stay on the desktop clients — they are
/// consequential, hard to undo, and a phone is the wrong place to be sure.
class AdminUserDetailScreen extends ConsumerWidget {
  const AdminUserDetailScreen({required this.userId, super.key});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final profile = ref.watch(adminUserProfileProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(profile.value?.user.displayName ?? t(AdminKeys.usersTitle)),
      ),
      body: CatalogBody<AdminUserProfile>(
        value: profile,
        errorTitle: t(AdminKeys.userDetailLoadFailed),
        onRetry: () => ref.invalidate(adminUserProfileProvider(userId)),
        skeleton: const CatalogDetailSkeleton(circularArt: true),
        builder: (context, value) => _Loaded(profile: value),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.profile});

  final AdminUserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final theme = Theme.of(context);
    final user = profile.user;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CoverArt(
                sha256: artHashOf(user.avatarUrl),
                size: 72,
                shape: BoxShape.circle,
                fallbackIcon: Icons.person_rounded,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${user.handle}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email ?? t(AdminKeys.usersNoEmail),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (user.suspended) ...[
                      const SizedBox(height: 6),
                      Text(
                        user.suspendedReason == null
                            ? t(AdminKeys.usersSuspendedBadge)
                            : '${t(AdminKeys.usersSuspendedBadge)}: '
                                  '${user.suspendedReason}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        AdminStatGrid(
          children: [
            AdminStat(
              label: t(AdminKeys.userDetailPlays),
              value: formatAdminCount(user.plays, locale),
              caption: t(AdminKeys.userDetailActiveDays, {
                'count': profile.activeDays,
              }),
            ),
            AdminStat(
              label: t(AdminKeys.userDetailListeningTime),
              value: t(AdminKeys.overviewHoursValue, {
                'hours': formatAdminCount(
                  listeningHours(profile.msPlayed),
                  locale,
                ),
              }),
            ),
            AdminStat(
              label: t(AdminKeys.userDetailLibrariesPlaylists),
              value: '${profile.libraries.length} / ${profile.playlists}',
            ),
            AdminStat(
              label: t(AdminKeys.userDetailJoined),
              value: formatAdminDay(user.createdAtMs, locale),
              caption: user.lastSeenMs == null
                  ? t(AdminKeys.usersNever)
                  : t(AdminKeys.userDetailLastSeen, {
                      'when': formatAdminDay(user.lastSeenMs!, locale),
                    }),
            ),
            AdminStat(
              label: t(AdminKeys.usersVerified),
              value: user.emailVerified
                  ? t(CommonKeys.stateOn)
                  : t(CommonKeys.stateOff),
            ),
            AdminStat(
              label: t(AdminKeys.overviewCoverage2fa),
              value: user.totpEnabled
                  ? t(CommonKeys.stateOn)
                  : t(CommonKeys.stateOff),
            ),
          ],
        ),
        AdminSection(title: t(AdminKeys.userDetailLibraries)),
        if (profile.libraries.isEmpty)
          CatalogEmpty(message: t(AdminKeys.userDetailNoLibraries))
        else
          for (final library in profile.libraries)
            ListTile(
              dense: true,
              leading: Icon(
                library.online
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                color: library.online
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(library.name),
              subtitle: Text(
                '${formatAdminCount(library.trackCount, locale)} · '
                '${library.online ? t(AdminKeys.userDetailOnline) : t(AdminKeys.userDetailOffline)}',
              ),
            ),
        AdminSection(title: t(AdminKeys.userDetailSessions)),
        if (profile.sessions.isEmpty)
          CatalogEmpty(message: t(AdminKeys.userDetailNoSessions))
        else
          for (final session in profile.sessions)
            ListTile(
              dense: true,
              leading: Icon(
                session.longLived
                    ? Icons.smartphone_rounded
                    : Icons.public_rounded,
              ),
              // The raw user agent, unparsed: turning it into "Chrome on macOS" is a guess, and an
              // operator chasing a suspicious session wants the actual header.
              title: Text(
                session.userAgent ?? t(AdminKeys.userDetailUnknownDevice),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                t(AdminKeys.userDetailSessionMeta, {
                  'started': formatAdminDay(session.createdAtMs, locale),
                  'used': formatAdminDay(session.lastUsedAtMs, locale),
                }),
              ),
              trailing: session.longLived
                  ? Text(t(AdminKeys.userDetailDevice))
                  : null,
            ),
        AdminSection(title: t(AdminKeys.userDetailHistory)),
        if (profile.recentAudit.isEmpty)
          CatalogEmpty(message: t(AdminKeys.userDetailNoHistory))
        else
          for (final entry in profile.recentAudit)
            AuditEntryTile(entry: entry, locale: locale),
      ],
    );
  }
}
