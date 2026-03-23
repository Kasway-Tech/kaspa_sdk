# Changelog

## 0.1.0

Initial release.

- `KaspaWallet` — BIP39 mnemonic generation/validation, BIP32 address derivation (m/44'/111111'/0'/0/0), and transaction sending.
- `KaspaNodeClient` — wRPC JSON-RPC client with one-shot calls (`getUtxosByAddresses`, `submitTransaction`, `getBlockDagInfo`) and continuous balance monitoring via `watchBalance`.
- `KaspaResolverService` — automatic node discovery via the Kaspa public resolver network (16 nodes across 4 domains).
- `KaspaNetworkConfig` — per-network constants (mainnet and testnet-10).
- Low-level exports: `kaspaSchnorrSign`, `calcKaspaSigHash`, `buildP2pkSigScript`, `parseCompactSpk`, `encodeKaspaAddress`, `decodeKaspaAddress`, `scriptToAddress`, `buildSignedTransaction`.
- Typed exceptions: `KaspaException`, `InsufficientFundsException`, `MassLimitException`.
- Pure Dart — no Flutter dependency; compatible with Flutter, Dart CLI, and server applications.
