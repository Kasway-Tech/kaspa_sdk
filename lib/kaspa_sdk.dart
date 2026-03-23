/// Kaspa SDK for Dart — wallet, signing, UTXO management, and node client.
///
/// ## Quick start
///
/// ```dart
/// import 'package:kaspa_sdk/kaspa_sdk.dart';
///
/// // Generate a new wallet
/// final wallet = KaspaWallet.generate();
/// print(wallet.address); // 'kaspa:qp...'
///
/// // Find a node automatically
/// final resolver = KaspaResolverService();
/// final nodeUrl = await resolver.resolve(KaspaNetwork.mainnet)
///     ?? KaspaNetworkConfig.mainnet.fallbackNodeUrl;
///
/// // Watch balance
/// final client = KaspaNodeClient(url: nodeUrl);
/// client.watchBalance(wallet.address).listen((kas) {
///   print('Balance: $kas KAS');
/// });
/// ```
library;

export 'src/network.dart' show KaspaNetwork, KaspaNetworkConfig;
export 'src/models.dart'
    show KaspaUtxo, KaspaOutput, KaspaUtxoEntry, KaspaBlockDagInfo;
export 'src/signing.dart'
    show kaspaSchnorrSign, calcKaspaSigHash, parseCompactSpk, buildP2pkSigScript;
export 'src/address.dart'
    show
        kaspaCharset,
        encodeKaspaAddress,
        decodeKaspaAddress,
        addressToP2pkScript,
        scriptToAddress;
export 'src/transaction.dart'
    show
        KaspaException,
        InsufficientFundsException,
        MassLimitException,
        KaspaTransactionResult,
        buildSignedTransaction;
export 'src/wallet.dart' show KaspaWallet;
export 'src/node_client.dart' show KaspaNodeClient;
export 'src/resolver.dart' show KaspaResolverService;
