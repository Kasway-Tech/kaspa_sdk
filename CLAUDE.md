# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
dart test                        # run all tests
dart test test/wallet_test.dart  # run a single test file
dart analyze                     # lint
```

## Architecture

Pure-Dart SDK for the Kaspa blockchain. No Flutter dependency, no FFI, no native code — works in Flutter apps, Dart CLI, and Dart servers (not web, due to WebSocket constraints).

**Public API:** `lib/kaspa_sdk.dart` is the single barrel export. All implementation lives in `lib/src/`.

### Modules

| File | Responsibility |
|------|---------------|
| `models.dart` | Immutable data models: `KaspaUtxo`, `KaspaOutput`, `KaspaUtxoEntry`, `KaspaBlockDagInfo` |
| `network.dart` | `KaspaNetwork` enum + `KaspaNetworkConfig` constants (mainnet / testnet-10) |
| `address.dart` | Kaspa cashaddr codec — encode/decode, P2PK script ↔ address conversion |
| `signing.dart` | BIP340 Schnorr signing (deterministic, all-zero aux), BLAKE2b-256 sighash |
| `transaction.dart` | 3-phase UTXO selection + fee/mass calculation mirroring rusty-kaspa's generator |
| `wallet.dart` | High-level wallet: mnemonic generation, BIP32 key derivation, `sendTransaction()` |
| `node_client.dart` | wRPC JSON-RPC over WebSocket — one-shot requests + streaming balance watcher |
| `resolver.dart` | Node discovery via 16 public resolver nodes; returns least-loaded wRPC URL |

### Key design points

- **Derivation path:** `m/44'/111111'/0'/0/0` (Kaspa coin type 111111)
- **Address format:** `<hrp>:<base32>` — HRP is `kaspa` (mainnet) or `kaspatest` (testnet-10)
- **Sighash:** BLAKE2b-256 keyed with `"TransactionSigningHash"`, SIG_HASH_ALL only
- **Signature script:** `OP_DATA_65 (0x41) || sig64 || 0x01` (66 bytes)
- **Mass formula:** `size×1 + outputs×360 + inputs×1000 + storage_mass`; storage mass uses KIP-0009 harmonic mean; dust threshold is 600 sompi
- **`KaspaNodeClient` testing:** inject a `WebSocketFactory` to mock the WebSocket without a mocking library

### Lint config

`analysis_options.yaml` enables strict mode (`strict-casts`, `strict-inference`, `strict-raw-types`) and enforces `prefer_single_quotes`, `always_declare_return_types`, `unawaited_futures`, among others.
