import '../constants/addresses.dart';
import '../instructions/create_with_nft_instruction.dart';
import '../instructions/instruction_types.dart';
import '../utils/derive_address.dart';

/// Parameters for registering with NFT
class RegisterWithNftParams {
  const RegisterWithNftParams({
    required this.domain,
    required this.space,
    required this.buyer,
    required this.nftSource,
    required this.nftMint,
  });

  /// The domain name to be registered
  final String domain;

  /// The space in bytes to be allocated for the domain registry
  final int space;

  /// The address of the buyer registering the domain
  final String buyer;

  /// The address of the NFT source account
  final String nftSource;

  /// The mint address of the NFT used for registration
  final String nftMint;
}

/// Registers a .sol domain using a Bonfida Wolves NFT.
///
/// This mirrors js-kit/src/bindings/registerWithNft.ts
Future<TransactionInstruction> registerWithNft(
    RegisterWithNftParams params) async {
  final domainAddress = await deriveAddress(
    params.domain,
    parentAddress: rootDomainAddress,
  );

  final reverseLookupAccount = await deriveAddress(
    domainAddress,
    classAddress: centralState,
  );

  // For now, we'll use simplified PDA generation
  // In full implementation, would use proper PDA derivation
  const state = registryProgramAddress;
  const nftMetadata = metaplexProgramAddress;
  const masterEdition = metaplexProgramAddress;

  final instruction = CreateWithNftInstruction(
    space: params.space,
    name: params.domain,
  );

  instruction.setParams(
    programAddress: registryProgramAddress,
    namingServiceProgram: nameProgramAddress,
    rootDomain: rootDomainAddress,
    nameAddress: domainAddress,
    reverseLookup: reverseLookupAccount,
    systemProgram: systemProgramAddress,
    centralState: reverseLookupClass,
    buyer: params.buyer,
    nftSource: params.nftSource,
    nftMetadata: nftMetadata,
    nftMint: params.nftMint,
    masterEdition: masterEdition,
    collection: wolvesCollectionMetadata,
    splTokenProgram: tokenProgramAddress,
    rentSysvar: sysvarRentAddress,
    state: state,
    mplTokenMetadata: metaplexProgramAddress,
  );

  return instruction.build();
}
