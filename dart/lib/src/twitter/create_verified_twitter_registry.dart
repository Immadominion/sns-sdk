import 'dart:typed_data';

import '../constants/addresses.dart';
import '../instructions/instruction_types.dart';
import '../rpc/rpc_client.dart';
import '../utils/get_domain_key_sync.dart';
import 'create_reverse_twitter_registry.dart';

/// Create verified Twitter registry instruction
///
/// This function mirrors js/src/twitter/createVerifiedTwitterRegistry.ts
///
/// Signed by the authority, the payer and the verified pubkey
///
/// [connection] - RPC connection
/// [twitterHandle] - The Twitter handle
/// [verifiedPubkey] - The verified public key
/// [space] - The space that the user will have to write data into the verified registry
/// [payerKey] - The payer's public key
///
/// Returns list of transaction instructions
Future<List<TransactionInstruction>> createVerifiedTwitterRegistry(
  RpcClient connection,
  String twitterHandle,
  String verifiedPubkey,
  int space,
  String payerKey,
) async {
  // Create user facing registry
  final hashedTwitterHandle = getHashedNameSync(twitterHandle);
  final twitterHandleRegistryKey = getNameAccountKeySync(
    hashedTwitterHandle,
    nameParent: twitterRootParentRegistryAddress,
  );

  final instructions = <TransactionInstruction>[];

  // Create the main user-facing registry instruction
  // TODO: Implement proper CreateNameRegistryInstruction when instruction infrastructure is complete
  final createInstruction = TransactionInstruction(
    programAddress: nameProgramAddress,
    accounts: [
      const AccountMeta(
        address: systemProgramAddress,
        role: AccountRole.readonly,
      ),
      AccountMeta(
        address: await twitterHandleRegistryKey,
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
      const AccountMeta(
        address: twitterVerificationAuthority,
        role: AccountRole.readonly,
      ),
      const AccountMeta(
        address: twitterRootParentRegistryAddress,
        role: AccountRole.readonly,
      ),
    ],
    data: _buildCreateInstructionData(hashedTwitterHandle, 2000000, space),
  );
  instructions.add(createInstruction);

  // Create the reverse Twitter registry
  final reverseInstructions = await createReverseTwitterRegistry(
    connection,
    twitterHandle,
    await twitterHandleRegistryKey,
    verifiedPubkey,
    payerKey,
  );
  instructions.addAll(reverseInstructions);

  return instructions;
}

/// Build create instruction data (placeholder implementation)
Uint8List _buildCreateInstructionData(
  Uint8List hashedName,
  int lamports,
  int space,
) {
  // This is a placeholder implementation
  // TODO: Implement proper instruction data serialization
  final data = Uint8List(45);

  // Instruction tag (0 for create)
  data[0] = 0;

  // Hashed name (32 bytes)
  data.setRange(1, 33, hashedName);

  // Lamports (8 bytes, little endian)
  final lamportsBytes = Uint8List(8);
  lamportsBytes.buffer.asByteData().setUint64(0, lamports, Endian.little);
  data.setRange(33, 41, lamportsBytes);

  // Space (4 bytes, little endian)
  final spaceBytes = Uint8List(4);
  spaceBytes.buffer.asByteData().setUint32(0, space, Endian.little);
  data.setRange(41, 45, spaceBytes);

  return data;
}
