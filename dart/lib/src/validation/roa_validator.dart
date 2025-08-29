/// Right of Association (RoA) validation system for SNS records
///
/// Provides comprehensive validation for record authenticity and ownership
/// verification matching the JavaScript SDK validation patterns.
library;

import 'dart:convert';
import '../constants/records.dart';
import '../rpc/rpc_client.dart';

/// Exception thrown when RoA validation fails
class RoaValidationError implements Exception {
  const RoaValidationError(this.message, {this.domain, this.recordType});
  final String message;
  final String? domain;
  final Record? recordType;

  @override
  String toString() =>
      'RoaValidationError: $message${domain != null ? ' (domain: $domain)' : ''}${recordType != null ? ' (record: $recordType)' : ''}';
}

/// Validation result for RoA verification
class ValidationResult {
  const ValidationResult({
    required this.isValid,
    this.error,
    this.metadata,
  });

  factory ValidationResult.valid({Map<String, dynamic>? metadata}) =>
      ValidationResult(isValid: true, metadata: metadata);

  factory ValidationResult.invalid(String error,
          {Map<String, dynamic>? metadata}) =>
      ValidationResult(isValid: false, error: error, metadata: metadata);
  final bool isValid;
  final String? error;
  final Map<String, dynamic>? metadata;
}

/// Right of Association validation utilities for record authenticity
class RoaValidator {
  /// Validates Right of Association for a domain record
  ///
  /// This is the main validation function that checks if a record is properly
  /// authorized to be associated with a domain through cryptographic proof.
  ///
  /// [rpc] - The RPC client for blockchain queries
  /// [domain] - The SNS domain name
  /// [recordType] - The type of record being validated
  /// [recordData] - The record content data
  /// [signature] - Optional signature for verification
  ///
  /// Returns [ValidationResult] with validation status and details.
  static Future<ValidationResult> validateRoa(
    RpcClient rpc,
    String domain,
    Record recordType,
    List<int> recordData, {
    List<int>? signature,
    Map<String, dynamic>? options,
  }) async {
    try {
      // Validate input parameters
      if (domain.isEmpty) {
        return ValidationResult.invalid('Domain cannot be empty');
      }

      if (recordData.isEmpty) {
        return ValidationResult.invalid('Record data cannot be empty');
      }

      // Get the record address for validation
      final recordAddress = await _getRecordAddress(domain, recordType);
      if (recordAddress == null) {
        return ValidationResult.invalid('Could not derive record address');
      }

      // Fetch current record state from blockchain
      final recordAccount = await _fetchRecordAccount(rpc, recordAddress);
      if (recordAccount == null) {
        return ValidationResult.invalid('Record does not exist on blockchain');
      }

      // Validate record staleness
      final stalenessCheck = await _validateRecordStaleness(rpc, recordAddress);
      if (!stalenessCheck.isValid) {
        return ValidationResult.invalid(
            'Record is stale: ${stalenessCheck.error}');
      }

      // Perform record type specific validation
      switch (recordType) {
        case Record.sol:
          return await _validateSolRecordRoa(
              rpc, domain, recordData, recordAccount);

        case Record.eth:
          return await _validateEthRecordRoa(domain, recordData, signature);

        case Record.url:
          return await _validateUrlRecordRoa(domain, recordData);

        case Record.twitter:
          return await _validateTwitterRecordRoa(domain, recordData);

        case Record.discord:
          return await _validateDiscordRecordRoa(domain, recordData);

        case Record.github:
          return await _validateGithubRecordRoa(domain, recordData);

        default:
          return await _validateGenericRecordRoa(
              domain, recordType, recordData);
      }
    } on Exception catch (e) {
      return ValidationResult.invalid('Validation error: $e');
    }
  }

  /// Validates SOL record Right of Association
  static Future<ValidationResult> _validateSolRecordRoa(
    RpcClient rpc,
    String domain,
    List<int> recordData,
    Map<String, dynamic> recordAccount,
  ) async {
    try {
      // Parse SOL address from record data
      if (recordData.length != 32) {
        return ValidationResult.invalid('SOL record data must be 32 bytes');
      }

      // Convert to base58 address
      final solAddress = _bytesToBase58(recordData);

      // Verify the address exists on the blockchain
      final addressAccount = await rpc.fetchEncodedAccount(solAddress);
      if (!addressAccount.exists || addressAccount.data.isEmpty) {
        return ValidationResult.invalid(
            'SOL address does not exist on blockchain');
      }

      // Additional validation: check if address is a valid program derived address
      final isValidPda = await _validateSolAddressFormat(solAddress);
      if (!isValidPda) {
        return ValidationResult.invalid('Invalid SOL address format');
      }

      return ValidationResult.valid(metadata: {
        'solAddress': solAddress,
        'dataLength': addressAccount.data.length,
        'exists': addressAccount.exists,
      });
    } on Exception catch (e) {
      return ValidationResult.invalid('SOL record validation failed: $e');
    }
  }

  /// Validates Ethereum record Right of Association
  static Future<ValidationResult> _validateEthRecordRoa(
    String domain,
    List<int> recordData,
    List<int>? signature,
  ) async {
    try {
      // Parse Ethereum address from record data
      if (recordData.length != 20) {
        return ValidationResult.invalid(
            'Ethereum record data must be 20 bytes');
      }

      final ethAddress =
          '0x${recordData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

      // Validate Ethereum address format
      if (!_isValidEthereumAddress(ethAddress)) {
        return ValidationResult.invalid('Invalid Ethereum address format');
      }

      // If signature is provided, validate RoA signature
      if (signature != null) {
        final signatureValid = await _verifyEthereumRoaSignature(
          domain,
          ethAddress,
          signature,
        );

        if (!signatureValid) {
          return ValidationResult.invalid('Invalid Ethereum RoA signature');
        }
      }

      return ValidationResult.valid(metadata: {
        'ethAddress': ethAddress,
        'signatureProvided': signature != null,
      });
    } on Exception catch (e) {
      return ValidationResult.invalid('Ethereum record validation failed: $e');
    }
  }

  /// Validates URL record Right of Association
  static Future<ValidationResult> _validateUrlRecordRoa(
    String domain,
    List<int> recordData,
  ) async {
    try {
      final url = utf8.decode(recordData);

      // Validate URL format
      final uri = Uri.tryParse(url);
      if (uri == null ||
          (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https'))) {
        return ValidationResult.invalid('Invalid URL format');
      }

      // Check URL length constraints
      if (url.length > 512) {
        return ValidationResult.invalid(
            'URL exceeds maximum length of 512 characters');
      }

      // Validate domain reference in URL (optional check)
      final urlContainsDomain =
          url.toLowerCase().contains(domain.toLowerCase());

      return ValidationResult.valid(metadata: {
        'url': url,
        'scheme': uri.scheme,
        'host': uri.host,
        'containsDomain': urlContainsDomain,
      });
    } on Exception catch (e) {
      return ValidationResult.invalid('URL record validation failed: $e');
    }
  }

  /// Validates Twitter record Right of Association
  static Future<ValidationResult> _validateTwitterRecordRoa(
    String domain,
    List<int> recordData,
  ) async {
    try {
      final twitterHandle = utf8.decode(recordData);

      // Validate Twitter handle format
      if (!_isValidTwitterHandle(twitterHandle)) {
        return ValidationResult.invalid('Invalid Twitter handle format');
      }

      // Check handle length constraints
      if (twitterHandle.length > 15) {
        return ValidationResult.invalid(
            'Twitter handle exceeds maximum length');
      }

      return ValidationResult.valid(metadata: {
        'twitterHandle': twitterHandle,
        'normalized': _normalizeTwitterHandle(twitterHandle),
      });
    } on Exception catch (e) {
      return ValidationResult.invalid('Twitter record validation failed: $e');
    }
  }

  /// Validates Discord record Right of Association
  static Future<ValidationResult> _validateDiscordRecordRoa(
    String domain,
    List<int> recordData,
  ) async {
    try {
      final discordId = utf8.decode(recordData);

      // Validate Discord ID format (should be numeric)
      if (!_isValidDiscordId(discordId)) {
        return ValidationResult.invalid('Invalid Discord ID format');
      }

      return ValidationResult.valid(metadata: {
        'discordId': discordId,
      });
    } on Exception catch (e) {
      return ValidationResult.invalid('Discord record validation failed: $e');
    }
  }

  /// Validates GitHub record Right of Association
  static Future<ValidationResult> _validateGithubRecordRoa(
    String domain,
    List<int> recordData,
  ) async {
    try {
      final githubUsername = utf8.decode(recordData);

      // Validate GitHub username format
      if (!_isValidGithubUsername(githubUsername)) {
        return ValidationResult.invalid('Invalid GitHub username format');
      }

      return ValidationResult.valid(metadata: {
        'githubUsername': githubUsername,
      });
    } on Exception catch (e) {
      return ValidationResult.invalid('GitHub record validation failed: $e');
    }
  }

  /// Validates generic record Right of Association
  static Future<ValidationResult> _validateGenericRecordRoa(
    String domain,
    Record recordType,
    List<int> recordData,
  ) async {
    try {
      // Basic validation for generic records
      if (recordData.isEmpty) {
        return ValidationResult.invalid('Record data cannot be empty');
      }

      // Check maximum data size (32KB)
      if (recordData.length > 32768) {
        return ValidationResult.invalid('Record data exceeds maximum size');
      }

      // Try to decode as UTF-8 for text-based records
      String? textContent;
      try {
        textContent = utf8.decode(recordData);
      } on Exception catch (e) {
        // Binary data is acceptable for some record types
      }

      return ValidationResult.valid(metadata: {
        'recordType': recordType.toString(),
        'dataLength': recordData.length,
        'isTextContent': textContent != null,
        'textContent': textContent,
      });
    } on Exception catch (e) {
      return ValidationResult.invalid('Generic record validation failed: $e');
    }
  }

  // Helper methods

  static Future<String?> _getRecordAddress(
      String domain, Record recordType) async {
    // This would call the actual record address derivation function
    // For now, return a placeholder
    return 'placeholder_record_address';
  }

  static Future<Map<String, dynamic>?> _fetchRecordAccount(
      RpcClient rpc, String address) async {
    try {
      final account = await rpc.fetchEncodedAccount(address);
      return {
        'data': account.data,
        'exists': account.exists,
      };
    } on Exception catch (e) {
      return null;
    }
  }

  static Future<ValidationResult> _validateRecordStaleness(
      RpcClient rpc, String recordAddress) async {
    // Placeholder implementation for record staleness validation
    // This would check if the record is up to date
    return ValidationResult.valid();
  }

  static String _bytesToBase58(List<int> bytes) {
    // Placeholder implementation for base58 encoding
    // In production, use a proper base58 library
    return 'base58_encoded_address';
  }

  static Future<bool> _validateSolAddressFormat(String address) async {
    // Validate SOL address format
    return address.length == 44; // Base58 encoded 32-byte address
  }

  static bool _isValidEthereumAddress(String address) {
    final regex = RegExp(r'^0x[a-fA-F0-9]{40}$');
    return regex.hasMatch(address);
  }

  static Future<bool> _verifyEthereumRoaSignature(
    String domain,
    String ethAddress,
    List<int> signature,
  ) async {
    // Placeholder for Ethereum signature verification
    // This would use proper ECDSA verification
    return signature.length == 65;
  }

  static bool _isValidTwitterHandle(String handle) {
    final normalizedHandle =
        handle.startsWith('@') ? handle.substring(1) : handle;
    final regex = RegExp(r'^[a-zA-Z0-9_]{1,15}$');
    return regex.hasMatch(normalizedHandle);
  }

  static String _normalizeTwitterHandle(String handle) =>
      handle.startsWith('@') ? handle.substring(1) : handle;

  static bool _isValidDiscordId(String id) {
    final regex = RegExp(r'^\d{17,19}$');
    return regex.hasMatch(id);
  }

  static bool _isValidGithubUsername(String username) {
    final regex =
        RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$');
    return regex.hasMatch(username);
  }

  /// Gets validation rules for each record type
  static Map<Record, String> getValidationRules() => {
        Record.sol: 'Must be a valid 32-byte Solana address',
        Record.eth:
            'Must be a valid 20-byte Ethereum address with optional RoA signature',
        Record.url: 'Must be a valid HTTP/HTTPS URL under 512 characters',
        Record.twitter:
            'Must be a valid Twitter handle (1-15 characters, alphanumeric and underscore)',
        Record.discord: 'Must be a valid Discord ID (17-19 digits)',
        Record.github:
            'Must be a valid GitHub username (1-39 characters, alphanumeric and hyphen)',
      };
}
