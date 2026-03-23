import 'dart:typed_data';

import 'package:hex/hex.dart';
import 'package:kaspa_sdk/kaspa_sdk.dart';
import 'package:test/test.dart';

// A valid secp256k1 private key (k=1) for use in tests.
final _privKey1 = Uint8List.fromList([...List.filled(31, 0x00), 0x01]);

void main() {
  // ─── parseCompactSpk ────────────────────────────────────────────────────────

  group('parseCompactSpk', () {
    test('parses a standard P2PK compact SPK', () {
      // version bytes 0x00 0x00 (LE u16 = 0) + 34-byte P2PK script
      final spkHex = '000020${'aa' * 32}ac';
      final result = parseCompactSpk(spkHex);
      expect(result.version, 0);
      expect(result.script.length, 34);
    });

    test('returns version=0 and empty script for empty input', () {
      final result = parseCompactSpk('');
      expect(result.version, 0);
      expect(result.script, isEmpty);
    });

    test('returns version=0 and empty script for single-byte input', () {
      final result = parseCompactSpk('ff');
      expect(result.version, 0);
      expect(result.script, isEmpty);
    });

    test('parses little-endian version correctly', () {
      // 0x01 0x00 LE = version 1
      final result = parseCompactSpk('0100aabb');
      expect(result.version, 1);
      expect(result.script.length, 2);
    });
  });

  // ─── buildP2pkSigScript ─────────────────────────────────────────────────────

  group('buildP2pkSigScript', () {
    test('produces 66-byte output', () {
      final sig = Uint8List(64);
      final result = buildP2pkSigScript(sig);
      expect(result.length, 66);
    });

    test('first byte is OP_DATA_65 (0x41)', () {
      final sig = Uint8List(64);
      expect(buildP2pkSigScript(sig)[0], 0x41);
    });

    test('last byte is SIG_HASH_ALL (0x01)', () {
      final sig = Uint8List(64);
      expect(buildP2pkSigScript(sig)[65], 0x01);
    });

    test('bytes 1..64 match the input signature', () {
      final sig = Uint8List.fromList(List.generate(64, (i) => i));
      final result = buildP2pkSigScript(sig);
      expect(result.sublist(1, 65), sig);
    });
  });

  // ─── kaspaSchnorrSign ────────────────────────────────────────────────────────

  group('kaspaSchnorrSign', () {
    final testMsg = Uint8List.fromList(List.generate(32, (i) => i));

    test('produces a 64-byte signature', () {
      final sig = kaspaSchnorrSign(_privKey1, testMsg);
      expect(sig.length, 64);
    });

    test('signing is deterministic', () {
      final sig1 = kaspaSchnorrSign(_privKey1, testMsg);
      final sig2 = kaspaSchnorrSign(_privKey1, testMsg);
      expect(sig1, equals(sig2));
    });

    test('different messages produce different signatures', () {
      final msg2 = Uint8List.fromList(List.generate(32, (i) => 32 - i));
      final sig1 = kaspaSchnorrSign(_privKey1, testMsg);
      final sig2 = kaspaSchnorrSign(_privKey1, msg2);
      expect(sig1, isNot(equals(sig2)));
    });

    test('different keys produce different signatures', () {
      final privKey2 = Uint8List.fromList([...List.filled(31, 0x00), 0x02]);
      final sig1 = kaspaSchnorrSign(_privKey1, testMsg);
      final sig2 = kaspaSchnorrSign(privKey2, testMsg);
      expect(sig1, isNot(equals(sig2)));
    });
  });

  // ─── calcKaspaSigHash ────────────────────────────────────────────────────────

  group('calcKaspaSigHash', () {
    final dummyTxId =
        '0000000000000000000000000000000000000000000000000000000000000001';
    final dummyScript =
        Uint8List.fromList(HEX.decode('20${'aa' * 32}ac'));

    test('returns 32 bytes', () {
      final hash = calcKaspaSigHash(
        txVersion: 0,
        txIds: [dummyTxId],
        indices: [0],
        utxos: [
          KaspaUtxo(amount: 1000000000, scriptVersion: 0, script: dummyScript),
        ],
        outputs: [
          KaspaOutput(value: 900000000, scriptVersion: 0, script: dummyScript),
        ],
        inputIndex: 0,
      );
      expect(hash.length, 32);
    });

    test('is deterministic', () {
      final utxos = [
        KaspaUtxo(amount: 1000000000, scriptVersion: 0, script: dummyScript),
      ];
      final outputs = [
        KaspaOutput(value: 900000000, scriptVersion: 0, script: dummyScript),
      ];
      final h1 = calcKaspaSigHash(
        txVersion: 0,
        txIds: [dummyTxId],
        indices: [0],
        utxos: utxos,
        outputs: outputs,
        inputIndex: 0,
      );
      final h2 = calcKaspaSigHash(
        txVersion: 0,
        txIds: [dummyTxId],
        indices: [0],
        utxos: utxos,
        outputs: outputs,
        inputIndex: 0,
      );
      expect(h1, equals(h2));
    });

    test('different input index produces different hash', () {
      final script2 = Uint8List.fromList(HEX.decode('20${'bb' * 32}ac'));
      final utxos = [
        KaspaUtxo(amount: 1000000000, scriptVersion: 0, script: dummyScript),
        KaspaUtxo(amount: 500000000, scriptVersion: 0, script: script2),
      ];
      final outputs = [
        KaspaOutput(value: 1400000000, scriptVersion: 0, script: dummyScript),
      ];
      final txId2 =
          '0000000000000000000000000000000000000000000000000000000000000002';
      final h0 = calcKaspaSigHash(
        txVersion: 0,
        txIds: [dummyTxId, txId2],
        indices: [0, 1],
        utxos: utxos,
        outputs: outputs,
        inputIndex: 0,
      );
      final h1 = calcKaspaSigHash(
        txVersion: 0,
        txIds: [dummyTxId, txId2],
        indices: [0, 1],
        utxos: utxos,
        outputs: outputs,
        inputIndex: 1,
      );
      expect(h0, isNot(equals(h1)));
    });

    test('can sign the resulting hash without throwing', () {
      final hash = calcKaspaSigHash(
        txVersion: 0,
        txIds: [dummyTxId],
        indices: [0],
        utxos: [
          KaspaUtxo(amount: 1000000000, scriptVersion: 0, script: dummyScript),
        ],
        outputs: [
          KaspaOutput(value: 900000000, scriptVersion: 0, script: dummyScript),
        ],
        inputIndex: 0,
      );
      expect(() => kaspaSchnorrSign(_privKey1, hash), returnsNormally);
    });
  });
}
