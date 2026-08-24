import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// The `icon` column's default, and what an unknown value falls back to.
///
/// The same slug the web client writes, because one Hub serves both: a library given an icon on a
/// phone has to render on the desktop and vice versa, and the column stores the slug rather than
/// anything platform-shaped.
const defaultLibraryIcon = 'music-notes';

/// The marker an emoji icon carries, followed by the literal emoji.
///
/// Literal rather than a codepoint, matching the web client — the same string is what a font
/// renders when no vendored SVG exists for it.
const emojiIconPrefix = 'emoji:';

/// The curated set, keyed by the slug stored in `libraries.icon`.
///
/// Both halves come from the web client (`frontend/src/lib/library/icons.tsx`): the key is the
/// slug stored in the column, the value is the SAME Phosphor glyph that client draws for it, at
/// the fill weight its `LibraryIcon` defaults to. A name this build has never heard of falls back
/// to [defaultLibraryIcon] rather than to nothing, so an icon added by a newer client looks
/// ordinary here rather than broken.
const libraryIcons = <String, IconData>{
  'music-notes': PhosphorIconsFill.musicNotes,
  'vinyl-record': PhosphorIconsFill.vinylRecord,
  'disc': PhosphorIconsFill.disc,
  'guitar': PhosphorIconsFill.guitar,
  'piano': PhosphorIconsFill.pianoKeys,
  'microphone': PhosphorIconsFill.microphoneStage,
  'metronome': PhosphorIconsFill.metronome,
  'equalizer': PhosphorIconsFill.equalizer,
  'waveform': PhosphorIconsFill.waveform,
  'radio': PhosphorIconsFill.radio,
  'broadcast': PhosphorIconsFill.broadcast,
  'headphones': PhosphorIconsFill.headphones,
  'speaker': PhosphorIconsFill.speakerHigh,
  'playlist': PhosphorIconsFill.playlist,
  'star': PhosphorIconsFill.star,
  'heart': PhosphorIconsFill.heart,
  'fire': PhosphorIconsFill.fire,
  'sparkle': PhosphorIconsFill.sparkle,
  'crown': PhosphorIconsFill.crown,
  'trophy': PhosphorIconsFill.trophy,
  'diamond': PhosphorIconsFill.diamond,
  'folder': PhosphorIconsFill.folder,
  'archive': PhosphorIconsFill.archive,
  'bookmark': PhosphorIconsFill.bookmark,
  'lock': PhosphorIconsFill.lock,
  'users': PhosphorIconsFill.users,
  'house': PhosphorIconsFill.house,
  'globe': PhosphorIconsFill.globe,
  'ticket': PhosphorIconsFill.ticket,
  'confetti': PhosphorIconsFill.confetti,
  'campfire': PhosphorIconsFill.campfire,
  'moon': PhosphorIconsFill.moon,
  'sun': PhosphorIconsFill.sun,
  'waves': PhosphorIconsFill.waves,
  'mountains': PhosphorIconsFill.mountains,
  'tree': PhosphorIconsFill.tree,
  'coffee': PhosphorIconsFill.coffee,
  'car': PhosphorIconsFill.car,
  'airplane': PhosphorIconsFill.airplane,
  'barbell': PhosphorIconsFill.barbell,
  'books': PhosphorIconsFill.books,
  'film': PhosphorIconsFill.filmSlate,
  'game': PhosphorIconsFill.gameController,
  'ghost': PhosphorIconsFill.ghost,
  'skull': PhosphorIconsFill.skull,
};

/// Extra search terms per icon, so the filter matches how people describe them.
///
/// The key is matched on its own; this covers the gap between a name and an intent. Nobody
/// searching for their metal library types "skull".
const libraryIconKeywords = <String, List<String>>{
  'music-notes': ['music', 'song', 'default'],
  'vinyl-record': ['record', 'lp', 'vinyl', 'analog'],
  'disc': ['cd', 'album', 'compact'],
  'guitar': ['rock', 'metal', 'acoustic', 'strings'],
  'piano': ['keys', 'keyboard', 'classical', 'jazz'],
  'microphone': ['vocals', 'sing', 'karaoke', 'live'],
  'metronome': ['tempo', 'practice', 'classical'],
  'equalizer': ['mix', 'eq', 'studio', 'levels'],
  'waveform': ['audio', 'sound', 'wave'],
  'radio': ['station', 'broadcast', 'fm'],
  'broadcast': ['live', 'stream', 'radio'],
  'headphones': ['listen', 'personal', 'private'],
  'speaker': ['loud', 'party', 'sound'],
  'playlist': ['list', 'queue', 'mix'],
  'star': ['favourite', 'favorite', 'best', 'top'],
  'heart': ['loved', 'liked', 'favourite', 'favorite'],
  'fire': ['hot', 'banger', 'heat', 'new'],
  'sparkle': ['new', 'fresh', 'shiny', 'discover'],
  'crown': ['best', 'king', 'queen', 'classics'],
  'trophy': ['hits', 'winner', 'greatest', 'best'],
  'diamond': ['rare', 'gems', 'hidden', 'precious'],
  'folder': ['files', 'misc', 'general'],
  'archive': ['old', 'storage', 'backup', 'cold'],
  'bookmark': ['saved', 'later', 'marked'],
  'lock': ['private', 'hidden', 'secret'],
  'users': ['shared', 'friends', 'family', 'group'],
  'house': ['home', 'personal', 'mine'],
  'globe': ['world', 'international', 'global'],
  'ticket': ['live', 'concert', 'gig', 'shows'],
  'confetti': ['party', 'celebrate', 'fun'],
  'campfire': ['folk', 'acoustic', 'chill', 'outdoors'],
  'moon': ['night', 'sleep', 'late', 'ambient'],
  'sun': ['summer', 'morning', 'bright', 'happy'],
  'waves': ['ocean', 'chill', 'surf', 'calm'],
  'mountains': ['nature', 'outdoors', 'hike', 'epic'],
  'tree': ['forest', 'nature', 'folk', 'calm'],
  'coffee': ['morning', 'cafe', 'study', 'focus'],
  'car': ['drive', 'road', 'commute', 'trip'],
  'airplane': ['travel', 'flight', 'holiday'],
  'barbell': ['gym', 'workout', 'training', 'hype'],
  'books': ['study', 'reading', 'focus', 'audiobook'],
  'film': ['soundtrack', 'score', 'cinema', 'movie'],
  'game': ['gaming', 'vgm', 'soundtrack', 'chiptune'],
  'ghost': ['spooky', 'halloween', 'dark'],
  'skull': ['metal', 'death', 'dark', 'heavy'],
};

/// One emoji the picker offers, with the words that find it.
class LibraryEmoji {
  const LibraryEmoji(this.emoji, this.keywords);

  final String emoji;
  final List<String> keywords;
}

/// The emoji half of the picker: where a much larger selection actually comes from.
///
/// The glyph set above is deliberately small — every entry is a name two clients have to agree on
/// — and emoji cost nothing to add, because the platform already has them.
const libraryEmoji = <LibraryEmoji>[
  LibraryEmoji('🎵', ['music', 'note', 'song']),
  LibraryEmoji('🎶', ['music', 'notes', 'melody']),
  LibraryEmoji('🎸', ['guitar', 'rock', 'metal']),
  LibraryEmoji('🥁', ['drums', 'percussion', 'beat']),
  LibraryEmoji('🎹', ['piano', 'keys', 'classical']),
  LibraryEmoji('🎺', ['trumpet', 'brass', 'jazz']),
  LibraryEmoji('🎻', ['violin', 'strings', 'classical']),
  LibraryEmoji('🎤', ['mic', 'vocals', 'karaoke']),
  LibraryEmoji('🎧', ['headphones', 'listen', 'private']),
  LibraryEmoji('📻', ['radio', 'station', 'fm']),
  LibraryEmoji('💿', ['cd', 'disc', 'album']),
  LibraryEmoji('📀', ['dvd', 'disc', 'video']),
  LibraryEmoji('📼', ['tape', 'cassette', 'retro']),
  LibraryEmoji('🔊', ['speaker', 'loud', 'party']),
  LibraryEmoji('⭐', ['star', 'best', 'favourite', 'favorite']),
  LibraryEmoji('❤️', ['heart', 'loved', 'liked']),
  LibraryEmoji('🔥', ['fire', 'hot', 'banger']),
  LibraryEmoji('✨', ['sparkle', 'new', 'fresh']),
  LibraryEmoji('👑', ['crown', 'king', 'queen', 'classics']),
  LibraryEmoji('🏆', ['trophy', 'hits', 'greatest']),
  LibraryEmoji('💎', ['diamond', 'rare', 'gems']),
  LibraryEmoji('🌙', ['moon', 'night', 'ambient']),
  LibraryEmoji('☀️', ['sun', 'summer', 'morning']),
  LibraryEmoji('🌊', ['waves', 'ocean', 'chill']),
  LibraryEmoji('🏔️', ['mountain', 'nature', 'epic']),
  LibraryEmoji('🌲', ['tree', 'forest', 'folk']),
  LibraryEmoji('🍂', ['autumn', 'fall', 'mellow']),
  LibraryEmoji('❄️', ['winter', 'cold', 'snow']),
  LibraryEmoji('☕', ['coffee', 'cafe', 'study']),
  LibraryEmoji('🍺', ['beer', 'pub', 'party']),
  LibraryEmoji('🚗', ['car', 'drive', 'road']),
  LibraryEmoji('✈️', ['plane', 'travel', 'holiday']),
  LibraryEmoji('🏋️', ['gym', 'workout', 'training']),
  LibraryEmoji('🏃', ['run', 'running', 'cardio']),
  LibraryEmoji('📚', ['books', 'study', 'reading']),
  LibraryEmoji('🎬', ['film', 'movie', 'soundtrack']),
  LibraryEmoji('🎮', ['game', 'gaming', 'chiptune']),
  LibraryEmoji('👻', ['ghost', 'spooky', 'halloween']),
  LibraryEmoji('💀', ['skull', 'metal', 'death']),
  LibraryEmoji('🤘', ['metal', 'rock', 'horns']),
  LibraryEmoji('🕺', ['dance', 'disco', 'funk']),
  LibraryEmoji('🪩', ['disco', 'ball', 'party']),
  LibraryEmoji('🎉', ['party', 'celebrate', 'fun']),
  LibraryEmoji('🏠', ['home', 'house', 'personal']),
  LibraryEmoji('🔒', ['lock', 'private', 'secret']),
  LibraryEmoji('👨‍👩‍👧', ['family', 'shared', 'kids']),
  LibraryEmoji('🌍', ['world', 'global', 'international']),
  LibraryEmoji('🗄️', ['archive', 'storage', 'old']),
];

/// What one stored `icon` value means.
sealed class ParsedLibraryIcon {
  const ParsedLibraryIcon();
}

class GlyphLibraryIcon extends ParsedLibraryIcon {
  const GlyphLibraryIcon(this.name, this.icon);

  final String name;
  final IconData icon;
}

class EmojiLibraryIcon extends ParsedLibraryIcon {
  const EmojiLibraryIcon(this.emoji);

  final String emoji;
}

/// Reads the `icon` column.
///
/// One TEXT column carries both kinds: a bare slug is a glyph name — every row written before
/// emoji existed is one — and `emoji:` prefixes a literal emoji.
ParsedLibraryIcon parseLibraryIcon(String? stored) {
  if (stored != null && stored.startsWith(emojiIconPrefix)) {
    final emoji = stored.substring(emojiIconPrefix.length);
    if (emoji.isNotEmpty) return EmojiLibraryIcon(emoji);
  }
  final name = stored != null && libraryIcons.containsKey(stored)
      ? stored
      : defaultLibraryIcon;
  return GlyphLibraryIcon(name, libraryIcons[name]!);
}

/// Whether [term] finds an icon called [value] and also known as [keywords].
bool libraryIconMatches(String term, String value, List<String> keywords) {
  if (term.isEmpty) return true;
  final query = term.toLowerCase();
  return value.toLowerCase().contains(query) ||
      keywords.any((word) => word.toLowerCase().contains(query));
}

/// A library's chosen icon, rendered at [size].
class LibraryIcon extends StatelessWidget {
  const LibraryIcon({
    required this.icon,
    super.key,
    this.size = 24,
    this.color,
  });

  /// The stored value, not a parsed one: every call site holds a `LibrarySummary`.
  final String? icon;

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => switch (parseLibraryIcon(icon)) {
    GlyphLibraryIcon(:final icon) => Icon(icon, size: size, color: color),
    // Sized by font size rather than by a box: an emoji IS a glyph, and boxing it would leave it
    // a different size from every real icon beside it.
    EmojiLibraryIcon(:final emoji) => Text(
      emoji,
      style: TextStyle(fontSize: size * 0.85),
    ),
  };
}
