/// Kaspa public resolver network — discovers the least-loaded wRPC node.
library;
///
/// The resolver network consists of 16 public nodes that each expose a simple
/// HTTP API returning the WebSocket URL of a Kaspa full node.
///
/// Route: `GET /v2/kaspa/:network/tls/wrpc/json`
/// Response: `{"uid": "...", "url": "wss://..."}`

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'network.dart';

/// Queries the Kaspa public resolver network to discover the least-loaded
/// available wRPC node for the requested network.
///
/// Example:
/// ```dart
/// final resolver = KaspaResolverService();
/// final url = await resolver.resolve(KaspaNetwork.mainnet);
/// if (url != null) {
///   print('Connecting to $url');
/// } else {
///   // fall back to KaspaNetworkConfig.mainnet.fallbackNodeUrl
/// }
/// ```
class KaspaResolverService {
  /// Creates a [KaspaResolverService].
  ///
  /// Pass [overrideNodes] in tests to bypass the default resolver list.
  KaspaResolverService({this.overrideNodes});

  /// Inject a custom list of base URLs for testing (bypasses [_resolverNodes]).
  @visibleForTesting
  final List<String>? overrideNodes;

  static const List<String> _resolverNodes = [
    'https://eric.kaspa.stream',
    'https://maxim.kaspa.stream',
    'https://sean.kaspa.stream',
    'https://troy.kaspa.stream',
    'https://john.kaspa.red',
    'https://mike.kaspa.red',
    'https://paul.kaspa.red',
    'https://alex.kaspa.red',
    'https://jake.kaspa.green',
    'https://mark.kaspa.green',
    'https://adam.kaspa.green',
    'https://liam.kaspa.green',
    'https://noah.kaspa.blue',
    'https://ryan.kaspa.blue',
    'https://jack.kaspa.blue',
    'https://luke.kaspa.blue',
  ];

  String _pathFor(KaspaNetwork network) {
    final net = KaspaNetworkConfig.forNetwork(network).resolverNetworkPath;
    return '/v2/kaspa/$net/tls/wrpc/json';
  }

  /// Shuffles resolver nodes and tries each in order, returning the first
  /// `url` value from a successful 200 response.
  ///
  /// Returns `null` if all resolvers fail or return unusable responses within
  /// the given [timeout]. In that case, callers should fall back to
  /// [KaspaNetworkConfig.fallbackNodeUrl].
  Future<String?> resolve(
    KaspaNetwork network, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final nodes = List<String>.from(overrideNodes ?? _resolverNodes)..shuffle();
    final path = _pathFor(network);

    for (final node in nodes) {
      try {
        final client = HttpClient();
        final req =
            await client.getUrl(Uri.parse('$node$path')).timeout(timeout);
        final resp = await req.close().timeout(timeout);
        if (resp.statusCode != 200) {
          client.close();
          continue;
        }
        final body =
            await resp.transform(utf8.decoder).join().timeout(timeout);
        client.close();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final url = json['url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
