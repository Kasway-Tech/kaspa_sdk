/// Kaspa transaction building: UTXO selection, fee calculation, and signing.
library;
///
/// The mass calculation mirrors rusty-kaspa's generator and consensus logic:
///   - rusty-kaspa/wallet/core/src/tx/generator/generator.rs
///   - rusty-kaspa/wallet/core/src/tx/mass.rs
///
/// Consensus parameters (mainnet & testnet-10):
///   - mass_per_tx_byte              = 1
///   - mass_per_script_pub_key_byte  = 10
///   - mass_per_sig_op               = 1000
///   - STORAGE_MASS_PARAMETER  C     = 10^12  (KIP-0009)
///   - MINIMUM_RELAY_FEE             = 1 sompi/gram
///
/// Standard P2PK sizes (verified against node responses):
///   - sig_script = 66 bytes  (OP_DATA_65 + 64-byte Schnorr sig + SIG_HASH_ALL)
///   - SPK script = 34 bytes  (OP_DATA_32 + 32-byte x-only pubkey + OP_CHECKSIG)
///
/// Cross-checked:  1 input + 2 outputs → mass 2036  ✓
///                10 inputs + 1 output  → mass 11686 ✓

import 'dart:typed_data';

import 'package:hex/hex.dart';

import 'address.dart';
import 'models.dart';
import 'signing.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Exceptions
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all kaspa_sdk exceptions.
class KaspaException implements Exception {
  /// Creates a [KaspaException] with [message].
  const KaspaException(this.message);

  /// Human-readable error description.
  final String message;

  @override
  String toString() => 'KaspaException: $message';
}

/// Thrown when the available UTXOs cannot cover the requested amount plus fee.
class InsufficientFundsException extends KaspaException {
  /// Creates an [InsufficientFundsException].
  const InsufficientFundsException(super.message);
}

/// Thrown when the computed transaction mass exceeds the standard relay limit
/// (100 000 grams).
class MassLimitException extends KaspaException {
  /// Creates a [MassLimitException].
  const MassLimitException(super.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Mass calculation constants
// ─────────────────────────────────────────────────────────────────────────────

const _kStorageC = 1000000000000; // STORAGE_MASS_PARAMETER = 10^12
const _kMaxStandardMass = 100000;

/// Serialized byte size of a standard P2PK transaction with [n] inputs and [m] outputs.
///   base     = 94  (version u16 + n_inputs u64 + n_outputs u64 + locktime u64
///                   + subnetwork_id 20B + gas u64 + payload_hash 32B + payload_len u64)
///   input    = 118 (outpoint 36B + sig_script_len u64 + sig_script 66B + sequence u64)
///   output   = 52  (value u64 + spk_version u16 + spk_len u64 + spk_script 34B)
int p2pkTxSize(int n, int m) => 94 + 118 * n + 52 * m;

/// Compute mass for a transaction with [n] inputs and [m] outputs.
///   size × mass_per_tx_byte(1)
/// + Σ_outputs (spk_version(2) + spk_script(34)) × mass_per_spk_byte(10) = 360 per output
/// + Σ_inputs  sig_op_count(1) × mass_per_sig_op(1000) = 1000 per input
int computeMass(int n, int m) {
  final size = p2pkTxSize(n, m);
  return size + 360 * m + 1000 * n;
}

int _storageMassFromHarmonic(List<int> ins, int outputHarmonic) {
  final n = ins.length;
  if (n == 0) return outputHarmonic;
  final totalIn = ins.fold<int>(0, (s, a) => s + a);
  if (totalIn == 0) return outputHarmonic;
  // arithmetic mean: N × (C / (total/N)) = N² × C / total
  final harmIn = n * (_kStorageC ~/ (totalIn ~/ n));
  final diff = outputHarmonic - harmIn;
  return diff > 0 ? diff : 0;
}

bool _isDust(int value) => value < 600;

({int storageMass, bool absorb}) _massDisposition(
  List<int> ins,
  int changeEstimate,
  int recipientHarmonic,
  int computeWithChange,
) {
  // dust → always absorb
  if (_isDust(changeEstimate)) {
    return (
      storageMass: _storageMassFromHarmonic(ins, recipientHarmonic),
      absorb: true,
    );
  }

  final smWithChange = _storageMassFromHarmonic(
    ins,
    recipientHarmonic + _kStorageC ~/ changeEstimate,
  );

  // If storage mass is dominated by compute mass, no penalty
  if (smWithChange == 0 || smWithChange < computeWithChange) {
    return (storageMass: 0, absorb: false);
  }

  final smNoChange = _storageMassFromHarmonic(ins, recipientHarmonic);

  if (smWithChange < smNoChange) {
    // change output actually helps (unusual — e.g. rebalancing)
    return (storageMass: smWithChange, absorb: false);
  }

  // If the extra fee from keeping change > change value → absorb
  final diff =
      smWithChange > smNoChange ? smWithChange - smNoChange : 0;
  if (diff > changeEstimate) {
    return (storageMass: smNoChange, absorb: true);
  }

  return (storageMass: smWithChange, absorb: false);
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction result
// ─────────────────────────────────────────────────────────────────────────────

/// The result of building a signed Kaspa P2PK transaction.
class KaspaTransactionResult {
  /// Creates a [KaspaTransactionResult].
  const KaspaTransactionResult({
    required this.transaction,
    required this.feeSompi,
    required this.changeSompi,
    required this.inputCount,
  });

  /// The signed transaction map, ready to pass to a `submitTransaction` wRPC call.
  final Map<String, dynamic> transaction;

  /// The network fee paid, in sompi.
  final int feeSompi;

  /// The change amount returned to the sender, in sompi. Zero when absorbed.
  final int changeSompi;

  /// Number of UTXOs consumed as inputs.
  final int inputCount;
}

// ─────────────────────────────────────────────────────────────────────────────
// buildSignedTransaction
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a signed P2PK transaction ready for submission to a Kaspa node.
///
/// UTXO selection uses a 3-phase algorithm mirroring rusty-kaspa's generator:
///   1. Greedy selection until `total >= amount + compute_mass(n, 2)`
///   2. Fee convergence: iterate up to 5 times until fee stabilises
///   3. Extension: add more UTXOs if Phase 2 fee exceeds available funds
///
/// Parameters:
///   - [utxoEntries]: UTXOs for the sender's address (from `KaspaNodeClient.getUtxosByAddresses`).
///   - [fromPrivKey32]: 32-byte private key for signing (from BIP32 derivation).
///   - [fromAddress]: Sender's Kaspa cashaddr (used for the change output).
///   - [toAddress]: Recipient's Kaspa cashaddr.
///   - [amountSompi]: Amount to send in sompi (1 KAS = 10^8 sompi).
///   - [hrp]: Human-readable part of the network (default `'kaspa'`).
///
/// Throws:
///   - [InsufficientFundsException] if UTXOs cannot cover amount + fee.
///   - [MassLimitException] if transaction mass exceeds 100 000 grams.
///   - [KaspaException] if [toAddress] does not match [hrp].
KaspaTransactionResult buildSignedTransaction({
  required List<KaspaUtxoEntry> utxoEntries,
  required Uint8List fromPrivKey32,
  required String fromAddress,
  required String toAddress,
  required int amountSompi,
  String hrp = 'kaspa',
}) {
  if (!toAddress.startsWith('$hrp:')) {
    throw KaspaException(
      'Destination must be a valid $hrp: address',
    );
  }

  final int recipientHarmonic = _kStorageC ~/ amountSompi;

  // Run the mass-disposition convergence for the current input set.
  ({int fee, bool absorb}) converge(List<int> ins, int total) {
    var fee = computeMass(ins.length, 2);
    var absorb = false;
    for (var i = 0; i < 5; i++) {
      final changeEst = total - amountSompi; // rusty-kaspa: before fees
      if (changeEst <= 0) {
        absorb = true;
        fee = computeMass(ins.length, 1);
        break;
      }
      final computeWith = computeMass(ins.length, 2);
      final (:storageMass, absorb: absorbNow) = _massDisposition(
        ins,
        changeEst,
        recipientHarmonic,
        computeWith,
      );
      absorb = absorbNow;
      final numOut = absorbNow ? 1 : 2;
      final cm = computeMass(ins.length, numOut);
      final txMass = cm > storageMass ? cm : storageMass;
      if (txMass == fee) break;
      fee = txMass;
    }
    return (fee: fee, absorb: absorb);
  }

  // Phase 1 — greedy selection
  final selectedUtxos = <KaspaUtxoEntry>[];
  final inputAmounts = <int>[];
  var totalInput = 0;
  for (final entry in utxoEntries) {
    selectedUtxos.add(entry);
    inputAmounts.add(entry.amountSompi);
    totalInput += entry.amountSompi;
    if (totalInput >= amountSompi + computeMass(selectedUtxos.length, 2)) {
      break;
    }
  }

  // Phase 2 — fee convergence
  var (:fee, :absorb) = converge(inputAmounts, totalInput);

  // Phase 3 — extend if still short
  if (totalInput < amountSompi + fee) {
    for (final entry in utxoEntries.skip(selectedUtxos.length)) {
      selectedUtxos.add(entry);
      inputAmounts.add(entry.amountSompi);
      totalInput += entry.amountSompi;
      (fee: fee, absorb: absorb) = converge(inputAmounts, totalInput);
      if (totalInput >= amountSompi + fee) break;
    }
  }

  final feeSompi = fee;
  final absorbChange = absorb;
  final changeSompi = totalInput - amountSompi - feeSompi;

  if (changeSompi < 0) {
    throw InsufficientFundsException(
      'Insufficient funds: have $totalInput sompi, '
      'need ${amountSompi + feeSompi} sompi',
    );
  }

  if (feeSompi > _kMaxStandardMass) {
    throw MassLimitException(
      'Transaction mass too high ($feeSompi > $_kMaxStandardMass). '
      'The send amount may be too small relative to your UTXO sizes.',
    );
  }

  final includeChange =
      !absorbChange && changeSompi > 0 && !_isDust(changeSompi);

  // ── Build output descriptors ──────────────────────────────────────────────
  final toScriptHex = addressToP2pkScript(toAddress);
  final ourScriptHex = addressToP2pkScript(fromAddress);

  final kaspaOutputs = <KaspaOutput>[
    KaspaOutput(
      value: amountSompi,
      scriptVersion: 0,
      script: Uint8List.fromList(HEX.decode(toScriptHex)),
    ),
  ];
  if (includeChange) {
    kaspaOutputs.add(KaspaOutput(
      value: changeSompi,
      scriptVersion: 0,
      script: Uint8List.fromList(HEX.decode(ourScriptHex)),
    ));
  }

  // ── Build input descriptors for signing ───────────────────────────────────
  final txIds = <String>[];
  final outpointIndices = <int>[];
  final kaspaUtxos = <KaspaUtxo>[];

  for (final entry in selectedUtxos) {
    txIds.add(entry.transactionId);
    outpointIndices.add(entry.index);
    kaspaUtxos.add(entry.toKaspaUtxo());
  }

  // ── Sign each input with BIP340 Schnorr ──────────────────────────────────
  final signedInputs = <Map<String, dynamic>>[];
  for (var i = 0; i < txIds.length; i++) {
    final sigHash = calcKaspaSigHash(
      txVersion: 0,
      txIds: txIds,
      indices: outpointIndices,
      utxos: kaspaUtxos,
      outputs: kaspaOutputs,
      inputIndex: i,
    );
    final sig64 = kaspaSchnorrSign(fromPrivKey32, sigHash);
    final sigScriptHex = HEX.encode(buildP2pkSigScript(sig64));
    signedInputs.add({
      'previousOutpoint': {
        'transactionId': txIds[i],
        'index': outpointIndices[i],
      },
      'signatureScript': sigScriptHex,
      'sequence': 0,
      'sigOpCount': 1,
    });
  }

  // ── Assemble transaction ──────────────────────────────────────────────────
  final outputs = kaspaOutputs
      .map((o) => {
            'value': o.value,
            'scriptPublicKey': '0000${HEX.encode(o.script)}',
          })
      .toList();

  final transaction = <String, dynamic>{
    'version': 0,
    'inputs': signedInputs,
    'outputs': outputs,
    'lockTime': 0,
    'subnetworkId': '0000000000000000000000000000000000000000',
    'gas': 0,
    'payload': '',
    'mass': 0,
  };

  return KaspaTransactionResult(
    transaction: transaction,
    feeSompi: feeSompi,
    changeSompi: includeChange ? changeSompi : 0,
    inputCount: selectedUtxos.length,
  );
}
