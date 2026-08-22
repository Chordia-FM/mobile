/// A playhead or track length as `m:ss`, widening to `h:mm:ss` only when there are hours to show.
///
/// Not localised, and deliberately: every locale Chordia ships writes a running time this way, and
/// an ICU message would put the colon-separated figure at the mercy of a translator's line. A
/// negative value clamps to zero, which is what a scrubber dragged past the start produces.
String formatPlaybackTime(Duration duration) {
  final total = duration.isNegative ? 0 : duration.inSeconds;
  final seconds = (total % 60).toString().padLeft(2, '0');
  final minutes = (total ~/ 60) % 60;
  final hours = total ~/ 3600;
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}
