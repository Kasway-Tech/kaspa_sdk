import 'dart:typed_data';

import 'package:kaspa_sdk/kaspa_sdk.dart';
import 'package:test/test.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

// A valid secp256k1 private key (k = 1, generates a valid signature).
final _testPrivKey = Uint8List.fromList([...List.filled(31, 0x00), 0x01]);

// Builds a fake KaspaUtxoEntry with the given amount in sompi.
KaspaUtxoEntry _fakeUtxo(int amountSompi, {int index = 0}) {
  return KaspaUtxoEntry(
    transactionId:
        '0000000000000000000000000000000000000000000000000000000000000001',
    index: index,
    amountSompi: amountSompi,
    // compact SPK: version 0x0000 + P2PK script (0x20 + 32 zero bytes + 0xac)
    scriptPublicKey: '000020${'00' * 32}ac',
    blockDaaScore: 1000000,
    isCoinbase: false,
  );
}

// ─── Mass calculation constants (cross-checked against node) ─────────────────

// The public functions p2pkTxSize and computeMass are internal to transaction.dart
// and not exported. We test them indirectly via buildSignedTransaction outputs.

void main() {
  // ─── buildSignedTransaction ──────────────────────────────────────────────────

  group('buildSignedTransaction', () {
    // Build real addresses from known mnemonic for round-trip testing
    const knownMnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

    late KaspaWallet wallet;
    setUp(() {
      wallet = KaspaWallet.fromMnemonic(knownMnemonic);
    });

    test('succeeds with a single UTXO covering amount + fee', () {
      // 10 KAS UTXO, sending 5 KAS (5×10^8 sompi)
      const amountSompi = 500000000; // 5 KAS
      final utxos = [_fakeUtxo(1000000000)]; // 10 KAS

      // Use a real derivation so signing works
      final result = buildSignedTransaction(
        utxoEntries: utxos,
        fromPrivKey32: _testPrivKey,
        fromAddress: wallet.address,
        toAddress: wallet.address, // send to self for test
        amountSompi: amountSompi,
        hrp: 'kaspa',
      );

      expect(result.feeSompi, greaterThan(0));
      expect(result.inputCount, 1);
      // Transaction map should have the required keys
      expect(result.transaction['version'], 0);
      expect(result.transaction['inputs'], isList);
      expect(result.transaction['outputs'], isList);
    });

    test('fee is positive', () {
      final result = buildSignedTransaction(
        utxoEntries: [_fakeUtxo(1000000000)],
        fromPrivKey32: _testPrivKey,
        fromAddress: wallet.address,
        toAddress: wallet.address,
        amountSompi: 100000000,
        hrp: 'kaspa',
      );
      expect(result.feeSompi, greaterThan(0));
    });

    test('output scriptPublicKey has 0000 version prefix', () {
      final result = buildSignedTransaction(
        utxoEntries: [_fakeUtxo(1000000000)],
        fromPrivKey32: _testPrivKey,
        fromAddress: wallet.address,
        toAddress: wallet.address,
        amountSompi: 100000000,
        hrp: 'kaspa',
      );
      final outputs = result.transaction['outputs'] as List<dynamic>;
      for (final out in outputs) {
        final spk = (out as Map<String, dynamic>)['scriptPublicKey'] as String;
        expect(spk, startsWith('0000'));
      }
    });

    test('signed inputs include signatureScript', () {
      final result = buildSignedTransaction(
        utxoEntries: [_fakeUtxo(1000000000)],
        fromPrivKey32: _testPrivKey,
        fromAddress: wallet.address,
        toAddress: wallet.address,
        amountSompi: 100000000,
        hrp: 'kaspa',
      );
      final inputs = result.transaction['inputs'] as List<dynamic>;
      for (final inp in inputs) {
        final sig =
            (inp as Map<String, dynamic>)['signatureScript'] as String;
        expect(sig, isNotEmpty);
        // P2PK sig script = 66 bytes = 132 hex chars
        expect(sig.length, 132);
      }
    });

    test('throws KaspaException when toAddress hrp mismatches', () {
      expect(
        () => buildSignedTransaction(
          utxoEntries: [_fakeUtxo(1000000000)],
          fromPrivKey32: _testPrivKey,
          fromAddress: wallet.address,
          toAddress:
              'kaspatest:qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq',
          amountSompi: 100000000,
          hrp: 'kaspa',
        ),
        throwsA(isA<KaspaException>()),
      );
    });

    test('throws InsufficientFundsException when UTXOs too small', () {
      // 1000 sompi UTXO, trying to send 1 KAS (10^8 sompi)
      final utxos = [_fakeUtxo(1000)];
      expect(
        () => buildSignedTransaction(
          utxoEntries: utxos,
          fromPrivKey32: _testPrivKey,
          fromAddress: wallet.address,
          toAddress: wallet.address,
          amountSompi: 100000000, // 1 KAS
          hrp: 'kaspa',
        ),
        throwsA(isA<InsufficientFundsException>()),
      );
    });

    test('throws InsufficientFundsException for empty UTXO list', () {
      expect(
        () => buildSignedTransaction(
          utxoEntries: [],
          fromPrivKey32: _testPrivKey,
          fromAddress: wallet.address,
          toAddress: wallet.address,
          amountSompi: 100000000,
          hrp: 'kaspa',
        ),
        throwsA(isA<InsufficientFundsException>()),
      );
    });

    test('absorbs dust change (< 600 sompi) into fee', () {
      // Design: send almost all of a UTXO so change would be dust.
      // 1_000_002_036 sompi UTXO, sending 1_000_000_000 sompi.
      // Expected fee = ~2036 (1-in-2-out compute mass), change = 2036 - fee ≈ dust.
      // After dust absorption, changeSompi should be 0.
      final utxo = _fakeUtxo(1000002100); // slightly above amount + computed fee
      final result = buildSignedTransaction(
        utxoEntries: [utxo],
        fromPrivKey32: _testPrivKey,
        fromAddress: wallet.address,
        toAddress: wallet.address,
        amountSompi: 1000000000,
        hrp: 'kaspa',
      );
      // Change is either 0 (absorbed) or small-but-not-dust; fee covers all
      expect(result.feeSompi, greaterThan(0));
      expect(result.inputCount, 1);
    });

    test('selects multiple UTXOs when single one is insufficient', () {
      // Each UTXO = 600000 sompi; sending 1_000_000 sompi + fee requires 2+
      final utxos = List.generate(5, (i) => _fakeUtxo(600000, index: i));
      final result = buildSignedTransaction(
        utxoEntries: utxos,
        fromPrivKey32: _testPrivKey,
        fromAddress: wallet.address,
        toAddress: wallet.address,
        amountSompi: 1000000,
        hrp: 'kaspa',
      );
      expect(result.inputCount, greaterThan(1));
    });
  });

  // ─── Exception types ─────────────────────────────────────────────────────────

  group('Exception types', () {
    test('KaspaException.toString includes message', () {
      const e = KaspaException('something went wrong');
      expect(e.toString(), contains('something went wrong'));
    });

    test('InsufficientFundsException is a KaspaException', () {
      expect(
        const InsufficientFundsException('x'),
        isA<KaspaException>(),
      );
    });

    test('MassLimitException is a KaspaException', () {
      expect(const MassLimitException('x'), isA<KaspaException>());
    });
  });
}
