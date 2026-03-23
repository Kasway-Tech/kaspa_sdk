import 'dart:typed_data';

import 'package:kaspa_sdk/kaspa_sdk.dart';
import 'package:test/test.dart';

// The known mnemonic derives a known address deterministically.
const _knownMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  // ─── encodeKaspaAddress ─────────────────────────────────────────────────────

  group('encodeKaspaAddress', () {
    test('produces a kaspa: address for a 33-byte compressed key', () {
      // Use a fake 33-byte key; we just test the encoding, not key validity.
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02; // even Y
      final address = encodeKaspaAddress(pubkey);
      expect(address, startsWith('kaspa:'));
    });

    test('uses provided hrp', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      final address = encodeKaspaAddress(pubkey, hrp: 'kaspatest');
      expect(address, startsWith('kaspatest:'));
    });

    test('address only contains valid cashaddr characters after colon', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      final address = encodeKaspaAddress(pubkey);
      final afterColon = address.substring(address.indexOf(':') + 1);
      final validChars =
          RegExp(r'^[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+$');
      expect(validChars.hasMatch(afterColon), isTrue,
          reason: 'invalid chars in "$afterColon"');
    });

    test('is deterministic', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      final a1 = encodeKaspaAddress(pubkey);
      final a2 = encodeKaspaAddress(pubkey);
      expect(a1, equals(a2));
    });

    test('different pubkeys produce different addresses', () {
      final k1 = Uint8List(33);
      k1[0] = 0x02;
      k1[32] = 0x01;
      final k2 = Uint8List(33);
      k2[0] = 0x02;
      k2[32] = 0x02;
      expect(encodeKaspaAddress(k1), isNot(equals(encodeKaspaAddress(k2))));
    });

    test('mainnet and testnet encode produce different addresses', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      final main = encodeKaspaAddress(pubkey, hrp: 'kaspa');
      final test = encodeKaspaAddress(pubkey, hrp: 'kaspatest');
      expect(main, isNot(equals(test)));
    });
  });

  // ─── decodeKaspaAddress ─────────────────────────────────────────────────────

  group('decodeKaspaAddress', () {
    test('returns 32 bytes for a valid address', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      pubkey[1] = 0x42;
      final addr = encodeKaspaAddress(pubkey);
      final decoded = decodeKaspaAddress(addr);
      expect(decoded, isNotNull);
      expect(decoded!.length, 32);
    });

    test('round-trips encode → decode', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      for (var i = 1; i < 33; i++) {
        pubkey[i] = i * 3 & 0xff;
      }
      final addr = encodeKaspaAddress(pubkey);
      final decoded = decodeKaspaAddress(addr);
      expect(decoded, isNotNull);
      // The decoded bytes should match pubkey[1..32] (x-coordinate only)
      expect(decoded, equals(pubkey.sublist(1, 33)));
    });

    test('returns null for empty string', () {
      expect(decodeKaspaAddress(''), isNull);
    });

    test('returns null for address without colon', () {
      expect(decodeKaspaAddress('qpzry9x8gf2tvdw0s3jn54k'), isNull);
    });

    test('returns null for random garbage', () {
      expect(decodeKaspaAddress('kaspa:notvalid!!'), isNull);
    });
  });

  // ─── addressToP2pkScript ────────────────────────────────────────────────────

  group('addressToP2pkScript', () {
    test('returns a 34-byte hex script (68 hex chars) for a valid address', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      pubkey[1] = 0x55;
      final addr = encodeKaspaAddress(pubkey);
      final script = addressToP2pkScript(addr);
      expect(script.length, 68); // 34 bytes = 68 hex chars
    });

    test('script starts with 20 (OP_DATA_32)', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      final addr = encodeKaspaAddress(pubkey);
      final script = addressToP2pkScript(addr);
      expect(script, startsWith('20'));
    });

    test('script ends with ac (OP_CHECKSIG)', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      final addr = encodeKaspaAddress(pubkey);
      final script = addressToP2pkScript(addr);
      expect(script, endsWith('ac'));
    });

    test('returns empty string for malformed address', () {
      expect(addressToP2pkScript('not:an:address'), isEmpty);
    });

    test('returns empty string for empty string', () {
      expect(addressToP2pkScript(''), isEmpty);
    });
  });

  // ─── scriptToAddress ────────────────────────────────────────────────────────

  group('scriptToAddress', () {
    test('round-trip: address → script → address', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      for (var i = 1; i < 33; i++) {
        pubkey[i] = (i * 7) & 0xff;
      }
      final original = encodeKaspaAddress(pubkey);
      final script = addressToP2pkScript(original);
      // compact SPK = "0000" (version) + script
      final compactSpk = '0000$script';
      final recovered = scriptToAddress(compactSpk);
      expect(recovered, equals(original));
    });

    test('returns null for invalid SPK hex', () {
      expect(scriptToAddress('deadbeef'), isNull);
    });

    test('returns null for empty string', () {
      expect(scriptToAddress(''), isNull);
    });

    test('returns null for non-P2PK script (wrong length)', () {
      // version 0 + 10 bytes = not a 34-byte P2PK script
      expect(scriptToAddress('0000${'aa' * 10}'), isNull);
    });

    test('returns null for script with wrong first opcode', () {
      // version 0 + 0x21 (not 0x20) + 32 bytes + 0xac
      expect(scriptToAddress('000021${'aa' * 32}ac'), isNull);
    });

    test('returns null for script with wrong last opcode', () {
      // version 0 + 0x20 + 32 bytes + 0xad (not 0xac)
      expect(scriptToAddress('000020${'aa' * 32}ad'), isNull);
    });

    test('uses provided hrp', () {
      final pubkey = Uint8List(33);
      pubkey[0] = 0x02;
      pubkey[1] = 0x99;
      final addr = encodeKaspaAddress(pubkey, hrp: 'kaspatest');
      final script = addressToP2pkScript(addr);
      final compactSpk = '0000$script';
      final recovered = scriptToAddress(compactSpk, hrp: 'kaspatest');
      expect(recovered, startsWith('kaspatest:'));
    });
  });

  // ─── KaspaWallet address derivation integration ──────────────────────────────

  group('KaspaWallet address (via encodeKaspaAddress)', () {
    test('known mnemonic derives a kaspa: address', () {
      final wallet = KaspaWallet.fromMnemonic(_knownMnemonic);
      expect(wallet.address, startsWith('kaspa:'));
    });

    test('address has >= 60 chars', () {
      final wallet = KaspaWallet.fromMnemonic(_knownMnemonic);
      expect(wallet.address.length, greaterThanOrEqualTo(60));
    });

    test('derivation is deterministic', () {
      final a1 = KaspaWallet.fromMnemonic(_knownMnemonic).address;
      final a2 = KaspaWallet.fromMnemonic(_knownMnemonic).address;
      expect(a1, equals(a2));
    });

    test('testnet mnemonic gives kaspatest: address', () {
      final wallet =
          KaspaWallet.fromMnemonic(_knownMnemonic, hrp: 'kaspatest');
      expect(wallet.address, startsWith('kaspatest:'));
    });

    test('mainnet and testnet addresses differ', () {
      final main = KaspaWallet.fromMnemonic(_knownMnemonic).address;
      final test =
          KaspaWallet.fromMnemonic(_knownMnemonic, hrp: 'kaspatest').address;
      expect(main, isNot(equals(test)));
    });
  });
}
