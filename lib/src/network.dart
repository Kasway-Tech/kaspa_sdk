/// Kaspa network identifiers and per-network configuration constants.
library;

/// The Kaspa network to connect to.
enum KaspaNetwork {
  /// The Kaspa main network (real KAS).
  mainnet,

  /// Kaspa testnet-10 (test KAS, no monetary value).
  testnet10,
}

/// Immutable configuration constants for a given [KaspaNetwork].
///
/// Use the pre-built [KaspaNetworkConfig.mainnet] and
/// [KaspaNetworkConfig.testnet10] constants, or call
/// [KaspaNetworkConfig.forNetwork] to look one up by enum value.
///
/// Example:
/// ```dart
/// final config = KaspaNetworkConfig.mainnet;
/// print(config.addressHrp);      // 'kaspa'
/// print(config.fallbackNodeUrl); // 'wss://rose.kaspa.green/...'
/// ```
class KaspaNetworkConfig {
  const KaspaNetworkConfig._({
    required this.network,
    required this.addressHrp,
    required this.fallbackNodeUrl,
    required this.resolverNetworkPath,
    required this.symbol,
    required this.explorerBaseUrl,
    required this.explorerAddressBaseUrl,
  });

  /// The network this config belongs to.
  final KaspaNetwork network;

  /// The human-readable part used in Kaspa cashaddr addresses.
  /// `'kaspa'` for mainnet, `'kaspatest'` for testnet-10.
  final String addressHrp;

  /// A hardcoded fallback wRPC WebSocket URL used when the resolver fails.
  final String fallbackNodeUrl;

  /// The network segment used in resolver HTTP paths (e.g. `'mainnet'`).
  final String resolverNetworkPath;

  /// Ticker symbol — `'KAS'` for mainnet, `'TKAS'` for testnet-10.
  final String symbol;

  /// Base URL for the block explorer transaction pages.
  final String explorerBaseUrl;

  /// Base URL for the block explorer address pages.
  final String explorerAddressBaseUrl;

  /// Configuration for the Kaspa main network.
  static const mainnet = KaspaNetworkConfig._(
    network: KaspaNetwork.mainnet,
    addressHrp: 'kaspa',
    fallbackNodeUrl: 'wss://rose.kaspa.green/kaspa/mainnet/wrpc/json',
    resolverNetworkPath: 'mainnet',
    symbol: 'KAS',
    explorerBaseUrl: 'https://kaspa.stream/transactions/',
    explorerAddressBaseUrl: 'https://kaspa.stream/addresses/',
  );

  /// Configuration for Kaspa testnet-10.
  static const testnet10 = KaspaNetworkConfig._(
    network: KaspaNetwork.testnet10,
    addressHrp: 'kaspatest',
    fallbackNodeUrl: 'wss://electron-10.kaspa.stream/kaspa/testnet-10/wrpc/json',
    resolverNetworkPath: 'testnet-10',
    symbol: 'TKAS',
    explorerBaseUrl: 'https://tn10.kaspa.stream/transactions/',
    explorerAddressBaseUrl: 'https://tn10.kaspa.stream/addresses/',
  );

  /// Returns the [KaspaNetworkConfig] for the given [network].
  static KaspaNetworkConfig forNetwork(KaspaNetwork network) =>
      network == KaspaNetwork.mainnet ? mainnet : testnet10;
}
