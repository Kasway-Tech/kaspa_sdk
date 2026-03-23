/// High-level Kaspa wallet: mnemonic management, address derivation,
/// and transaction sending.
library;

import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;

import 'address.dart';
import 'node_client.dart';
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
    final root = bip32.BIP32.fromSeed(seed);
    final child = root.derivePath("m/44'/111111'/0'/0/0");
    final address = encodeKaspaAddress(child.publicKey, hrp: hrp);
    return KaspaWallet._(
      mnemonic: mnemonic,
      address: address,
      privateKey32: child.privateKey!,
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
