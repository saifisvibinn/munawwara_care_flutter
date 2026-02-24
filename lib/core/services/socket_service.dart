import 'package:socket_io_client/socket_io_client.dart' as io;

// ─────────────────────────────────────────────────────────────────────────────
// SocketService – static singleton wrapping the Socket.io connection.
// Call SocketService.connect(...) once after login; all other classes can
// then call SocketService.emit / .on / .off directly.
// ─────────────────────────────────────────────────────────────────────────────

class SocketService {
  static io.Socket? _socket;
  static String? _connectedUserId;

  // ── Connect ──────────────────────────────────────────────────────────────────
  static void connect({
    required String serverUrl, // e.g. "http://192.168.1.14:5000"
    required String userId,
    required String role,
  }) {
    // Don't reconnect if already live for the same user
    if (_socket != null &&
        _socket!.connected &&
        _connectedUserId == userId) {
      return;
    }

    _socket?.disconnect();
    _connectedUserId = userId;

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionDelay(2000)
          .setReconnectionAttempts(20)
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      _socket!.emit('register-user', {'userId': userId, 'role': role});
    });

    // Re-register after reconnect so the server knows who this socket is
    _socket!.on('reconnect', (_) {
      _socket!.emit('register-user', {'userId': userId, 'role': role});
    });
  }

  // ── Emit / Listen ─────────────────────────────────────────────────────────
  static void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  static void on(String event, void Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  static void off(String event) {
    _socket?.off(event);
  }

  // ── State ─────────────────────────────────────────────────────────────────
  static bool get isConnected => _socket?.connected ?? false;
  static String? get connectedUserId => _connectedUserId;

  // ── Disconnect ────────────────────────────────────────────────────────────
  static void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connectedUserId = null;
  }
}
