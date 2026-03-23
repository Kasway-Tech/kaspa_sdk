import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kaspa_sdk/kaspa_sdk.dart';
import 'package:kaspa_sdk/src/node_client.dart' show WebSocketFactory;
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake WebSocket infrastructure
// ─────────────────────────────────────────────────────────────────────────────

/// A fake WebSocket that immediately delivers the provided responses when
/// anything is added to it. The responses are delivered as strings in order.
class _FakeWebSocket implements WebSocket {
  _FakeWebSocket(List<String> responses)
      : _controller = StreamController<dynamic>() {
    for (final r in responses) {
      _controller.add(r);
    }
    // Don't close — let the client time out or cancel normally.
  }

  final StreamController<dynamic> _controller;
  bool _closed = false;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(dynamic data) {
    // no-op: we pre-loaded responses above
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_closed) {
      _closed = true;
      await _controller.close();
    }
  }

  @override
  int get readyState => _closed ? WebSocket.closed : WebSocket.open;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake WebSocket that throws [error] when connected.
class _ThrowingFactory {
  final Object error;
  _ThrowingFactory(this.error);

  Future<WebSocket> call(String url, Duration timeout) => Future.error(error);
}

WebSocketFactory _fakeFactory(List<String> responses) =>
    (String url, Duration timeout) async => _FakeWebSocket(responses);

// ─────────────────────────────────────────────────────────────────────────────
// Test helpers
// ─────────────────────────────────────────────────────────────────────────────

String _utxoResponse({int id = 1, int amountSompi = 500000000}) {
  return jsonEncode({
    'id': id,
    'params': {
      'entries': [
        {
          'outpoint': {
            'transactionId':
                '0000000000000000000000000000000000000000000000000000000000000001',
            'index': 0,
          },
          'utxoEntry': {
            'amount': '$amountSompi',
            'scriptPublicKey': '000020${'00' * 32}ac',
            'blockDaaScore': '1000000',
            'isCoinbase': false,
          },
        },
      ],
    },
  });
}

String _submitResponse({int id = 1, String txId = 'deadbeef01'}) {
  return jsonEncode({
    'id': id,
    'params': {'transactionId': txId},
  });
}

String _submitErrorResponse({int id = 1, String message = 'rejected'}) {
  return jsonEncode({
    'id': id,
    'error': {'code': -1, 'message': message},
  });
}

String _dagInfoResponse({int id = 1, int daaScore = 12345678}) {
  return jsonEncode({
    'id': id,
    'params': {
      'virtualDaaScore': '$daaScore',
      'networkName': 'kaspa-mainnet',
      'blockCount': '1000000',
      'headerCount': '1000000',
    },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('KaspaNodeClient.getUtxosByAddresses', () {
    test('parses single UTXO entry', () async {
      final client = KaspaNodeClient(
        url: 'wss://fake',
        wsFactory: _fakeFactory([_utxoResponse(amountSompi: 500000000)]),
      );
      final utxos =
          await client.getUtxosByAddresses(['kaspa:qp...']);
      expect(utxos.length, 1);
      expect(utxos[0].amountSompi, 500000000);
      expect(utxos[0].transactionId, isNotEmpty);
      await client.close();
    });

    test('returns empty list for empty entries array', () async {
      final response = jsonEncode({
        'id': 1,
        'params': {'entries': <dynamic>[]},
      });
      final client = KaspaNodeClient(
        url: 'wss://fake',
        wsFactory: _fakeFactory([response]),
      );
      final utxos =
          await client.getUtxosByAddresses(['kaspa:qp...']);
      expect(utxos, isEmpty);
      await client.close();
    });

    test('wraps connection error in KaspaException', () async {
      final client = KaspaNodeClient(
        url: 'wss://fake',
        wsFactory: _ThrowingFactory(
          const SocketException('unreachable'),
        ).call,
      );
      await expectLater(
        client.getUtxosByAddresses(['kaspa:qp...']),
        throwsA(isA<KaspaException>()),
      );
      await client.close();
    });
  });

  group('KaspaNodeClient.submitTransaction', () {
    test('returns txId on success', () async {
      const expectedTxId = 'abc123deadbeef';
      final client = KaspaNodeClient(
        url: 'wss://fake',
        wsFactory: _fakeFactory([_submitResponse(txId: expectedTxId)]),
      );
      final txId = await client.submitTransaction(<String, dynamic>{
        'version': 0,
        'inputs': <dynamic>[],
        'outputs': <dynamic>[],
      });
      expect(txId, expectedTxId);
      await client.close();
    });

    test('throws KaspaException when node returns error', () async {
      final client = KaspaNodeClient(
        url: 'wss://fake',
        wsFactory:
            _fakeFactory([_submitErrorResponse(message: 'tx rejected')]),
      );
      await expectLater(
        client.submitTransaction(<String, dynamic>{'version': 0}),
        throwsA(
          isA<KaspaException>().having(
            (e) => e.message,
            'message',
            contains('tx rejected'),
          ),
        ),
      );
      await client.close();
    });

    test('throws KaspaException for connection failure', () async {
      final client = KaspaNodeClient(
        url: 'wss://fake',
        wsFactory: _ThrowingFactory(const SocketException('down')).call,
      );
      await expectLater(
        client.submitTransaction(<String, dynamic>{}),
        throwsA(isA<KaspaException>()),
      );
      await client.close();
    });
  });

  group('KaspaNodeClient.getBlockDagInfo', () {
    test('returns parsed KaspaBlockDagInfo', () async {
      final client = KaspaNodeClient(
        url: 'wss://fake',
        wsFactory: _fakeFactory([_dagInfoResponse(daaScore: 99887766)]),
      );
      final info = await client.getBlockDagInfo();
      expect(info.virtualDaaScore, 99887766);
      expect(info.networkName, 'kaspa-mainnet');
      await client.close();
    });

    test('throws KaspaException on connection failure', () async {
      final client = KaspaNodeClient(
        url: 'wss://fake',
        wsFactory: _ThrowingFactory(Exception('timeout')).call,
      );
      await expectLater(
        client.getBlockDagInfo(),
        throwsA(isA<KaspaException>()),
      );
      await client.close();
    });
  });

  group('KaspaNodeClient.watchBalance', () {
    test('emits balance converted from sompi to KAS', () async {
      // 1 KAS = 10^8 sompi → 500000000 sompi = 5 KAS
      final controller = StreamController<dynamic>();

      Future<WebSocket> factory(String url, Duration timeout) async {
        return _StreamBackedWebSocket(controller.stream, onAdd: (data) {
          // When client sends a request, respond with balance
          controller.add(_utxoResponse(amountSompi: 500000000));
        });
      }

      final client = KaspaNodeClient(url: 'wss://fake', wsFactory: factory);
      final balances = <double>[];

      final sub = client.watchBalance('kaspa:qp...',
          interval: const Duration(milliseconds: 50)).listen((bal) {
        balances.add(bal);
      });

      // Wait for at least one emission
      await Future<void>.delayed(const Duration(milliseconds: 200));

      await sub.cancel();
      await client.close();
      await controller.close();

      expect(balances, isNotEmpty);
      expect(balances.first, closeTo(5.0, 0.001));
    }, timeout: const Timeout(Duration(seconds: 5)));
  });
}

// ─── Helper: WebSocket backed by an external stream ──────────────────────────

typedef _OnAdd = void Function(dynamic data);

class _StreamBackedWebSocket implements WebSocket {
  _StreamBackedWebSocket(this._stream, {_OnAdd? onAdd}) : _onAdd = onAdd;

  final Stream<dynamic> _stream;
  final _OnAdd? _onAdd;
  bool _closed = false;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(dynamic data) {
    _onAdd?.call(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    _closed = true;
  }

  @override
  int get readyState => _closed ? WebSocket.closed : WebSocket.open;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
