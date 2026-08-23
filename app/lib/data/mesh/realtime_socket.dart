/// The socket seam: one text pipe to the Hub, and the real implementation of it.
library;

import 'dart:async';
import 'dart:io';

import 'package:chordia_net/chordia_net.dart';
import 'package:web_socket_channel/io.dart';

/// How long to wait for the upgrade before giving up and letting the backoff take over.
const Duration kRealtimeConnectTimeout = Duration(seconds: 15);

/// How often to send a protocol ping.
///
/// Not decoration: a phone's carrier NAT drops an idle mapping in a couple of minutes, and a mesh
/// member whose socket has silently gone away is worse than one that left — every other device
/// still offers it as a playback target. The ping keeps the mapping alive and, when the network
/// really has gone, makes the close happen promptly instead of at the next send.
const Duration kRealtimePingInterval = Duration(seconds: 30);

/// One open connection to the Hub's realtime endpoint, reduced to what the mesh needs of it.
///
/// An interface rather than a `WebSocketChannel` because every rule worth testing here — the exact
/// bytes of an outbound frame, that a non-player kind never reaches the mesh, that a token refresh
/// opens a second socket — is about what crosses this boundary, and none of them should need a
/// listening server to exercise.
abstract interface class RealtimeSocket {
  /// Text frames from the Hub. Completes when the connection closes, however it closed.
  Stream<String> get messages;

  /// Send one text frame. Throwing is a supported answer; the caller treats it as a dead pipe.
  void send(String text);

  Future<void> close();
}

/// Opens a socket at [url]. Injected so a test can hand back a scripted pipe.
typedef RealtimeSocketOpener = Future<RealtimeSocket> Function(Uri url);

/// The production opener: a WebSocket over the app's shared HTTP client.
///
/// Unpinned, like every other Hub call — the Hub is a public host with an ordinary certificate,
/// and it is the LIBRARY servers that are pinned to an advertised fingerprint. Going through the
/// factory rather than `WebSocket.connect` is still what makes the connection Chordia's: it
/// carries the app's user agent and the same timeouts as every other request.
RealtimeSocketOpener ioRealtimeSocketOpener(
  PinnedHttpClientFactory factory,
) => (url) async {
  // One client per socket, closed with it. The channel does not own the client, so nothing
  // else would ever release the connection this leaves parked in the pool.
  final client = factory.unpinned();
  try {
    final channel = IOWebSocketChannel.connect(
      url,
      customClient: client,
      pingInterval: kRealtimePingInterval,
      connectTimeout: kRealtimeConnectTimeout,
    );
    await channel.ready;
    return _IoRealtimeSocket(channel, client);
  } on Object {
    client.close(force: true);
    rethrow;
  }
};

class _IoRealtimeSocket implements RealtimeSocket {
  _IoRealtimeSocket(this._channel, this._client);

  final IOWebSocketChannel _channel;
  final HttpClient _client;
  bool _closed = false;

  @override
  Stream<String> get messages => _messages;

  late final Stream<String> _messages = _channel.stream
      // Binary is not part of the protocol. Dropping a frame we cannot read beats decoding it as
      // text and handing the mesh something that will not parse.
      .where((frame) => frame is String)
      .cast<String>()
      // A socket error IS the close, as far as the caller is concerned: nothing on this connection
      // is recoverable, and the done that follows is what the caller reconnects from.
      .handleError((Object _) {})
      .transform(
        StreamTransformer<String, String>.fromHandlers(
          handleDone: (sink) {
            _release();
            sink.close();
          },
        ),
      );

  @override
  void send(String text) {
    if (_closed) throw StateError('the realtime socket is closed');
    _channel.sink.add(text);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel.sink.close();
    _client.close(force: true);
  }

  void _release() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}
