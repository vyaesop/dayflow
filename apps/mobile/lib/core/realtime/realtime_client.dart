import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_client.dart';
import '../auth/token_store.dart';

/// A board event pushed by the server.
class BoardEvent {
  const BoardEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  String get boardId => data['boardId'] as String? ?? '';
  String? get itemId => data['itemId'] as String?;
  String? get groupId => data['groupId'] as String?;
  String? get columnId => data['columnId'] as String?;

  Map<String, dynamic>? get patch => data['patch'] as Map<String, dynamic>?;
  Map<String, dynamic>? get item => data['item'] as Map<String, dynamic>?;
  Map<String, dynamic>? get group => data['group'] as Map<String, dynamic>?;
  Map<String, dynamic>? get column => data['column'] as Map<String, dynamic>?;

  /// Cell values are `null` when the cell was cleared, so the key must be
  /// checked rather than the value.
  bool get hasValue => data.containsKey('value');
  Map<String, dynamic>? get value => data['value'] as Map<String, dynamic>?;
}

/// Health of the live-updates link, surfaced to the UI so board screens can
/// fall back to polling (and say so) instead of silently going stale.
enum RealtimeStatus { idle, connecting, connected, offline }

/// Maintains one WebSocket to `/v1/realtime`, re-subscribing and reconnecting
/// with backoff. Board controllers subscribe to the boards they display.
///
/// Authentication happens via the first frame (`{action:'auth', token}`)
/// rather than a query parameter, keeping the JWT out of URLs and logs. The
/// server answers `{type:'ready'}` before subscriptions are honored.
class RealtimeClient {
  RealtimeClient._();
  static final instance = RealtimeClient._();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnect;
  int _attempt = 0;
  bool _disposed = false;
  bool _ready = false;

  final _events = StreamController<BoardEvent>.broadcast();
  final _boards = <String>{};

  /// Broadcast stream of every board event this connection receives.
  Stream<BoardEvent> get events => _events.stream;

  /// Current link state; listen to drive "live vs. auto-refresh" UI.
  final ValueNotifier<RealtimeStatus> status = ValueNotifier(RealtimeStatus.idle);

  bool get isConnected => status.value == RealtimeStatus.connected;

  /// Starts watching [boardId], connecting on first use.
  void subscribe(String boardId) {
    _boards.add(boardId);
    if (_channel == null) {
      _connect();
    } else if (_ready) {
      _send({'action': 'subscribe', 'boardId': boardId});
    }
  }

  void unsubscribe(String boardId) {
    _boards.remove(boardId);
    _send({'action': 'unsubscribe', 'boardId': boardId});
    // Nothing left to watch — drop the socket rather than idling.
    if (_boards.isEmpty) {
      _teardown();
      status.value = RealtimeStatus.idle;
    }
  }

  /// Forces a fresh connection, e.g. after an account switch changes the token.
  void reset() {
    _attempt = 0;
    _teardown();
    if (_boards.isNotEmpty) {
      _connect();
    } else {
      status.value = RealtimeStatus.idle;
    }
  }

  /// Retries immediately (app resumed, connectivity regained) instead of
  /// waiting out the current backoff window.
  void reconnectNow() {
    if (_disposed || _boards.isEmpty || isConnected) return;
    _attempt = 0;
    _teardown();
    _connect();
  }

  void dispose() {
    _disposed = true;
    _teardown();
    _events.close();
  }

  void _connect() {
    final token = TokenStore.instance.accessToken;
    if (token == null || _disposed) return;

    status.value = RealtimeStatus.connecting;
    final origin = apiBaseUrl().replaceFirst(RegExp(r'^http'), 'ws');

    try {
      final channel = WebSocketChannel.connect(Uri.parse('$origin/v1/realtime'));
      _channel = channel;
      _ready = false;
      _subscription = channel.stream.listen(
        _onFrame,
        onError: (Object error) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      // First frame proves who we are; subscriptions wait for `ready`.
      _send({'action': 'auth', 'token': token});
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic raw) {
    _attempt = 0; // a delivered frame proves the link is healthy
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      if (type == 'ready') {
        _ready = true;
        status.value = RealtimeStatus.connected;
        // Re-declare interest; the server keeps no state across connections.
        for (final boardId in _boards) {
          _send({'action': 'subscribe', 'boardId': boardId});
        }
        return;
      }
      if (type == null) return;
      _events.add(BoardEvent(type, decoded));
    } catch (_) {
      // Ignore frames we cannot parse rather than killing the stream.
    }
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {
      // The socket is closing; the reconnect path will re-subscribe.
    }
  }

  void _scheduleReconnect() {
    _teardown();
    if (_disposed || _boards.isEmpty) return;
    status.value = RealtimeStatus.offline;

    // Exponential backoff, capped at 30s.
    _attempt = (_attempt + 1).clamp(1, 6);
    final delay = Duration(seconds: [1, 2, 4, 8, 16, 30][_attempt - 1]);
    if (kDebugMode) {
      debugPrint('Realtime: reconnecting in ${delay.inSeconds}s');
    }
    _reconnect = Timer(delay, _connect);
  }

  void _teardown() {
    _reconnect?.cancel();
    _reconnect = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _ready = false;
  }
}
