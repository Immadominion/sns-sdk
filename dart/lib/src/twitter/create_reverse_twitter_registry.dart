import 'dart:typed_data';

import '../constants/addresses.dart';
import '../instructions/instruction_types.dart';
import '../instructions/update_name_registry_instruction.dart';
import '../rpc/rpc_client.dart';
import '../utils/get_domain_key_sync.dart';
import 'reverse_twitter_registry_state.dart';

/// Create reverse Twitter registry instruction
///
/// This function mirrors js/src/twitter/createReverseTwitterRegistry.ts
///
/// [connection] - RPC connection
/// [twitterHandle] - The Twitter handle
/// [twitterRegistryKey] - The Twitter registry key
/// [verifiedPubkey] - The verified public key
/// [payerKey] - The payer's public key
///
/// Returns list of transaction instructions
Future<List<TransactionInstruction>> createReverseTwitterRegistry(
  RpcClient connection,
  String twitterHandle,
  String twitterRegistryKey,
  String verifiedPubkey,
  String payerKey,
) async {
  // Create the reverse lookup registry
  final hashedVerifiedPubkey = getHashedNameSync(verifiedPubkey);
  final reverseRegistryKey = getNameAccountKeySync(
    hashedVerifiedPubkey,
    nameClass: twitterVerificationAuthority,
    nameParent: twitterRootParentRegistryAddress,
  );

  // Create the reverse Twitter registry state
  final reverseState = ReverseTwitterRegistryState(
    twitterRegistryKey: _publicKeyToBytes(twitterRegistryKey),
    twitterHandle: twitterHandle,
  );
  final reverseTwitterRegistryStateBuff = reverseState.serialize();

  final instructions = <TransactionInstruction>[];

  // Create a basic instruction placeholder
  // TODO: Implement proper CreateNameRegistryInstruction when instruction infrastructure is complete
  final createInstruction = TransactionInstruction(
    programAddress: nameProgramAddress,
    accounts: [
      const AccountMeta(
        address: systemProgramAddress,
        role: AccountRole.readonly,
      ),
      AccountMeta(
        address: await reverseRegistryKey,
        role: AccountRole.writable,
      ),
      AccountMeta(
        address: verifiedPubkey,
        role: AccountRole.readonlySigner,
      ),
      AccountMeta(
        address: payerKey,
        role: AccountRole.writableSigner,
      ),
    ],
    data: _buildPlaceholderCreateData(),
  );
  instructions.add(createInstruction);

  // Create the update instruction to write the reverse state data
  final updateInstr = UpdateNameRegistryInstruction(
    offset: 0,
    inputData: reverseTwitterRegistryStateBuff,
  );

  final updateInstruction = updateInstr.getInstruction(
    programAddress: nameProgramAddress,
    domainAddress: await reverseRegistryKey,
    signer: twitterVerificationAuthority,
  );
  instructions.add(updateInstruction);

  return instructions;
}

/// Convert public key string to bytes (placeholder implementation)
Uint8List _publicKeyToBytes(String pubkey) {
  // This is a placeholder - proper implementation would decode base58
  final bytes = Uint8List(32);
  // Fill with dummy data for now
  for (var i = 0; i < 32; i++) {
    bytes[i] = i;
  }
  return bytes;
}

/// Build placeholder create instruction data
Uint8List _buildPlaceholderCreateData() {
  // This is a basic placeholder implementation
  // TODO: Implement proper instruction data serialization
  return Uint8List.fromList([0]); // Basic create instruction tag
}
