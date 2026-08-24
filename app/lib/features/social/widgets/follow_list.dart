import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../catalog/widgets/catalog_state.dart';
import 'person_row.dart';
import 'profile_reads.dart';
import 'profile_wall.dart';

/// Who follows a listener, or who they follow.
///
/// One widget for both directions, because they are two tabs of the same panel rather than two
/// pages — two files that must be edited in lockstep is how one of them ends up a version behind.
///
/// Paged explicitly with a button rather than an infinite-scroll sentinel: this list lives inside
/// the profile's own scroll view, and a sentinel that loads on reaching the bottom fights the page
/// for the reader's gesture.
class FollowList extends ConsumerStatefulWidget {
  const FollowList({
    required this.handle,
    required this.followers,
    required this.own,
    super.key,
  });

  final String handle;

  /// Followers when true, following when false.
  final bool followers;

  /// Whether this profile is the viewer's own — picks the empty-state copy.
  final bool own;

  @override
  ConsumerState<FollowList> createState() => _FollowListState();
}

class _FollowListState extends ConsumerState<FollowList> {
  /// Pages already in hand, frozen at the moment "Load more" was pressed.
  ///
  /// The total rides along because the next offset is a new provider key: its value is absent
  /// until that page lands, and without a remembered total the count line would blink to nothing
  /// mid-page.
  var _rows = const <FollowUser>[];
  var _total = 0;
  var _offset = 0;

  @override
  void didUpdateWidget(FollowList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching direction or person is a different list, not more of this one. Without this the
    // followers already loaded would have somebody's *following* appended to them.
    if (oldWidget.handle != widget.handle ||
        oldWidget.followers != widget.followers) {
      _rows = const [];
      _total = 0;
      _offset = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final page = ref.watch(
      followPageProvider((
        handle: widget.handle,
        followers: widget.followers,
        offset: _offset,
      )),
    );

    final fresh = page.value;
    final rows = fresh == null ? _rows : [..._rows, ...fresh.items];
    final total = fresh?.total ?? _total;
    final next = fresh?.nextOffset;

    // A 404 is the visibility gate, NOT a missing person: the Hub answers "not visible to you" and
    // "no such handle" identically so neither can be probed. So this says withheld, never
    // not-found.
    final error = page.error;
    if (error is ApiException && error.isNotFound) {
      return ProfileWall(
        title: t(SocialKeys.profileHiddenTitle),
        description: t(SocialKeys.profileHiddenDescription, {
          'name': '@${widget.handle}',
        }),
      );
    }
    if (page.hasError && rows.isEmpty) {
      return CatalogError(
        title: t(SocialKeys.profileLoadError),
        error: error,
        onRetry: () => ref.invalidate(followPageProvider),
      );
    }
    // Only the FIRST page gets the loading line. A later page is pending too — a new offset is a
    // new provider key — and swapping the loaded list out for this would be a whole-panel flash.
    if (page.isLoading && rows.isEmpty) {
      return CatalogEmpty(message: t(CommonKeys.stateLoading));
    }
    if (rows.isEmpty) {
      return CatalogEmpty(
        message: t(
          widget.followers
              ? (widget.own
                    ? SocialKeys.followersEmptyOwn
                    : SocialKeys.followersEmpty)
              : (widget.own
                    ? SocialKeys.followingEmptyOwn
                    : SocialKeys.followingEmpty),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            t(
              widget.followers
                  ? SocialKeys.followersCount
                  : SocialKeys.followingCount,
              {'count': total},
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final row in rows)
          PersonRow(
            user: row.user,
            tie: row.isFriend ? FriendTie.friends : FriendTie.none,
          ),
        if (next != null || page.isLoading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: OutlinedButton(
                onPressed: page.isLoading || next == null
                    ? null
                    : () => setState(() {
                        _rows = rows;
                        _total = total;
                        _offset = next;
                      }),
                child: Text(
                  t(
                    page.isLoading
                        ? CommonKeys.stateLoading
                        : SocialKeys.profileLoadMore,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
