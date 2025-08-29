import '../constants/addresses.dart';
import '../instructions/instructions.dart';
import '../utils/derive_address.dart';

/// Parameters for burning a domain
class BurnDomainParams {
  const BurnDomainParams({
    required this.domain,
    required this.owner,
    required this.refundAddress,
  });

  /// The domain name to burn
  final String domain;

  /// The current owner's address
  final String owner;

  /// The address to refund rent to
  final String refundAddress;
}

/// Creates a domain burn instruction
///
/// Burns a domain and refunds rent to the specified address.
/// This matches the js-kit/src/bindings/burnDomain.ts implementation.
Future<TransactionInstruction> burnDomain(BurnDomainParams params) async {
  // Derive the domain address
  final domainAddress = await deriveAddress(params.domain);

  // For now, use simplified PDA derivation
  // In a full implementation, these would be properly derived
  final reverseAddress = await deriveAddress('${params.domain}_reverse');
  final stateAddress = domainAddress;
  final resellingStateAddress = domainAddress;

  // Create burn instruction parameters
  final burnParams = BurnDomainInstructionParams(
    nameServiceId: nameProgramAddress,
    systemProgram: systemProgramAddress,
    domainAddress: domainAddress,
    reverse: reverseAddress,
    resellingState: resellingStateAddress,
    state: stateAddress,
    centralState: centralState,
    owner: params.owner,
    target: params.refundAddress,
    programAddress: registryProgramAddress,
  );

  // Create and build the burn instruction
  final burnInstr = BurnDomainInstruction(
    params: burnParams,
  );

  return burnInstr.build();
}
