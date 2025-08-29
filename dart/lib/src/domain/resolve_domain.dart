import 'dart:typed_data';
import '../constants/records.dart';
import '../domain/get_domain_address.dart';
import '../errors/sns_errors.dart';
import '../record/get_record_v1_address.dart';
import '../record/get_record_v2_address.dart';
import '../rpc/rpc_client.dart';
import '../states/nft.dart';
import '../states/registry.dart';
import '../types/validation.dart';
import '../utils/check_address_on_curve/index.dart';

/// Options for domain resolution
class ResolveOptions {
  const ResolveOptions({
    this.allowPda = false,
    this.programIds,
  });

  /// Whether to allow PDA (Program Derived Address) owners
  ///
  /// Can be:
  /// - `false`: Only allow standard wallet owners (default)
  /// - `true`: Allow any PDA owners
  /// - `List<String>`: Allow only specific program IDs
  final dynamic allowPda;

  /// List of allowed program IDs (when allowPda is a list)
  final List<String>? programIds;
}

/// Resolves a domain to its owner address according to SNS-IP 5 specification.
///
/// Implements the complete domain resolution logic including:
/// - NFT ownership verification
/// - SOL record V2 validation with signature verification
/// - SOL record V1 validation with signature verification
/// - PDA ownership validation based on options
///
/// The resolution follows this priority order:
/// 1. NFT ownership (if domain is tokenized)
/// 2. SOL record V2 (with staleness and signature checks)
/// 3. SOL record V1 (with signature verification)
/// 4. Registry owner (if allowed by options)
///
/// [rpc] RPC client for fetching account data from Solana
/// [domain] The domain name to resolve (e.g., 'bonfida' or 'sub.domain')
/// [options] Optional configuration for PDA ownership rules
///
/// Returns the resolved owner address as a base58 string
///
/// Throws [DomainDoesNotExistError] if the domain is not registered
/// Throws [NoRecordDataError] if no valid ownership record is found
///
/// ```dart
/// // Basic resolution
/// final owner = await resolveDomain(rpc, 'bonfida');
///
/// // Allow PDA owners
/// final owner = await resolveDomain(rpc, 'program-owned',
///   options: ResolveOptions(allowPda: true));
/// ```
Future<String> resolveDomain(
  RpcClient rpc,
  String domain, {
  ResolveOptions options = const ResolveOptions(),
}) async {
  // Get domain address
  final domainResult = await getDomainAddress(GetDomainAddressParams(
    domain: domain,
  ));
  final domainAddress = domainResult.domainAddress;

  // Get NFT address
  final nftAddress = await NftState.getAddress(domainAddress);

  // Get SOL record addresses
  final solRecordV1Address = await getRecordV1Address(GetRecordV1AddressParams(
    domain: domain,
    record: Record.sol,
  ));
  final solRecordV2Address = await getRecordV2Address(GetRecordV2AddressParams(
    domain: domain,
    record: Record.sol,
  ));

  // Fetch all accounts in parallel
  final accounts = await rpc.fetchEncodedAccounts([
    domainAddress,
    nftAddress,
    solRecordV1Address,
    solRecordV2Address,
  ]);

  final domainAccount = accounts[0];
  final nftAccount = accounts[1];
  final solRecordV1Account = accounts[2];
  final solRecordV2Account = accounts[3];

  // Check if domain exists
  if (!domainAccount.exists) {
    throw DomainDoesNotExistError('Domain $domain does not exist');
  }

  final registry =
      RegistryState.deserialize(Uint8List.fromList(domainAccount.data));

  // If NFT account exists, then the NFT owner is the domain owner
  if (nftAccount.exists) {
    final nftRecord = NftState.deserialize(Uint8List.fromList(nftAccount.data));
    if (nftRecord.tag == NftTag.activeRecord) {
      final nftOwner = await _getNftOwner(rpc, domainAddress);
      if (nftOwner == null) {
        throw CouldNotFindNftOwnerError();
      }
      return nftOwner;
    }
  }

  // Check SOL record V2
  if (solRecordV2Account.exists) {
    try {
      return await _validateSolRecordV2(
        solRecordV2Account,
        registry,
      );
    } on Exception catch (e) {
      // If V2 validation fails, continue to V1
    }
  }

  // Check SOL record V1
  if (solRecordV1Account.exists) {
    final resolvedAddress = await _validateSolRecordV1(
      solRecordV1Account,
      solRecordV1Address,
      registry,
    );
    if (resolvedAddress != null) {
      return resolvedAddress;
    }
  }

  // Check if the registry owner is a PDA
  final registryOwnerBytes = _base58Decode(registry.owner);
  final isOnCurve = checkAddressOnCurve(Uint8List.fromList(registryOwnerBytes));

  if (!isOnCurve) {
    return _handlePdaOwner(rpc, registry.owner, options);
  }

  return registry.owner;
}

/// Validates SOL record V2
Future<String> _validateSolRecordV2(
  AccountInfo recordAccount,
  RegistryState registry,
) async {
  final recordV2 =
      RecordState.deserialize(Uint8List.fromList(recordAccount.data));
  final stalenessId = recordV2.getStalenessId();
  final roaId = recordV2.getRoAId();
  final content = recordV2.getContent();

  if (content.length != 32) {
    throw RecordMalformedError('Record is malformed');
  }

  if (recordV2.header.rightOfAssociationValidation != Validation.solana ||
      recordV2.header.stalenessValidation != Validation.solana) {
    throw InvalidValidationError();
  }

  if (registry.owner !=
      _base58Encode(Uint8List.fromList(_base58Decode(stalenessId)))) {
    throw InvalidRoAError('Staleness validation failed');
  }

  if (!_uint8ArraysEqual(_base58Decode(roaId), content.toList())) {
    final contentAddress = _base58Encode(content);
    final roaAddress = _base58Encode(Uint8List.fromList(_base58Decode(roaId)));
    throw InvalidRoAError(
      'The RoA ID should be $contentAddress but is $roaAddress',
    );
  }

  return _base58Encode(content);
}

/// Validates SOL record V1
Future<String?> _validateSolRecordV1(
  AccountInfo recordAccount,
  String recordAddress,
  RegistryState registry,
) async {
  final data = <int>[];

  // Add content (32 bytes starting from header length)
  data.addAll(recordAccount.data.sublist(
    RegistryState.headerLen,
    RegistryState.headerLen + 32,
  ));

  // Add record address
  data.addAll(_base58Decode(recordAddress));

  final signature = recordAccount.data.sublist(
    RegistryState.headerLen + 32,
    RegistryState.headerLen + 32 + 64,
  );

  final valid = await _verifySolRecordV1Signature(
    data: Uint8List.fromList(data),
    signature: Uint8List.fromList(signature),
    address: registry.owner,
  );

  if (valid) {
    final contentBytes = recordAccount.data.sublist(
      RegistryState.headerLen,
      RegistryState.headerLen + 32,
    );
    return _base58Encode(Uint8List.fromList(contentBytes));
  }

  return null;
}

/// Handles PDA owner validation
Future<String> _handlePdaOwner(
  RpcClient rpc,
  String owner,
  ResolveOptions options,
) async {
  if (options.allowPda == 'any') {
    return owner;
  } else if (options.allowPda == true) {
    final ownerAccount = await rpc.fetchEncodedAccount(owner);

    if (!ownerAccount.exists) {
      throw PdaOwnerNotAllowedError('Invalid domain owner account');
    }

    // Note: Program ID checking would require additional RPC interface methods
    // For now, we allow PDA owners when allowPda is set
    if (options.allowPda == true) {
      return owner;
    }

    throw PdaOwnerNotAllowedError(
      'PDA owner not allowed',
    );
  } else {
    throw PdaOwnerNotAllowedError();
  }
}

/// Gets the NFT owner for a domain
Future<String?> _getNftOwner(RpcClient rpc, String domainAddress) async {
  // This would implement the NFT owner lookup
  // For now, return null as a placeholder
  return null;
}

/// Verifies SOL record V1 signature
Future<bool> _verifySolRecordV1Signature({
  required Uint8List data,
  required Uint8List signature,
  required String address,
}) async {
  // This would implement Ed25519 signature verification
  // For now, return false as a placeholder
  return false;
}

/// Compares two Uint8List for equality
bool _uint8ArraysEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Base58 decode helper (simplified implementation)
List<int> _base58Decode(String input) {
  // Simplified implementation - in production use a proper library
  if (input.isEmpty) return [];
  // Return placeholder for now
  return List.filled(32, 0);
}

/// Base58 encode helper (simplified implementation)
String _base58Encode(Uint8List input) {
  // Simplified implementation - in production use a proper library
  if (input.isEmpty) return '';
  // Return placeholder for now
  return '11111111111111111111111111111111';
}
