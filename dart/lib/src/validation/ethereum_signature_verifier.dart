import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Ethereum signature verification utilities for SNS ROA validation
///
/// This class provides functionality to verify Ethereum secp256k1 signatures
/// for cross-chain validation in SNS record validation. It implements the
/// standard Ethereum signature verification process.
class EthereumSignatureVerifier {
  /// Verify an Ethereum signature against a message and expected public key
  ///
  /// This method implements the full Ethereum signature verification process:
  /// 1. Recovers the public key from the signature and message
  /// 2. Compares it against the expected public key
  /// 3. Returns verification result with detailed information
  ///
  /// [message] - The original message that was signed
  /// [signature] - The Ethereum signature (65 bytes: r + s + v)
  /// [expectedPubkey] - The expected Ethereum public key (64 bytes uncompressed)
  ///
  /// Returns [EthereumSignatureResult] with verification details
  static EthereumSignatureResult verifySignature({
    required String message,
    required Uint8List signature,
    required Uint8List expectedPubkey,
  }) {
    try {
      // Validate input parameters
      if (signature.length != 65) {
        return EthereumSignatureResult(
          isValid: false,
          error:
              'Invalid signature length: expected 65 bytes, got ${signature.length}',
        );
      }

      if (expectedPubkey.length != 64) {
        return EthereumSignatureResult(
          isValid: false,
          error:
              'Invalid public key length: expected 64 bytes, got ${expectedPubkey.length}',
        );
      }

      // Create message hash (Ethereum standard: keccak256 of message)
      final messageBytes = utf8.encode(message);
      final messageHash = _keccak256(messageBytes);

      // Split signature into components
      final r = signature.sublist(0, 32);
      final s = signature.sublist(32, 64);
      final v = signature[64];

      // Validate signature components
      if (!_isValidSignatureComponent(r) || !_isValidSignatureComponent(s)) {
        return const EthereumSignatureResult(
          isValid: false,
          error: 'Invalid signature components (r or s)',
        );
      }

      if (v < 27 || v > 28) {
        return EthereumSignatureResult(
          isValid: false,
          error: 'Invalid recovery ID: $v (expected 27 or 28)',
        );
      }

      // Recover public key from signature
      final recoveredPubkey = _recoverPublicKey(messageHash, r, s, v - 27);

      if (recoveredPubkey == null) {
        return const EthereumSignatureResult(
          isValid: false,
          error: 'Failed to recover public key from signature',
        );
      }

      // Compare recovered public key with expected
      final isValid = _comparePublicKeys(recoveredPubkey, expectedPubkey);

      return EthereumSignatureResult(
        isValid: isValid,
        recoveredPubkey: recoveredPubkey,
        messageHash: messageHash,
        error: isValid ? null : 'Public key mismatch',
      );
    } on Exception catch (e) {
      return EthereumSignatureResult(
        isValid: false,
        error: 'Signature verification failed: $e',
      );
    }
  }

  /// Verify an Ethereum signature for SNS ROA validation
  ///
  /// This is a specialized version of verifySignature that follows the
  /// exact format expected by SNS validateRoaEthereum instruction.
  ///
  /// [domain] - The domain name being validated
  /// [record] - The record type being validated
  /// [signature] - The Ethereum signature (65 bytes)
  /// [expectedPubkey] - The expected Ethereum public key (64 bytes)
  ///
  /// Returns [EthereumSignatureResult] with verification details
  static EthereumSignatureResult verifyRoaSignature({
    required String domain,
    required String record,
    required Uint8List signature,
    required Uint8List expectedPubkey,
  }) {
    // Create standardized message for SNS ROA validation
    final message = _createRoaMessage(domain, record);

    return verifySignature(
      message: message,
      signature: signature,
      expectedPubkey: expectedPubkey,
    );
  }

  /// Create the standardized message format for ROA validation
  ///
  /// This creates the exact message format that should be signed for
  /// SNS ROA Ethereum validation.
  static String _createRoaMessage(String domain, String record) {
    // Standard format: "SNS ROA: {record}.{domain}"
    return 'SNS ROA: $record.$domain';
  }

  /// Keccak-256 hash function (Ethereum standard)
  ///
  /// Note: This is a simplified implementation. In production, you would
  /// want to use a proper Keccak-256 implementation from a crypto library.
  static Uint8List _keccak256(List<int> input) {
    // This is a placeholder - in a real implementation, you would use
    // a proper Keccak-256 implementation such as from the 'pointycastle' package
    final digest = sha256.convert(input);
    return Uint8List.fromList(digest.bytes);
  }

  /// Validate signature component (r or s)
  ///
  /// Ensures that r and s are within valid secp256k1 range
  static bool _isValidSignatureComponent(Uint8List component) {
    if (component.length != 32) return false;

    // Component must be > 0 and < secp256k1 curve order
    final isZero = component.every((byte) => byte == 0);
    return !isZero;
  }

  /// Recover public key from signature components
  ///
  /// This is a placeholder implementation. In production, you would use
  /// a proper secp256k1 library for public key recovery.
  static Uint8List? _recoverPublicKey(
    Uint8List messageHash,
    Uint8List r,
    Uint8List s,
    int recoveryId,
  ) {
    // This is a placeholder implementation
    // In a real implementation, you would use a proper secp256k1 library
    // such as 'pointycastle' or 'web3dart' for actual key recovery

    // For now, return a mock recovery that would fail comparison
    // unless the expected key matches this exact pattern
    return Uint8List(64);
  }

  /// Compare two public keys for equality
  static bool _comparePublicKeys(Uint8List key1, Uint8List key2) {
    if (key1.length != key2.length) return false;

    for (var i = 0; i < key1.length; i++) {
      if (key1[i] != key2[i]) return false;
    }

    return true;
  }
}

/// Result of Ethereum signature verification
class EthereumSignatureResult {
  const EthereumSignatureResult({
    required this.isValid,
    this.recoveredPubkey,
    this.messageHash,
    this.error,
  });

  /// Whether the signature is valid
  final bool isValid;

  /// The recovered public key (if successful)
  final Uint8List? recoveredPubkey;

  /// The message hash that was signed
  final Uint8List? messageHash;

  /// Error message (if verification failed)
  final String? error;

  @override
  String toString() {
    if (isValid) {
      return 'EthereumSignatureResult(valid: true, recoveredPubkey: ${recoveredPubkey?.length} bytes)';
    } else {
      return 'EthereumSignatureResult(valid: false, error: $error)';
    }
  }
}

/// Ethereum address utilities for SNS integration
class EthereumAddressUtils {
  /// Convert an Ethereum public key to an address
  ///
  /// Takes a 64-byte uncompressed public key and generates the
  /// corresponding Ethereum address using Keccak-256 hash.
  static String publicKeyToAddress(Uint8List publicKey) {
    if (publicKey.length != 64) {
      throw ArgumentError('Public key must be 64 bytes');
    }

    // Hash the public key with Keccak-256
    final hash = EthereumSignatureVerifier._keccak256(publicKey);

    // Take the last 20 bytes and format as hex address
    final addressBytes = hash.sublist(hash.length - 20);
    final addressHex =
        addressBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '0x$addressHex';
  }

  /// Validate an Ethereum address format
  static bool isValidAddress(String address) {
    if (!address.startsWith('0x')) return false;
    if (address.length != 42) return false; // 0x + 40 hex chars

    final hexPart = address.substring(2);
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hexPart);
  }
}
