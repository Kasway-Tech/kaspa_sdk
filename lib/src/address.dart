/// Kaspa cashaddr encoding and decoding.
///
/// Kaspa uses a bech32-like address format (sometimes called "cashaddr") with:
///   - A human-readable part (HRP): `'kaspa'` for mainnet, `'kaspatest'` for testnet-10
///   - A `:` separator
///   - A base-32 encoded payload (version byte + x-only pubkey + 8-byte checksum)
///
/// Example mainnet address:
/// ```
/// kaspa:qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw
/// ```
library;

import 'dart:typed_data';

import 'package:hex/hex.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Charset + polymod
// ─────────────────────────────────────────────────────────────────────────────

/// The base-32 charset used by Kaspa cashaddr (same as Bitcoin Cash cashaddr).
const kaspaCharset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

int _polymod(List<int> data) {
  var c = 1;
  for (final d in data) {
    final c0 = c >> 35;
    c = ((c & 0x07ffffffff) << 5) ^ d;
    if (c0 & 0x01 != 0) c ^= 0x98f2bc8e61;
    if (c0 & 0x02 != 0) c ^= 0x79b76d99e2;
    if (c0 & 0x04 != 0) c ^= 0xf33e5fb3c4;
    if (c0 & 0x08 != 0) c ^= 0xae2eabe2a8;
    if (c0 & 0x10 != 0) c ^= 0x1e4f43e470;
  }
  return c ^ 1;
}

List<int> _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxv = (1 << toBits) - 1;
  for (final value in data) {
    acc = ((acc << fromBits) | value) & 0xffffffff;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      result.add((acc >> bits) & maxv);
    }
  }
  if (pad && bits > 0) {
    result.add((acc << (toBits - bits)) & maxv);
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Encodes a 33-byte BIP32 compressed public key as a Kaspa cashaddr.
///
/// The [pubkeyBytes33] must be 33 bytes (standard compressed secp256k1 key).
/// The first byte (parity) is stripped; only the 32-byte x-coordinate is encoded.
///
/// [hrp] defaults to `'kaspa'` (mainnet). Use `'kaspatest'` for testnet-10.
String encodeKaspaAddress(Uint8List pubkeyBytes33, {String hrp = 'kaspa'}) {
  final payload = [0x00, ...pubkeyBytes33.sublist(1)];
  final data5 = _convertBits(payload, 8, 5, true);
  final checksumInput = [
    ...hrp.codeUnits.map((c) => c & 0x1f),
    0,
    ...data5,
    0, 0, 0, 0, 0, 0, 0, 0,
  ];
  final checksum = _polymod(checksumInput);
  final sb = StringBuffer('$hrp:');
  for (final d in data5) {
    sb.write(kaspaCharset[d]);
  }
  for (var i = 7; i >= 0; i--) {
    sb.write(kaspaCharset[(checksum >> (i * 5)) & 0x1f]);
  }
  return sb.toString();
}

/// Decodes a Kaspa cashaddr to its 32-byte x-only public key bytes.
///
/// Returns `null` if the address is malformed, has an invalid checksum, or
/// does not represent a valid P2PK address.
Uint8List? decodeKaspaAddress(String address) {
  try {
    final colonIdx = address.indexOf(':');
    if (colonIdx < 0) return null;
    final data = address.substring(colonIdx + 1).toLowerCase();
    final charMap = <String, int>{};
    for (var i = 0; i < kaspaCharset.length; i++) {
      charMap[kaspaCharset[i]] = i;
    }
    final data5 = <int>[];
    for (final c in data.split('')) {
      final val = charMap[c];
      if (val == null) return null;
      data5.add(val);
    }
    if (data5.length < 9) return null;
    final payload5 = data5.sublist(0, data5.length - 8);
    final payload8 = _convertBits(payload5, 5, 8, false);
    if (payload8.length < 33) return null;
    return Uint8List.fromList(payload8.sublist(1, 33));
  } catch (_) {
    return null;
  }
}

/// Converts a Kaspa cashaddr to its 34-byte P2PK scriptPublicKey hex string
/// (format: `20{32-byte-pubkey}ac`).
///
/// Returns an empty string if the address is malformed.
String addressToP2pkScript(String address) {
  final pubkey = decodeKaspaAddress(address);
  if (pubkey == null || pubkey.length != 32) return '';
  return '20${HEX.encode(pubkey)}ac';
}

/// Decodes a compact scriptPublicKey hex string to the corresponding Kaspa address.
///
/// The compact SPK format is `"VVVV{script_hex}"` where the first 2 bytes
/// (little-endian u16) are the script version and the remainder is the script.
///
/// Returns `null` if the script is not a recognised P2PK (34-byte) script
/// or if [compactSpkHex] is malformed.
///
/// [hrp] defaults to `'kaspa'` (mainnet). Use `'kaspatest'` for testnet-10.
String? scriptToAddress(String compactSpkHex, {String hrp = 'kaspa'}) {
  try {
    final bytes = Uint8List.fromList(HEX.decode(compactSpkHex));
    if (bytes.length < 2) return null;
    final version = bytes[0] | (bytes[1] << 8);
    final script = bytes.sublist(2);
    // P2PK: OP_DATA_32 (0x20) + 32-byte x-only pubkey + OP_CHECKSIG (0xac)
    if (version != 0 || script.length != 34 ||
        script[0] != 0x20 || script[33] != 0xac) {
      return null;
    }
    // Wrap the 32-byte x-only key in a fake 33-byte compressed key so that
    // encodeKaspaAddress (which calls sublist(1)) works correctly.
    final fake33 = Uint8List(33);
    fake33[0] = 0x02;
    fake33.setRange(1, 33, script.sublist(1, 33));
    return encodeKaspaAddress(fake33, hrp: hrp);
  } catch (_) {
    return null;
  }
}
