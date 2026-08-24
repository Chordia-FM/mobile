import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/surface.dart';
import '../../widgets/tokens.dart';
import 'nav_tabs.dart';

/// The four tabs, drawn the way `components/app/MobileTabBar.tsx` draws them.
///
/// Not Material's [NavigationBar]. That widget arrives with an indicator pill behind the selected
/// icon, its own 80px height and its own ink ripple, and the web's bar has none of the three: the
/// selected tab is `text-primary` on icon *and* label, on the same background as the other three,
/// separated from the content only by a hairline. Wearing this app's colours over Material's shape
/// is exactly the complaint that this file exists to answer.
///
/// Every number below is from that component:
///
/// - the bar is `h-[calc(var(--tabbar-h)+var(--safe-b))] pb-(--safe-b)` — [barHeight] of touch
///   target with the home-indicator inset padded *below* it, so the icons never sit under the
///   gesture bar;
/// - `bg-(--surface-strong)` with `border-border border-t`;
/// - `grid grid-cols-4 items-stretch` — four equal columns, each filling the full height, so the
///   tap target is the whole column and not just the glyph;
/// - each item is `flex-col items-center justify-center gap-0.5 rounded-lg px-1 pt-1`;
/// - the icon is `size-5` (20px), the label `text-[0.6875rem] font-medium` (11px, weight 500);
/// - inactive is `text-muted-foreground`, active is `text-primary` — the accent, so this bar moves
///   with the account's colour like everything else.
class MobileTabBar extends ConsumerWidget {
  const MobileTabBar({
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final int currentIndex;
  final void Function(int index) onSelected;

  /// `--tabbar-h: 3.5rem`.
  static const double barHeight = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final surfaces = context.surfaces;
    // `env(safe-area-inset-bottom)`. Read from the view padding rather than the padding, because a
    // `Scaffold` that has already consumed it would report zero and drop the bar onto the gesture
    // bar — which is the shape this inset exists to prevent.
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaces.surfaceStrong,
        border: Border(top: BorderSide(color: surfaces.border)),
      ),
      child: SizedBox(
        height: barHeight + inset,
        child: Padding(
          padding: EdgeInsets.only(bottom: inset),
          // The press fill is an `InkWell`, which needs a `Material` above it. A transparent one,
          // because the background is already painted below: without this the bar only works where
          // a `Scaffold` happens to supply the ancestor, and it is a widget that should not care.
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              children: [
                for (final (index, tab) in NavTab.values.indexed)
                  Expanded(
                    child: _TabItem(
                      tab: tab,
                      label: t(tab.labelKey),
                      selected: index == currentIndex,
                      onTap: () => onSelected(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final NavTab tab;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The accent moves with the account; the muted role does not (the web fixes it in `:root`,
    // outside `.accent-scope`), so it comes off the colour scheme rather than the surface set.
    final colour = selected
        ? context.surfaces.accent
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      child: PressFill(
        onTap: onTap,
        borderRadius: ChordiaRadius.lgAll,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? tab.selectedIcon : tab.icon,
                size: 20,
                color: colour,
                semanticLabel: null,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Fixed rather than scaled off the text theme: this is the one place the web pins
                // an exact size, and a label that grows here pushes the icon out of a 56px bar.
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
