import '../rpc/rpc_client.dart';
import 'get_nft_mint.dart';

/// Parameters for getting NFT owner
class GetNftOwnerParams {
  const GetNftOwnerParams({
    required this.rpc,
    required this.domainAddress,
  });

  /// The RPC client for blockchain interaction
  final RpcClient rpc;

  /// The domain address whose NFT owner is to be retrieved
  final String domainAddress;
}

/// Token account information
class TokenAccountInfo {
  const TokenAccountInfo({
    required this.amount,
    required this.owner,
  });

  /// Token amount
  final String amount;

  /// Token owner address
  final String owner;
}

/// Retrieves the owner of a tokenized domain.
///
/// This matches js-kit/src/nft/getNftOwner.ts
///
/// [params] - Parameters containing RPC client and domain address
///
/// Returns the NFT owner's address, or null if no owner is found
Future<String?> getNftOwner(GetNftOwnerParams params) async {
  try {
    final mint = await getNftMint(GetNftMintParams(
      domainAddress: params.domainAddress,
    ));

    final largestAccounts = await params.rpc.getTokenLargestAccounts(mint);

    if (largestAccounts.isEmpty) {
      return null;
    }

    final largestAccountInfo = await params.rpc.fetchEncodedAccount(
      largestAccounts.first.address,
    );

    if (!largestAccountInfo.exists) {
      return null;
    }

    final decoded = _decodeTokenAccount(largestAccountInfo.data);
    if (decoded.amount == '1') {
      return decoded.owner;
    }

    return null;
  } on Exception catch (e) {
    // If invalid params or other RPC error, return null
    return null;
  }
}

/// Simplified token account decoder
TokenAccountInfo _decodeTokenAccount(List<int> data) {
  // This is a simplified implementation
  // In a full implementation, you'd properly decode the token account structure

  if (data.length < 72) {
    throw ArgumentError('Invalid token account data');
  }

  // Extract owner (bytes 32-64)
  final ownerBytes = data.sublist(32, 64);
  final owner = _base58Encode(ownerBytes);

  // Extract amount (bytes 64-72, little-endian u64)
  var amount = 0;
  for (var i = 0; i < 8; i++) {
    amount |= data[64 + i] << (i * 8);
  }

  return TokenAccountInfo(
    amount: amount.toString(),
    owner: owner,
  );
}

/// Base58 encode helper
String _base58Encode(List<int> input) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  if (input.isEmpty) return '';

  // Count leading zeros
  var leadingZeros = 0;
  for (var i = 0; i < input.length; i++) {
    if (input[i] == 0) {
      leadingZeros++;
    } else {
      break;
    }
  }

  // Convert to BigInt
  var value = BigInt.zero;
  for (var i = 0; i < input.length; i++) {
    value = value * BigInt.from(256) + BigInt.from(input[i]);
  }

  // Encode to base58
  final result = <String>[];
  final base = BigInt.from(58);

  while (value > BigInt.zero) {
    final remainder = (value % base).toInt();
    result.insert(0, alphabet[remainder]);
    value = value ~/ base;
  }

  // Add leading ones for leading zeros
  for (var i = 0; i < leadingZeros; i++) {
    result.insert(0, '1');
  }

  return result.join();
}
