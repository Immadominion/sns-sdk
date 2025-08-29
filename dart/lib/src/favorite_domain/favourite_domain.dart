import 'dart:typed_data';

import '../rpc/rpc_client.dart';
import '../utils/get_domain_key_sync.dart';

/// The Name Offers program ID for favorite domains
const String nameOffersId = '85iDfUvr3HJyLM2zcq5BXSiDvUfw6cSE1FfNBo8Ap29';

/// Favorite domain state class
///
/// This mirrors js/src/favorite-domain.ts FavouriteDomain class
class FavouriteDomain {
  const FavouriteDomain({
    required this.tag,
    required this.nameAccount,
  });
  final int tag;
  final String nameAccount;

  /// Borsh schema definition
  static const Map<String, dynamic> schema = {
    'struct': {
      'tag': 'u8',
      'nameAccount': {
        'array': {'type': 'u8', 'len': 32}
      },
    }
  };

  /// Deserialize buffer data into a FavouriteDomain object
  ///
  /// [data] - The buffer to deserialize
  ///
  /// Returns a FavouriteDomain object
  static FavouriteDomain deserialize(Uint8List data) {
    if (data.length < 33) {
      throw Exception('Insufficient data for FavouriteDomain');
    }

    // Read tag (1 byte)
    final tag = data[0];

    // Read name account (32 bytes)
    final nameAccountBytes = data.sublist(1, 33);
    final nameAccount = _bytesToBase58(nameAccountBytes);

    return FavouriteDomain(
      tag: tag,
      nameAccount: nameAccount,
    );
  }

  /// Retrieve and deserialize a favorite domain
  ///
  /// [connection] - The Solana RPC connection object
  /// [key] - The favorite account key
  ///
  /// Returns a FavouriteDomain object
  /// Throws Exception if the account does not exist
  static Future<FavouriteDomain> retrieve(
    RpcClient connection,
    String key,
  ) async {
    final accountInfo = await connection.fetchEncodedAccount(key);
    if (!accountInfo.exists || accountInfo.data.isEmpty) {
      throw Exception('FavouriteDomain not found for key: $key');
    }
    return deserialize(Uint8List.fromList(accountInfo.data));
  }

  /// Derive the key of a favorite domain
  ///
  /// [programId] - The name offer program ID
  /// [owner] - The owner to retrieve the favorite domain for
  ///
  /// Returns a DomainKeyResult with the favorite domain key
  static Future<DomainKeyResult> getKeySync(
      String programId, String owner) async {
    // Create a simple seed based approach
    final seedString = 'favourite_domain_$owner';
    final hashedSeed = getHashedNameSync(seedString);

    // Use existing name account key derivation with the seed
    final keyString = await getNameAccountKeySync(
      hashedSeed,
      nameClass: programId,
    );

    return DomainKeyResult(
      pubkey: keyString,
      hashed: hashedSeed,
      isSub: false,
    );
  }

  /// Find favorite domains with a specific owner
  ///
  /// [connection] - The RPC connection
  /// [owner] - The owner to search for
  ///
  /// Returns a list of favorite domain keys for the owner
  static Future<List<String>> findWithOwner(
    RpcClient connection,
    String owner,
  ) async {
    final favKey = await getKeySync(nameOffersId, owner);

    try {
      await retrieve(connection, favKey.pubkey);
      return [favKey.pubkey];
    } on Exception catch (e) {
      // No favorite domain found for this owner
      return [];
    }
  }

  /// Retrieve multiple favorite domains
  ///
  /// [connection] - The RPC connection
  /// [keys] - List of favorite domain keys to retrieve
  ///
  /// Returns a list of FavouriteDomain objects (null for missing accounts)
  static Future<List<FavouriteDomain?>> retrieveMultiple(
    RpcClient connection,
    List<String> keys,
  ) async {
    final results = <FavouriteDomain?>[];

    for (final key in keys) {
      try {
        final domain = await retrieve(connection, key);
        results.add(domain);
      } on Exception catch (e) {
        results.add(null);
      }
    }

    return results;
  }

  /// Convert bytes to base58 string (placeholder implementation)
  static String _bytesToBase58(Uint8List bytes) {
    // This is a placeholder - proper implementation would encode to base58
    return 'placeholder_${bytes.length}';
  }
}

/// Alias for FavouriteDomain
typedef PrimaryDomain = FavouriteDomain;
