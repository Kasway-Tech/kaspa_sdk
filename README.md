# kaspa_sdk

A pure-Dart SDK for the [Kaspa](https://kaspa.org) cryptocurrency.

Supports wallet generation, address derivation, transaction signing and submission, UTXO management, and real-time balance monitoring — with no Flutter dependency.

---

## Features

- **BIP39 mnemonic** generation and validation
- **BIP32 address derivation** at path `m/44'/111111'/0'/0/0`
- **Kaspa cashaddr** encoding and decoding
- **Transaction building & signing** — pure-Dart UTXO selection with fee convergence, BIP340 Schnorr signing, and BLAKE2b-256 sighash (KIP-9 storage mass)
- **wRPC node client** — JSON-RPC over WebSocket (`getUtxosByAddresses`, `submitTransaction`, `getBlockDagInfo`, and continuous balance stream)
- **Automatic node discovery** via the Kaspa public resolver network
- **Mainnet and testnet-10** support

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  kaspa_sdk: ^0.1.0
```

---

## Quick Start

```dart
import 'package:kaspa_sdk/kaspa_sdk.dart';

// Generate a new wallet
final wallet = KaspaWallet.generate();
print(wallet.address); // kaspa:qp...

// Or restore from a mnemonic
final existing = KaspaWallet.fromMnemonic('abandon ability ...');
```

---

## Node Discovery

```dart
final resolver = KaspaResolverService();
final nodeUrl = await resolver.resolve(KaspaNetwork.mainnet)
    ?? KaspaNetworkConfig.mainnet.fallbackNodeUrl;
```

The resolver queries 16 public nodes and returns the least-loaded one. Falls back to a hardcoded URL if all resolvers are unavailable.

---

## Fetching Balance

```dart
final client = KaspaNodeClient(url: nodeUrl);

// One-shot fetch
final utxos = await client.getUtxosByAddresses([wallet.address]);
final totalKas = utxos.fold<double>(0, (s, u) => s + u.amountSompi / 1e8);
print('Balance: $totalKas KAS');

await client.close();
```

---

## Continuous Balance Monitoring

```dart
final client = KaspaNodeClient(url: nodeUrl);

final sub = client.watchBalance(wallet.address).listen((kas) {
  print('Balance: $kas KAS');
});

// When done
await sub.cancel();
await client.close();
```

`watchBalance` manages a persistent WebSocket connection internally and auto-reconnects on errors.

---

## Sending a Transaction

```dart
try {
  final txId = await wallet.sendTransaction(
    nodeUrl: nodeUrl,
    toAddress: 'kaspa:qrecipient...',
    amountSompi: 100000000, // 1 KAS = 10^8 sompi
  );
  print('Sent! txId: $txId');
  print('Explorer: ${KaspaNetworkConfig.mainnet.explorerBaseUrl}$txId');
} on InsufficientFundsException catch (e) {
  print('Not enough funds: $e');
} on KaspaException catch (e) {
  print('Transaction error: $e');
}
```

---

## Confirmation Counting

Use `getBlockDagInfo` to track confirmations after a payment:

```dart
final client = KaspaNodeClient(url: nodeUrl);

// Record the DAA score when payment was detected
final detected = await client.getBlockDagInfo();
final detectedDaa = detected.virtualDaaScore;

// Later, poll for current score
final current = await client.getBlockDagInfo();
final confirmations = current.virtualDaaScore - detectedDaa;
print('Confirmations: $confirmations');

await client.close();
```

---

## Testnet-10

```dart
// Derive a testnet address
final testWallet = KaspaWallet.fromMnemonic(mnemonic, hrp: 'kaspatest');
print(testWallet.address); // kaspatest:qp...

// Find a testnet node
final testUrl = await KaspaResolverService().resolve(KaspaNetwork.testnet10)
    ?? KaspaNetworkConfig.testnet10.fallbackNodeUrl;
```

---

## Low-Level API

For advanced use cases, all cryptographic primitives are exported:

```dart
import 'package:kaspa_sdk/kaspa_sdk.dart';

// Schnorr signing
final sig = kaspaSchnorrSign(privKey32, msgHash32);

// Sighash
final hash = calcKaspaSigHash(
  txVersion: 0,
  txIds: [txId],
  indices: [0],
  utxos: [utxo],
  outputs: [output],
  inputIndex: 0,
);

// Build a transaction without sending
final result = buildSignedTransaction(
  utxoEntries: utxos,
  fromPrivKey32: privKey32,
  fromAddress: 'kaspa:qsender...',
  toAddress: 'kaspa:qrecipient...',
  amountSompi: 100000000,
);
// result.transaction is ready for submitTransaction
```

---

## Network Configuration

```dart
final cfg = KaspaNetworkConfig.mainnet;
print(cfg.addressHrp);             // 'kaspa'
print(cfg.fallbackNodeUrl);        // 'wss://rose.kaspa.green/...'
print(cfg.symbol);                 // 'KAS'
print(cfg.explorerBaseUrl);        // 'https://kaspa.stream/transactions/'
```

---

## Platform Support

Works on all platforms that support `dart:io`:

| Platform | Supported |
|---|---|
| Flutter (iOS, Android, macOS, Windows, Linux) | ✅ |
| Dart CLI | ✅ |
| Dart server (shelf, etc.) | ✅ |
| Flutter Web / Dart Web | ❌ (requires `dart:io`) |

---

## Security

- Private keys are derived in memory only and never stored by this package.
- Signing is deterministic (BIP340 with all-zero aux randomness) — no random number generator dependency for signing.
- Mnemonic validation uses BIP39 checksum verification.
- No native code, FFI, or platform channels — entirely pure Dart.

---

## References

- [Kaspa documentation](https://kaspa.org)
- [rusty-kaspa](https://github.com/kaspanet/rusty-kaspa) — the reference node implementation
- [KIP-0009](https://github.com/kaspanet/kips/blob/main/kip-0009.md) — storage mass formula
- [BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki) — mnemonic generation
- [BIP-32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki) — hierarchical key derivation
- [BIP-340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki) — Schnorr signatures
