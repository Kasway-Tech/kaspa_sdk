// ignore_for_file: avoid_print

/// kaspa_sdk usage examples.
///
/// These examples demonstrate the main API surface.
/// Real network calls require a live Kaspa node.
library;

import 'package:kaspa_sdk/kaspa_sdk.dart';

Future<void> main() async {
  // ─── 1. Mnemonic operations ──────────────────────────────────────────────────

  print('=== Mnemonic ===');

  // Generate a new 12-word mnemonic
  final mnemonic = KaspaWallet.generateMnemonic();
  print('Generated: $mnemonic');

  // Validate a mnemonic
  final (:valid, :error) = KaspaWallet.validateMnemonic(mnemonic);
  print('Valid: $valid  Error: "$error"');

  // ─── 2. Wallet derivation ────────────────────────────────────────────────────

  print('\n=== Wallet ===');

  // Derive a wallet from an existing mnemonic (path m/44'/111111'/0'/0/0)
  final wallet = KaspaWallet.fromMnemonic(mnemonic);
  print('Address (mainnet):  ${wallet.address}');

  // Testnet-10 address uses a different HRP
  final testnetWallet = KaspaWallet.fromMnemonic(mnemonic, hrp: 'kaspatest');
  print('Address (testnet):  ${testnetWallet.address}');

  // ─── 3. Node discovery via resolver ─────────────────────────────────────────

  print('\n=== Node discovery ===');

  final resolver = KaspaResolverService();
  // Skipped in example to avoid requiring network access.
  // Uncomment to run against a live network:
  //
  // final nodeUrl = await resolver.resolve(KaspaNetwork.mainnet)
  //     ?? KaspaNetworkConfig.mainnet.fallbackNodeUrl;
  // print('Node URL: $nodeUrl');

  final nodeUrl = KaspaNetworkConfig.mainnet.fallbackNodeUrl;
  print('Using fallback node: $nodeUrl');
  print('(resolver not called in this example — requires network)');

  // ─── 4. Fetching UTXOs & balance ────────────────────────────────────────────

  print('\n=== UTXOs (requires live node) ===');

  // Uncomment to query a live node:
  //
  // final client = KaspaNodeClient(url: nodeUrl);
  // try {
  //   final utxos = await client.getUtxosByAddresses([wallet.address]);
  //   final totalKas = utxos.fold<double>(
  //     0, (sum, u) => sum + u.amountSompi / 1e8,
  //   );
  //   print('Balance: $totalKas KAS  (${utxos.length} UTXOs)');
  //
  //   final dagInfo = await client.getBlockDagInfo();
  //   print('DAA score: ${dagInfo.virtualDaaScore}');
  // } finally {
  //   await client.close();
  // }

  print('(skipped — requires network)');

  // ─── 5. Continuous balance monitoring ───────────────────────────────────────

  print('\n=== Balance stream (requires live node) ===');

  // Uncomment for real-time balance updates:
  //
  // final monitorClient = KaspaNodeClient(url: nodeUrl);
  // final sub = monitorClient.watchBalance(wallet.address).listen((kas) {
  //   print('Balance: $kas KAS');
  // });
  // await Future<void>.delayed(const Duration(seconds: 10));
  // await sub.cancel();
  // await monitorClient.close();

  print('(skipped — requires network)');

  // ─── 6. Sending a transaction ────────────────────────────────────────────────

  print('\n=== Send transaction (requires live node + funded wallet) ===');

  // Uncomment to send KAS:
  //
  // try {
  //   final txId = await wallet.sendTransaction(
  //     nodeUrl: nodeUrl,
  //     toAddress: 'kaspa:qrecipient...',
  //     amountSompi: 100000000, // 1 KAS
  //   );
  //   print('Sent! txId: $txId');
  //   print('Explorer: ${KaspaNetworkConfig.mainnet.explorerBaseUrl}$txId');
  // } on InsufficientFundsException catch (e) {
  //   print('Not enough funds: $e');
  // } on KaspaException catch (e) {
  //   print('Error: $e');
  // }

  print('(skipped — requires network and funded wallet)');

  // ─── 7. Low-level address utilities ─────────────────────────────────────────

  print('\n=== Address utilities ===');

  // Convert a compact SPK hex to an address
  // (This is how you map a UTXO scriptPublicKey back to its owner's address)
  final knownSpk = '000020'
      'b9a58a1b8b83e2e42a5a28d3a3b7c12f56e0d8f09a74cbb8f67d891234abc56'
      'ac';
  final spkAddress = scriptToAddress(knownSpk);
  print('SPK → address: ${spkAddress ?? "invalid"}');

  // Network config
  print('\n=== Network config ===');
  for (final network in KaspaNetwork.values) {
    final cfg = KaspaNetworkConfig.forNetwork(network);
    print('${cfg.symbol}: hrp=${cfg.addressHrp}  fallback=${cfg.fallbackNodeUrl}');
  }

  // Suppress unused variable warning
  resolver.toString();
}
