/// The one place Chordia opens a socket.
///
/// Library servers are usually reached over a self-signed certificate, so they cannot be validated
/// against the system trust store. Instead the Hub directory advertises the SHA-256 fingerprint of
/// each server's leaf certificate, and clients pin that. Everything that talks to a library — REST,
/// WebSocket, artwork, downloads, and the outbound leg of the audio proxy — goes through the
/// clients built here, because a connection opened anywhere else would silently skip the pin.
library;

export 'src/fingerprint.dart';
export 'src/pinned_client.dart';
