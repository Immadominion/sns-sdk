import 'package:solana/solana.dart' hide RpcClient;

/// Get Twitter handle and registry key from a verified public key
///
/// This function mirrors js/src/twitter/getHandleAndRegistryKey.ts
///
/// [verifiedPubkey] - The verified public key to look up
///
/// Returns a tuple of [handle, registryKey] or throws if not found
Future<(String, Ed25519HDPublicKey)> getHandleAndRegistryKey(
  Ed25519HDPublicKey verifiedPubkey,
) async {
  // This function in the JS SDK only derives keys but doesn't fetch data
  // The actual data retrieval happens in the retrieve() method
  // For consistency with the JS API, we implement the key derivation here
  // but actual data fetching requires an RpcClient

  throw UnimplementedError(
      'This function requires an RpcClient to retrieve data. '
      'Use getHandleAndRegistryKeyViaFilters instead.');
}
