/// The cross-device player mesh, and the playback vocabulary it carries.
///
/// Every device a listener is signed in on — this app, a browser tab, the desktop client — joins
/// one mesh and agrees on exactly one owner of playback. The owner streams audio; the others
/// mirror its state and send it transport commands. Moving playback between them is a hand-off of
/// that ownership, queue and position included.
///
/// The protocol is a port of `frontend/src/lib/player/sync.ts` and has to stay wire-identical: the
/// phone is an ordinary member of a mesh the web and desktop clients already form, so a field this
/// client spells differently does not degrade — it makes this device unusable from somebody else's
/// picker. The parts most easily broken by a well-meaning cleanup are called out where they live:
/// the pre-serialised snapshot in [PlayerSyncProtocol], the exact-set de-duplication in
/// [PlayerSyncController], and the claim tie-break in [claimWins].
///
/// Pure Dart, and free of any engine dependency, so the resolution rules can be tested against
/// scripted peers with no audio device and no socket.
library;

export 'src/controller.dart';
export 'src/domain.dart';
export 'src/link.dart';
export 'src/messages.dart';
export 'src/protocol.dart';
export 'src/snapshot.dart';
export 'src/state.dart';
