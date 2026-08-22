/// Semantic-version precedence, as the update check needs it.
///
/// Hand-written rather than pulled in: the whole of the spec that matters here is precedence, and
/// this app's own version string is not a hypothetical — the `dev` flavour appends
/// `versionNameSuffix = "-dev"`, so a running build genuinely can be `0.2.0-dev`. Getting the
/// pre-release rule wrong would either nag every developer on every launch or hide a real release
/// from everybody on a pre-release build.
library;

/// A parsed `MAJOR.MINOR.PATCH[-prerelease][+build]`.
///
/// Lenient about the shape on the way in — a leading `v`, or a missing patch — because the two
/// strings compared here come from different places (a GitHub tag and Android's `versionName`) and
/// a version that fails to parse silently means "never offer an update".
class SemVer implements Comparable<SemVer> {
  const SemVer(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const [],
  });

  final int major;
  final int minor;
  final int patch;

  /// The dot-separated identifiers after `-`, empty for a final release.
  ///
  /// Build metadata (`+abc`) is deliberately absent: the spec says it takes no part in precedence,
  /// and keeping it on the object would invite a `==` that disagrees with [compareTo].
  final List<String> preRelease;

  /// Parses [input], or returns null if it is not a version at all.
  static SemVer? tryParse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);

    // Build metadata first: it is ignored entirely, and stripping it here keeps it out of the
    // pre-release split below, where `1.0.0-rc.1+build.5` would otherwise end in `1+build.5`.
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);

    final dash = s.indexOf('-');
    final core = dash >= 0 ? s.substring(0, dash) : s;
    final pre = dash >= 0 ? s.substring(dash + 1) : '';
    if (dash >= 0 && pre.isEmpty) return null;

    final parts = core.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      // Not `int.parse` with a fallback: `1.x.0` must fail to parse rather than become `1.0.0`,
      // which would compare as a real version and could suppress a genuine update.
      if (n == null || n < 0) return null;
      numbers.add(n);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }

    final identifiers = pre.isEmpty ? const <String>[] : pre.split('.');
    if (identifiers.any((id) => id.isEmpty)) return null;

    return SemVer(numbers[0], numbers[1], numbers[2], preRelease: identifiers);
  }

  @override
  int compareTo(SemVer other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    return _comparePreRelease(preRelease, other.preRelease);
  }

  bool operator >(SemVer other) => compareTo(other) > 0;

  bool operator <(SemVer other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is SemVer && compareTo(other) == 0 && other.runtimeType == SemVer;

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, Object.hashAll(preRelease));

  @override
  String toString() {
    final core = '$major.$minor.$patch';
    return preRelease.isEmpty ? core : '$core-${preRelease.join('.')}';
  }
}

/// Precedence between two pre-release lists.
///
/// The rules are the fiddly part of the spec, and each one exists for a reason worth keeping in
/// sight: a version with a pre-release ranks below the same version without one (`1.0.0-rc.1` is
/// not `1.0.0`); numeric identifiers compare numerically so `rc.9` precedes `rc.10`; a numeric
/// identifier always ranks below an alphanumeric one; and where one list runs out first, the
/// shorter ranks lower (`alpha` precedes `alpha.1`).
int _comparePreRelease(List<String> a, List<String> b) {
  if (a.isEmpty && b.isEmpty) return 0;
  if (a.isEmpty) return 1;
  if (b.isEmpty) return -1;

  for (var i = 0; i < a.length && i < b.length; i++) {
    final left = int.tryParse(a[i]);
    final right = int.tryParse(b[i]);
    final result = switch ((left, right)) {
      (final int l, final int r) => l.compareTo(r),
      (int(), null) => -1,
      (null, int()) => 1,
      _ => a[i].compareTo(b[i]),
    };
    if (result != 0) return result;
  }
  return a.length.compareTo(b.length);
}

/// Whether [candidate] is a version worth offering somebody running [current].
///
/// Anything unparseable on either side is "no". That is the safe direction: a phone that cannot
/// read its own version has no basis for telling its owner they are out of date, and a release feed
/// that is empty — which is what the Hub serves when GitHub is unreachable — must prompt nobody.
bool isNewer({required String candidate, required String current}) {
  final next = SemVer.tryParse(candidate);
  final now = SemVer.tryParse(current);
  if (next == null || now == null) return false;
  return next > now;
}
