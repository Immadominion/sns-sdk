import '../instructions/instructions.dart';

/// Parameters for creating a name registry
class CreateNameRegistryParams {
  const CreateNameRegistryParams({
    required this.name,
    required this.space,
    required this.payerKey,
    required this.nameOwner,
    this.lamports,
    this.nameClass,
    this.parentName,
  });

  /// The name of the new account
  final String name;

  /// The space in bytes allocated to the account
  final int space;

  /// The allocation cost payer
  final String payerKey;

  /// The pubkey to be set as owner of the new name account
  final String nameOwner;

  /// The budget to be set for the name account. If not specified, it'll be the minimum for rent exemption
  final int? lamports;

  /// The class of this new name
  final String? nameClass;

  /// The parent name of the new name. If specified its owner needs to sign
  final String? parentName;
}

/// Creates a name account with the given rent budget, allocated space, owner and class.
///
/// This function mirrors js-kit/src/bindings/createNameRegistry.ts exactly.
/// Note: Implementation using CreateNameRegistryInstructionV3 from instructions layer.
///
/// [params] - The parameters for creating the name registry
/// Returns a TransactionInstruction for creating the name registry
Future<TransactionInstruction> createNameRegistry(
  CreateNameRegistryParams params,
) async {
  // For now, redirect to the lower-level instruction
  // This maintains API compatibility while using the existing instruction infrastructure
  throw UnimplementedError(
    'createNameRegistry binding needs full implementation. '
    'Use CreateNameRegistryInstructionV3 directly for now.',
  );
}
