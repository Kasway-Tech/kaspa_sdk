/// High-level Kaspa wallet: mnemonic management, address derivation,
/// and transaction sending.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'address.dart';
import 'bip39.dart' as bip39;
import 'node_client.dart';
import 'signing.dart';
import 'transaction.dart';

/// A Kaspa wallet derived from a BIP39 mnemonic.
///
/// Holds the mnemonic, derived Kaspa address, and the private key needed for
/// signing. The private key is never exposed outside this object.
///
/// ## Example
///
/// ```dart
/// // Generate a new wallet
/// final wallet = KaspaWallet.generate();
/// print(wallet.mnemonic); // 'abandon ability ...'
/// print(wallet.address);  // 'kaspa:qp...'
///
/// // Restore from an existing mnemonic
/// final wallet2 = KaspaWallet.fromMnemonic('abandon ability ...');
///
/// // Send KAS
/// try {
///   final txId = await wallet2.sendTransaction(
///     nodeUrl: 'wss://node.kaspa.green/kaspa/mainnet/wrpc/json',
///     toAddress: 'kaspa:qrecipient...',
///     amountSompi: 100000000, // 1 KAS
///   );
///   print('Sent! txId: $txId');
/// } on InsufficientFundsException catch (e) {
///   print('Not enough funds: $e');
/// } on KaspaException catch (e) {
///   print('Error: $e');
/// }
/// ```
class KaspaWallet {
  KaspaWallet._({
    required this.mnemonic,
    required this.address,
    required Uint8List privateKey32,
  }) : _privateKey32 = privateKey32;

  /// The BIP39 mnemonic this wallet was derived from.
  final String mnemonic;

  /// The primary Kaspa cashaddr for this wallet (path m/44'/111111'/0'/0/0).
  final String address;

  final Uint8List _privateKey32;

  // ─────────────────────────────────────────────────────────────────────────
  // Factory constructors
  // ─────────────────────────────────────────────────────────────────────────

  /// Creates a [KaspaWallet] from an existing BIP39 mnemonic.
  ///
  /// Derives the key at path `m/44'/111111'/0'/0/0` (Kaspa coin type 111111).
  ///
  /// [hrp] sets the address prefix: `'kaspa'` for mainnet (default),
  /// `'kaspatest'` for testnet-10.
  ///
  /// Throws [ArgumentError] if the mnemonic is invalid.
  factory KaspaWallet.fromMnemonic(String mnemonic, {String hrp = 'kaspa'}) {
    final validation = validateMnemonic(mnemonic);
    if (!validation.valid) {
      throw ArgumentError(validation.error, 'mnemonic');
    }
    final seed = bip39.mnemonicToSeed(mnemonic);
    final derived = _bip32Derive(seed, "m/44'/111111'/0'/0/0");
    final address = encodeKaspaAddress(derived.publicKey, hrp: hrp);
    return KaspaWallet._(
      mnemonic: mnemonic,
      address: address,
      privateKey32: derived.privateKey,
    );
  }

  /// Generates a new random BIP39 mnemonic and derives a wallet from it.
  ///
  /// [wordCount] must be 12 (128-bit entropy) or 24 (256-bit entropy).
  /// [hrp] sets the address prefix.
  factory KaspaWallet.generate({int wordCount = 12, String hrp = 'kaspa'}) {
    final mnemonic = generateMnemonic(wordCount: wordCount);
    return KaspaWallet.fromMnemonic(mnemonic, hrp: hrp);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Static mnemonic utilities
  // ─────────────────────────────────────────────────────────────────────────

  /// Generates a BIP39 mnemonic phrase.
  ///
  /// [wordCount] must be 12 (128-bit entropy) or 24 (256-bit entropy).
  static String generateMnemonic({int wordCount = 12}) {
    final strength = wordCount == 24 ? 256 : 128;
    return bip39.generateMnemonic(strength: strength);
  }

  /// Validates a BIP39 mnemonic phrase.
  ///
  /// Returns a record `(valid, error)`. When `valid` is `true`, `error` is
  /// empty. When `valid` is `false`, `error` describes the problem.
  static ({bool valid, String error}) validateMnemonic(String phrase) {
    final words = phrase
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.length != 12 && words.length != 24) {
      return (
        valid: false,
        error: 'InvalidWordCount: must be 12 or 24 words, got ${words.length}',
      );
    }

    if (!bip39.validateMnemonic(phrase.trim())) {
      final wordRe = RegExp(r'^[a-z]+$');
      for (final w in words) {
        if (!wordRe.hasMatch(w)) {
          return (
            valid: false,
            error: 'InvalidWord: "$w" is not in the BIP39 word list',
          );
        }
      }
      return (
        valid: false,
        error: 'InvalidChecksum: mnemonic checksum verification failed',
      );
    }

    return (valid: true, error: '');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Transactions
  // ─────────────────────────────────────────────────────────────────────────

  /// Sends [amountSompi] sompi to [toAddress] via the Kaspa node at [nodeUrl].
  ///
  /// Returns the transaction ID on success.
  ///
  /// Throws:
  ///   - [InsufficientFundsException] if UTXOs cannot cover amount + fee.
  ///   - [MassLimitException] if the transaction is too large.
  ///   - [KaspaException] for connection, validation, or node errors.
  Future<String> sendTransaction({
    required String nodeUrl,
    required String toAddress,
    required int amountSompi,
  }) async {
    // Determine HRP from the wallet's own address
    final hrp = address.contains(':') ? address.split(':').first : 'kaspa';

    // Validate destination address HRP before making any network calls
    if (!toAddress.startsWith('$hrp:')) {
      throw KaspaException('Destination must be a valid $hrp: address');
    }

    final client = KaspaNodeClient(url: nodeUrl);
    try {
      final utxos = await client.getUtxosByAddresses([address]);
      final result = buildSignedTransaction(
        utxoEntries: utxos,
        fromPrivKey32: _privateKey32,
        fromAddress: address,
        toAddress: toAddress,
        amountSompi: amountSompi,
        hrp: hrp,
      );
      return await client.submitTransaction(result.transaction);
    } finally {
      await client.close();
    }
  }
}

// ─── BIP32 derivation (replaces the `bip32` package) ─────────────────────────

final _bip32n = BigInt.parse(
  'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
  radix: 16,
);

Uint8List _hmacSha512(List<int> key, List<int> data) =>
    Uint8List.fromList(Hmac(sha512, key).convert(data).bytes);

BigInt _bip32BytesToBigInt(Uint8List b) {
  var result = BigInt.zero;
  for (final byte in b) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bip32BigIntTo32(BigInt n) {
  final result = Uint8List(32);
  var temp = n;
  for (var i = 31; i >= 0; i--) {
    result[i] = (temp & BigInt.from(0xFF)).toInt();
    temp >>= 8;
  }
  return result;
}

class _Bip32Key {
  const _Bip32Key(this.key, this.chainCode);
  final Uint8List key;
  final Uint8List chainCode;
}

_Bip32Key _bip32Master(Uint8List seed) {
  final hmac = _hmacSha512('Bitcoin seed'.codeUnits, seed);
  return _Bip32Key(
    Uint8List.fromList(hmac.sublist(0, 32)),
    Uint8List.fromList(hmac.sublist(32)),
  );
}

_Bip32Key _bip32Child(_Bip32Key parent, int index) {
  final data = Uint8List(37);
  if (index >= 0x80000000) {
    // Hardened: 0x00 || key || ser32(index)
    data[0] = 0x00;
    data.setRange(1, 33, parent.key);
  } else {
    // Normal: serP(point(key)) || ser32(index)
    data.setRange(0, 33, privKeyToCompressedPubKey(parent.key));
  }
  data[33] = (index >> 24) & 0xFF;
  data[34] = (index >> 16) & 0xFF;
  data[35] = (index >> 8) & 0xFF;
  data[36] = index & 0xFF;

  final hmac = _hmacSha512(parent.chainCode, data);
  final il = Uint8List.fromList(hmac.sublist(0, 32));
  final ir = Uint8List.fromList(hmac.sublist(32));
  final childInt =
      (_bip32BytesToBigInt(il) + _bip32BytesToBigInt(parent.key)) % _bip32n;
  return _Bip32Key(_bip32BigIntTo32(childInt), ir);
}

({Uint8List publicKey, Uint8List privateKey}) _bip32Derive(
  Uint8List seed,
  String path,
) {
  var node = _bip32Master(seed);
  for (final seg in path.split('/').skip(1)) {
    final hardened = seg.endsWith("'");
    final idx =
        int.parse(hardened ? seg.substring(0, seg.length - 1) : seg);
    node = _bip32Child(node, hardened ? idx + 0x80000000 : idx);
  }
  return (
    publicKey: privKeyToCompressedPubKey(node.key),
    privateKey: node.key,
  );
}
