import 'dart:typed_data';

import 'package:hex/hex.dart';

/// Info about a UTXO being spent (used by the sighash calculator).
class KaspaUtxo {
  /// Creates a [KaspaUtxo] with the given fields.
  const KaspaUtxo({
    required this.amount,
    required this.scriptVersion,
    required this.script,
  });

  /// Value of this UTXO in sompi (1 KAS = 10^8 sompi).
  final int amount;

  /// Script version (u16, typically 0 for P2PK).
  final int scriptVersion;

  /// Raw script bytes (34 bytes for a standard P2PK script).
  final Uint8List script;
}

/// Info about a transaction output being created.
class KaspaOutput {
  /// Creates a [KaspaOutput] with the given fields.
  const KaspaOutput({
    required this.value,
    required this.scriptVersion,
    required this.script,
  });

  /// Value of this output in sompi.
  final int value;

  /// Script version (0 for P2PK).
  final int scriptVersion;

  /// Raw script bytes (34-byte P2PK script).
  final Uint8List script;
}

/// A parsed UTXO entry as returned by the node's `getUtxosByAddresses` method.
///
/// Example raw JSON entry:
/// ```json
/// {
///   "outpoint": {"transactionId": "ab12...", "index": 0},
///   "utxoEntry": {
///     "amount": "100000000",
///     "scriptPublicKey": "000020<32-byte-pubkey>ac",
///     "blockDaaScore": "12345678",
///     "isCoinbase": false
///   }
/// }
/// ```
class KaspaUtxoEntry {
  /// Creates a [KaspaUtxoEntry].
  const KaspaUtxoEntry({
    required this.transactionId,
    required this.index,
    required this.amountSompi,
    required this.scriptPublicKey,
    required this.blockDaaScore,
    required this.isCoinbase,
  });

  /// The transaction ID of the outpoint (hex string).
  final String transactionId;

  /// The output index within that transaction.
  final int index;

  /// Amount in sompi (parsed from the string field in the JSON response).
  final int amountSompi;

  /// Compact scriptPublicKey hex (format: `"VVVV{script_hex}"`).
  final String scriptPublicKey;

  /// The DAA score of the block that confirmed this UTXO.
  final int blockDaaScore;

  /// Whether this UTXO is from a coinbase transaction.
  final bool isCoinbase;

  /// Parses a raw JSON entry as returned by `getUtxosByAddresses`.
  factory KaspaUtxoEntry.fromJson(Map<String, dynamic> json) {
    final outpoint = (json['outpoint'] as Map<String, dynamic>?) ?? {};
    final utxoEntry = (json['utxoEntry'] as Map<String, dynamic>?) ?? {};
    return KaspaUtxoEntry(
      transactionId: (outpoint['transactionId'] as String?) ?? '',
      index: ((outpoint['index'] as num?)?.toInt()) ?? 0,
      amountSompi:
          int.tryParse((utxoEntry['amount']?.toString()) ?? '0') ?? 0,
      scriptPublicKey: (utxoEntry['scriptPublicKey'] as String?) ?? '',
      blockDaaScore:
          int.tryParse((utxoEntry['blockDaaScore']?.toString()) ?? '0') ?? 0,
      isCoinbase: (utxoEntry['isCoinbase'] as bool?) ?? false,
    );
  }

  /// Converts to the [KaspaUtxo] format required by the sighash calculator.
  KaspaUtxo toKaspaUtxo() {
    final bytes = Uint8List.fromList(HEX.decode(scriptPublicKey));
    final version = bytes.length >= 2 ? (bytes[0] | (bytes[1] << 8)) : 0;
    final script =
        bytes.length >= 2 ? Uint8List.fromList(bytes.sublist(2)) : Uint8List(0);
    return KaspaUtxo(
      amount: amountSompi,
      scriptVersion: version,
      script: script,
    );
  }
}

/// DAG info returned by the node's `getBlockDagInfo` method.
class KaspaBlockDagInfo {
  /// Creates a [KaspaBlockDagInfo].
  const KaspaBlockDagInfo({
    required this.virtualDaaScore,
    required this.networkName,
    required this.blockCount,
    required this.headerCount,
  });

  /// The current virtual DAA score (used for confirmation counting).
  final int virtualDaaScore;

  /// The network name string as reported by the node (e.g. `'kaspa-mainnet'`).
  final String networkName;

  /// Total number of blocks in the DAG.
  final int blockCount;

  /// Total number of headers in the DAG.
  final int headerCount;

  /// Parses the `params` map from a `getBlockDagInfo` response.
  factory KaspaBlockDagInfo.fromJson(Map<String, dynamic> json) {
    return KaspaBlockDagInfo(
      virtualDaaScore:
          int.tryParse((json['virtualDaaScore']?.toString()) ?? '0') ?? 0,
      networkName: (json['networkName'] as String?) ?? '',
      blockCount:
          int.tryParse((json['blockCount']?.toString()) ?? '0') ?? 0,
      headerCount:
          int.tryParse((json['headerCount']?.toString()) ?? '0') ?? 0,
    );
  }
}
