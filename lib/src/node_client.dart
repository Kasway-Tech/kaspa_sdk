/// Kaspa wRPC JSON-RPC client over WebSocket.
library;
///
/// Supports both one-shot method calls and continuous balance monitoring.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'models.dart';
import 'transaction.dart' show KaspaException;

/// Factory function type for creating WebSocket connections.
/// Injectable for testing.
@visibleForTesting
typedef WebSocketFactory = Future<WebSocket> Function(
  String url,
  Duration timeout,
);

Future<WebSocket> _defaultWsFactory(String url, Duration timeout) =>
    WebSocket.connect(url).timeout(timeout);

/// A client for the Kaspa wRPC JSON protocol over WebSocket.
///
/// ## One-shot calls
///
/// [getUtxosByAddresses], [submitTransaction], and [getBlockDagInfo] each
/// open a new WebSocket connection, execute the request, and close the
/// connection. They can be called concurrently.
///
/// ```dart
/// final client = KaspaNodeClient(url: 'wss://node.kaspa.stream/...');
/// final utxos = await client.getUtxosByAddresses(['kaspa:qp...']);
/// final txId = await client.submitTransaction(signedTx);
/// await client.close();
/// ```
///
/// ## Continuous balance monitoring
///
/// `watchBalance` returns a broadcast [Stream] that polls the node every
/// `interval` and emits the total balance in KAS whenever the underlying
/// WebSocket delivers a response. The connection is managed internally and
/// auto-reconnects on error.
///
/// ```dart
/// final sub = client.watchBalance('kaspa:qp...').listen((kas) {
///   print('Balance: $kas KAS');
/// });
/// // ...later
/// await sub.cancel();
/// await client.close();
/// ```
class KaspaNodeClient {
  /// Creates a [KaspaNodeClient] connected to [url].
  ///
  /// [connectTimeout] is how long to wait when opening a WebSocket.
  /// [requestTimeout] is how long to wait for a JSON-RPC response.
  KaspaNodeClient({
    required this.url,
    this.connectTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 15),
    @visibleForTesting WebSocketFactory? wsFactory,
  }) : _wsFactory = wsFactory ?? _defaultWsFactory;

  /// The wRPC WebSocket endpoint URL.
  final String url;

  /// Timeout for establishing a WebSocket connection.
  final Duration connectTimeout;

  /// Timeout for receiving a JSON-RPC response.
  final Duration requestTimeout;

  final WebSocketFactory _wsFactory;

  // Persistent connection state (used by watchBalance)
  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _pollTimer;
  StreamController<double>? _balanceController;
  bool _closed = false;

  // ─────────────────────────────────────────────────────────────────────────
  // One-shot helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<WebSocket> _connect() => _wsFactory(url, connectTimeout);

  /// Sends [request] on [ws] and waits for the response with the matching id.
  Future<Map<String, dynamic>> _rpc(
    WebSocket ws,
    Map<String, dynamic> request,
  ) async {
    final id = (request['id'] as num).toInt();
    final completer = Completer<Map<String, dynamic>>();
    late StreamSubscription<dynamic> sub;
    sub = ws.listen(
      (raw) {
        if (raw is! String) return;
        try {
          final msg = jsonDecode(raw) as Map<String, dynamic>;
          final msgId = (msg['id'] as num?)?.toInt();
          if (msgId == id && !completer.isCompleted) {
            completer.complete(msg);
          }
        } catch (_) {}
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            const KaspaException('WebSocket closed before response'),
          );
        }
      },
    );

    ws.add(jsonEncode(request));

    try {
      return await completer.future.timeout(requestTimeout);
    } finally {
      await sub.cancel();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public one-shot API
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches the current UTXOs for [addresses] from the node.
  ///
  /// Throws [KaspaException] on connection or protocol errors.
  Future<List<KaspaUtxoEntry>> getUtxosByAddresses(
    List<String> addresses,
  ) async {
    WebSocket? ws;
    try {
      ws = await _connect();
      final response = await _rpc(ws, {
        'id': 1,
        'method': 'getUtxosByAddresses',
        'params': {'addresses': addresses},
      });
      final params = (response['params'] as Map<String, dynamic>?) ?? {};
      final entries = (params['entries'] as List<dynamic>?) ?? [];
      return entries
          .map((e) => KaspaUtxoEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on KaspaException {
      rethrow;
    } catch (e) {
      throw KaspaException('getUtxosByAddresses failed: $e');
    } finally {
      await ws?.close();
    }
  }

  /// Submits a signed transaction and returns the transaction ID.
  ///
  /// [tx] must be the `transaction` map from a `KaspaTransactionResult`.
  ///
  /// Throws [KaspaException] if the node rejects the transaction or on
  /// connection errors.
  Future<String> submitTransaction(Map<String, dynamic> tx) async {
    WebSocket? ws;
    try {
      ws = await _connect();
      final response = await _rpc(ws, {
        'id': 1,
        'method': 'submitTransaction',
        'params': {'transaction': tx, 'allowOrphan': false},
      });
      if (response.containsKey('error')) {
        final err = response['error'];
        final errMsg = err is Map<String, dynamic>
            ? (err['message'] as String?) ?? 'Unknown node error'
            : err.toString();
        throw KaspaException(errMsg);
      }
      final params = (response['params'] as Map<String, dynamic>?) ?? {};
      final txId = (params['transactionId'] as String?) ?? '';
      if (txId.isEmpty) {
        throw KaspaException('Empty txId in submitTransaction response');
      }
      return txId;
    } on KaspaException {
      rethrow;
    } catch (e) {
      throw KaspaException('submitTransaction failed: $e');
    } finally {
      await ws?.close();
    }
  }

  /// Returns current block DAG info, including the virtual DAA score.
  ///
  /// The virtual DAA score is used to count confirmations: a transaction
  /// detected at DAA score D has `(currentDaaScore - D)` confirmations.
  ///
  /// Throws [KaspaException] on connection or protocol errors.
  Future<KaspaBlockDagInfo> getBlockDagInfo() async {
    WebSocket? ws;
    try {
      ws = await _connect();
      final response = await _rpc(ws, {
        'id': 1,
        'method': 'getBlockDagInfo',
        'params': <String, dynamic>{},
      });
      final params = (response['params'] as Map<String, dynamic>?) ?? {};
      return KaspaBlockDagInfo.fromJson(params);
    } on KaspaException {
      rethrow;
    } catch (e) {
      throw KaspaException('getBlockDagInfo failed: $e');
    } finally {
      await ws?.close();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Continuous balance stream
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a broadcast stream that emits the balance of [address] in KAS.
  ///
  /// The stream polls the node every [interval] using a persistent WebSocket
  /// connection. It auto-reconnects after a 3-second delay on disconnection.
  ///
  /// The stream emits every time the node responds (even when balance is
  /// unchanged). Cancel the subscription to stop polling. Call [close] to
  /// release all resources.
  Stream<double> watchBalance(
    String address, {
    Duration interval = const Duration(seconds: 1),
  }) {
    if (_balanceController == null || _balanceController!.isClosed) {
      _balanceController = StreamController<double>.broadcast(
        onCancel: _stopWatching,
      );
    }
    _startPolling(address, interval);
    return _balanceController!.stream;
  }

  void _startPolling(String address, Duration interval) {
    unawaited(_connectPersistent(address, interval));
  }

  Future<void> _connectPersistent(String address, Duration interval) async {
    if (_closed) return;
    await runZonedGuarded(() async {
      try {
        final ws = await _wsFactory(url, connectTimeout);
        if (_closed) {
          await ws.close();
          return;
        }
        _ws = ws;
        _wsSub = ws.listen(
          _handleBalanceMessage,
          onError: (_) =>
              unawaited(_reconnectPersistent(address, interval)),
          onDone: () =>
              unawaited(_reconnectPersistent(address, interval)),
        );
        _sendUtxoRequest(address);
        _pollTimer = Timer.periodic(interval, (_) => _sendUtxoRequest(address));
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 3));
        unawaited(_connectPersistent(address, interval));
      }
    }, (e, _) {
      // Swallow SocketException thrown by dart:io internals after socket close.
      if (e is! SocketException) {
        // ignore: avoid_print
        print('[KaspaNodeClient] zone error: $e');
      }
    });
  }

  void _sendUtxoRequest(String address) {
    try {
      _ws?.add(jsonEncode({
        'id': 1,
        'method': 'getUtxosByAddresses',
        'params': {
          'addresses': [address],
        },
      }));
    } catch (_) {}
  }

  void _handleBalanceMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final params = (msg['params'] as Map<String, dynamic>?) ?? {};
      final entries = (params['entries'] as List<dynamic>?) ?? [];
      double total = 0;
      for (final e in entries) {
        final entry = KaspaUtxoEntry.fromJson(e as Map<String, dynamic>);
        total += entry.amountSompi / 1e8;
      }
      if (!(_balanceController?.isClosed ?? true)) {
        _balanceController?.add(total);
      }
    } catch (_) {}
  }

  Future<void> _reconnectPersistent(String address, Duration interval) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    if (_closed) return;
    await Future<void>.delayed(const Duration(seconds: 3));
    unawaited(_connectPersistent(address, interval));
  }

  void _stopWatching() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _wsSub?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _balanceController = null;
  }

  /// Releases all resources held by this client.
  ///
  /// After calling [close], this client must not be used again.
  Future<void> close() async {
    _closed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    await _balanceController?.close();
    _balanceController = null;
  }
}
