import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'accent_engine.dart';
import 'accent_palette.dart';

/// The live accent, published to the widget tree without repainting it.
///
/// This is the answer to the one performance question a moving accent asks. The colour changes as
/// often as every 150ms in Fade mode, and the naive wiring — rebuild `MaterialApp.theme` on each
/// tick — rebuilds every widget that ever called `Theme.of(context)`, which is nearly all of them,
/// seven times a second. The web spent two sessions removing always-painting elements for exactly
/// this reason (`docs/overhaul/01-perf.md`); mobile is not going to reintroduce it.
///
/// So the split is:
///
///   - The **theme** is built from `AccentConfig.surfaceAccent`, which is stable for as long as
///     the account's configuration is. Changing the accent on the desktop rebuilds the tree once,
///     which is correct and cheap. A cross-fade does not touch it at all.
///   - The **moving colour** lives here, behind an [InheritedNotifier]. A widget that wants it
///     calls [AccentScope.of] and becomes a dependent, so the tick rebuilds that element and
///     nothing above it. A widget that wants it without rebuilding its own subtree uses
///     [AccentBuilder], which keeps its `child` alive across ticks.
///
/// Widgets that only need a still accent should keep using `Theme.of(context).colorScheme.primary`
/// and cost nothing.
class AccentScope extends InheritedNotifier<ValueListenable<AccentFrame>> {
  const AccentScope({
    required ValueListenable<AccentFrame> frame,
    required super.child,
    super.key,
  }) : super(notifier: frame);

  /// The frame the app is currently painting, subscribing this widget to the next one.
  ///
  /// Falls back to a still default when no scope is above — a widget test that builds one screen
  /// gets the built-in accent rather than an assertion.
  static AccentFrame of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AccentScope>()
          ?.notifier
          ?.value ??
      _fallback;

  /// The frame's listenable, WITHOUT subscribing this widget to it.
  ///
  /// For a caller that would rather listen at a narrower point than its own element — which is
  /// what [AccentBuilder] does.
  static ValueListenable<AccentFrame> listenableOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AccentScope>();
    final scope = element?.widget as AccentScope?;
    return scope?.notifier ?? _stillFallback;
  }

  static final AccentFrame _fallback = AccentFrame(
    accent: builtinAccent,
    foreground: foregroundFor(builtinAccent),
  );

  /// A listenable that never fires, for a subtree with no scope above it.
  static final ValueListenable<AccentFrame> _stillFallback = ValueNotifier(
    _fallback,
  );
}

/// Rebuilds only its builder when the accent moves, keeping [child] across ticks.
///
/// Use this for the expensive case — an accented element with real content under it. For a leaf,
/// [AccentScope.of] is simpler and just as cheap.
class AccentBuilder extends StatelessWidget {
  const AccentBuilder({required this.builder, super.key, this.child});

  final ValueWidgetBuilder<AccentFrame> builder;

  /// Anything under the accented element that does not itself depend on the colour. Built once.
  final Widget? child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AccentFrame>(
    valueListenable: AccentScope.listenableOf(context),
    builder: builder,
    child: child,
  );
}
