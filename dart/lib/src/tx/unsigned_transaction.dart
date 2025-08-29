import 'dart:typed_data';

/// Hardware wallet transaction instruction data
class HwTransactionInstruction {
  const HwTransactionInstruction({
    required this.programId,
    required this.accounts,
    required this.data,
  });

  /// Program ID for this instruction
  final String programId;

  /// Account metadata for this instruction
  final List<HwAccountMeta> accounts;

  /// Instruction data bytes
  final Uint8List data;
}

/// Hardware wallet account metadata for transaction instructions
class HwAccountMeta {
  const HwAccountMeta({
    required this.pubkey,
    required this.isSigner,
    required this.isWritable,
  });

  /// Account public key
  final String pubkey;

  /// Whether this account is a signer
  final bool isSigner;

  /// Whether this account is writable
  final bool isWritable;
}

/// Unsigned transaction for hardware wallet integration (Phase 4)
///
/// This class enables secure transaction workflows where signing can be
/// performed externally (hardware wallets, mobile signers, etc.)
class UnsignedTransaction {
  const UnsignedTransaction({
    required this.instructions,
    required this.requiredSigners,
    required this.recentBlockhash,
    required this.feePayer,
    required this.messageBytes,
  });

  /// List of transaction instructions
  final List<HwTransactionInstruction> instructions;

  /// Required signers for this transaction
  final List<String> requiredSigners;

  /// Recent blockhash for transaction lifetime
  final String recentBlockhash;

  /// Fee payer for the transaction
  final String feePayer;

  /// Raw transaction message bytes (unsigned)
  final Uint8List messageBytes;

  /// Create unsigned transaction from instructions
  ///
  /// This provides unsigned transaction workflow for hardware wallet integration.
  static UnsignedTransaction fromInstructions({
    required List<HwTransactionInstruction> instructions,
    required String feePayer,
    required String recentBlockhash,
    List<String> additionalSigners = const [],
  }) {
    // Collect all required signers
    final requiredSigners = <String>{feePayer};
    requiredSigners.addAll(additionalSigners);

    // Extract additional signers from instruction accounts
    for (final instruction in instructions) {
      for (final account in instruction.accounts) {
        if (account.isSigner) {
          requiredSigners.add(account.pubkey);
        }
      }
    }

    // Create simplified message bytes
    // In a full implementation, this would properly serialize the transaction message
    final messageData =
        _createMessageBytes(instructions, recentBlockhash, feePayer);

    return UnsignedTransaction(
      instructions: instructions,
      requiredSigners: requiredSigners.toList(),
      recentBlockhash: recentBlockhash,
      feePayer: feePayer,
      messageBytes: messageData,
    );
  }

  /// Create transaction message bytes (simplified implementation for Phase 4)
  static Uint8List _createMessageBytes(
    List<HwTransactionInstruction> instructions,
    String recentBlockhash,
    String feePayer,
  ) {
    // This is a simplified implementation for Phase 4
    // In production, this would use proper Solana message serialization
    final buffer = <int>[];

    // Add basic transaction structure
    buffer.addAll(recentBlockhash.codeUnits);
    buffer.addAll(feePayer.codeUnits);
    buffer.add(instructions.length);

    for (final instruction in instructions) {
      buffer.addAll(instruction.programId.codeUnits);
      buffer.add(instruction.accounts.length);
      for (final account in instruction.accounts) {
        buffer.addAll(account.pubkey.codeUnits);
        buffer.add(account.isSigner ? 1 : 0);
        buffer.add(account.isWritable ? 1 : 0);
      }
      buffer.addAll(instruction.data);
    }

    return Uint8List.fromList(buffer);
  }

  /// Get transaction bytes for external signing
  ///
  /// Returns the transaction bytes that need to be signed by external signers.
  /// This is compatible with hardware wallets and other external signing devices.
  Uint8List getBytesToSign() => messageBytes;

  /// Create signed transaction data from external signatures
  ///
  /// Takes signatures from external signers and creates transaction data
  /// that can be broadcast to the network.
  Map<String, dynamic> createSignedTransactionData(List<String> signatures) {
    if (signatures.length != requiredSigners.length) {
      throw ArgumentError(
        'Invalid signature count: expected ${requiredSigners.length}, got ${signatures.length}',
      );
    }

    return {
      'signatures': signatures,
      'message': messageBytes.toList(),
      'requiredSigners': requiredSigners,
      'recentBlockhash': recentBlockhash,
      'feePayer': feePayer,
    };
  }

  /// Get transaction size for fee estimation
  int get estimatedSize {
    // Estimate with signatures (64 bytes each)
    return messageBytes.length + (requiredSigners.length * 64);
  }

  /// Get list of accounts that need to sign this transaction
  List<String> get signerAddresses => requiredSigners;

  /// Serialize for external wallet communication
  ///
  /// Returns a JSON-serializable representation for communication with
  /// external wallets or signing services.
  Map<String, dynamic> toJson() => {
        'message': messageBytes.toList(),
        'requiredSigners': requiredSigners,
        'recentBlockhash': recentBlockhash,
        'feePayer': feePayer,
        'instructions': instructions.length,
        'estimatedSize': estimatedSize,
      };

  /// Create unsigned transaction from JSON
  static UnsignedTransaction fromJson(Map<String, dynamic> json) =>
      UnsignedTransaction(
        instructions: [], // Would need to reconstruct from JSON
        requiredSigners: List<String>.from(json['requiredSigners'] ?? []),
        recentBlockhash: json['recentBlockhash'] ?? '',
        feePayer: json['feePayer'] ?? '',
        messageBytes: Uint8List.fromList(List<int>.from(json['message'] ?? [])),
      );
}

/// Transaction builder for creating complex transactions with multiple instructions
class TransactionBuilder {
  final List<HwTransactionInstruction> _instructions = [];
  final List<String> _signers = [];
  String? _feePayer;
  String? _recentBlockhash;

  /// Add instruction to the transaction
  TransactionBuilder addInstruction(HwTransactionInstruction instruction) {
    _instructions.add(instruction);
    return this;
  }

  /// Add multiple instructions to the transaction
  TransactionBuilder addInstructions(
      List<HwTransactionInstruction> instructions) {
    _instructions.addAll(instructions);
    return this;
  }

  /// Set the fee payer for the transaction
  TransactionBuilder setFeePayer(String feePayer) {
    _feePayer = feePayer;
    return this;
  }

  /// Set the recent blockhash for the transaction
  TransactionBuilder setRecentBlockhash(String recentBlockhash) {
    _recentBlockhash = recentBlockhash;
    return this;
  }

  /// Add additional signer (beyond instruction-derived signers)
  TransactionBuilder addSigner(String signer) {
    _signers.add(signer);
    return this;
  }

  /// Build the unsigned transaction
  UnsignedTransaction build() {
    if (_feePayer == null) {
      throw StateError('Fee payer must be set before building transaction');
    }

    if (_recentBlockhash == null) {
      throw StateError(
          'Recent blockhash must be set before building transaction');
    }

    if (_instructions.isEmpty) {
      throw StateError(
          'At least one instruction must be added before building transaction');
    }

    return UnsignedTransaction.fromInstructions(
      instructions: _instructions,
      feePayer: _feePayer!,
      recentBlockhash: _recentBlockhash!,
      additionalSigners: _signers,
    );
  }

  /// Clear all instructions and signers
  TransactionBuilder clear() {
    _instructions.clear();
    _signers.clear();
    _feePayer = null;
    _recentBlockhash = null;
    return this;
  }
}

/// Utilities for hardware wallet integration
class HardwareWalletUtils {
  /// Check if a transaction is compatible with hardware wallet constraints
  ///
  /// Hardware wallets may have limitations on transaction size, number of accounts, etc.
  static bool isHardwareWalletCompatible(UnsignedTransaction transaction) {
    // Check transaction size (most hardware wallets have ~1232 byte limit)
    if (transaction.estimatedSize > 1200) {
      return false;
    }

    // Check number of instructions (hardware wallets may limit instructions)
    if (transaction.instructions.length > 20) {
      return false;
    }

    // Check number of required signers
    if (transaction.requiredSigners.length > 10) {
      return false;
    }

    return true;
  }

  /// Split large transaction into hardware wallet compatible chunks
  ///
  /// If a transaction exceeds hardware wallet limits, this function can help
  /// split it into multiple smaller transactions.
  static List<List<HwTransactionInstruction>>
      splitInstructionsForHardwareWallet(
    List<HwTransactionInstruction> instructions,
  ) {
    const maxInstructionsPerTx = 15; // Conservative limit for hardware wallets
    final chunks = <List<HwTransactionInstruction>>[];

    for (var i = 0; i < instructions.length; i += maxInstructionsPerTx) {
      final end = (i + maxInstructionsPerTx < instructions.length)
          ? i + maxInstructionsPerTx
          : instructions.length;
      chunks.add(instructions.sublist(i, end));
    }

    return chunks;
  }

  /// Get transaction compatibility report
  static Map<String, dynamic> getCompatibilityReport(
          UnsignedTransaction transaction) =>
      {
        'isCompatible': isHardwareWalletCompatible(transaction),
        'estimatedSize': transaction.estimatedSize,
        'maxSizeLimit': 1200,
        'instructionCount': transaction.instructions.length,
        'maxInstructionLimit': 20,
        'signerCount': transaction.requiredSigners.length,
        'maxSignerLimit': 10,
        'requiredSigners': transaction.signerAddresses,
      };

  /// Create a simple transaction for testing hardware wallet compatibility
  static HwTransactionInstruction createTestInstruction(String programId) =>
      HwTransactionInstruction(
        programId: programId,
        accounts: [
          const HwAccountMeta(
            pubkey: '11111111111111111111111111111112', // System program
            isSigner: false,
            isWritable: false,
          ),
        ],
        data: Uint8List.fromList([0]), // Minimal instruction data
      );

  /// Validate transaction before hardware wallet submission
  static List<String> validateTransaction(UnsignedTransaction transaction) {
    final issues = <String>[];

    if (transaction.estimatedSize > 1200) {
      issues.add(
          'Transaction size (${transaction.estimatedSize}) exceeds hardware wallet limit (1200 bytes)');
    }

    if (transaction.instructions.length > 20) {
      issues.add(
          'Instruction count (${transaction.instructions.length}) exceeds hardware wallet limit (20)');
    }

    if (transaction.requiredSigners.length > 10) {
      issues.add(
          'Signer count (${transaction.requiredSigners.length}) exceeds hardware wallet limit (10)');
    }

    if (transaction.recentBlockhash.isEmpty) {
      issues.add('Recent blockhash is required');
    }

    if (transaction.feePayer.isEmpty) {
      issues.add('Fee payer is required');
    }

    return issues;
  }
}
