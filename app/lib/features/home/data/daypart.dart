import '../../../i18n/keys.g.dart';

/// The part of the day the greeting is written for.
///
/// A pure function of a [DateTime] so it is testable without touching the clock, and read with the
/// local getters because it is called with the phone's own time — a UTC reading would wish half
/// the world good morning at midnight.
enum Daypart {
  night(DiscoveryKeys.greetingNight, DiscoveryKeys.greetingSubNight),
  morning(DiscoveryKeys.greetingMorning, DiscoveryKeys.greetingSubMorning),
  afternoon(
    DiscoveryKeys.greetingAfternoon,
    DiscoveryKeys.greetingSubAfternoon,
  ),
  evening(DiscoveryKeys.greetingEvening, DiscoveryKeys.greetingSubEvening);

  const Daypart(this.greetingKey, this.subtitleKey);

  final String greetingKey;
  final String subtitleKey;

  /// Boundaries match the web client's so the two greet at the same hours: `< 5` night, `< 12`
  /// morning, `< 18` afternoon, otherwise evening.
  static Daypart at(DateTime now) {
    final hour = now.hour;
    if (hour < 5) return Daypart.night;
    if (hour < 12) return Daypart.morning;
    if (hour < 18) return Daypart.afternoon;
    return Daypart.evening;
  }
}
