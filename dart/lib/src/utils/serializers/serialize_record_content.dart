import 'dart:convert';
import 'dart:typed_data';

import '../../constants/records.dart';
import '../../errors/sns_errors.dart';

/// Parameters for serializing record content
class SerializeRecordContentParams {
  const SerializeRecordContentParams({
    required this.content,
    required this.record,
  });

  /// The record content to serialize
  final String content;

  /// The type of record for which the content is being serialized
  final Record record;
}

/// Serializes record content based on its type.
///
/// This mirrors js-kit/src/utils/serializers/serializeRecordContent.ts
Uint8List serializeRecordContent({
  required String content,
  required Record record,
}) {
  final utf8Encoded = utf8EncodedRecords.contains(record);

  if (utf8Encoded) {
    var processedContent = content;
    if (record == Record.cname || record == Record.txt) {
      // Simple ASCII encoding for punycode-like processing
      processedContent = content.toLowerCase();
    }
    return utf8.encode(processedContent);
  } else if (record == Record.sol) {
    // For SOL addresses, we expect them to be base58 encoded
    // Convert base58 to bytes
    return _base58Decode(content);
  } else if (evmRecords.contains(record)) {
    if (!content.startsWith('0x')) {
      throw InvalidEvmAddressError('The record content must start with `0x`');
    }
    if (content.length != 42) {
      throw InvalidEvmAddressError(
          'The record content must be 42 characters long');
    }
    return _hexToBytes(content.substring(2));
  } else if (record == Record.injective) {
    // For injective addresses, we expect bech32 format starting with 'inj'
    if (!content.startsWith('inj')) {
      throw InvalidInjectiveAddressError(
          'The record content must start with `inj`');
    }
    if (content.length != 42) {
      throw InvalidInjectiveAddressError(
          'The record content must be 42 characters long');
    }
    // Simplified bech32 decoding - in production would use proper bech32 library
    final decoded = _simpleBech32Decode(content);
    if (decoded.length != 20) {
      throw InvalidInjectiveAddressError(
          'The record data must be 20 bytes long');
    }
    return decoded;
  } else if (record == Record.a) {
    // IPv4 address parsing
    final parts = content.split('.');
    if (parts.length != 4) {
      throw InvalidARecordError(
          'The record content must be a valid IPv4 address');
    }
    final bytes = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        throw InvalidARecordError('Invalid IPv4 address component');
      }
      bytes.add(value);
    }
    if (bytes.length != 4) {
      throw InvalidARecordError('The record content must be 4 bytes long');
    }
    return Uint8List.fromList(bytes);
  } else if (record == Record.aaaa) {
    // IPv6 address parsing - simplified
    final bytes = _parseIPv6(content);
    if (bytes.length != 16) {
      throw InvalidAAAARecordError('The record content must be 16 bytes long');
    }
    return bytes;
  } else {
    throw InvalidRecordInputError('The record content is malformed');
  }
}

/// Convert hex string to bytes
Uint8List _hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    final hexByte = hex.substring(i, i + 2);
    bytes.add(int.parse(hexByte, radix: 16));
  }
  return Uint8List.fromList(bytes);
}

/// Base58 alphabet used by Solana
const String _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Decode a base58 string to bytes
Uint8List _base58Decode(String input) {
  if (input.isEmpty) return Uint8List(0);

  // Count leading zeros
  var leadingZeros = 0;
  for (var i = 0; i < input.length; i++) {
    if (input[i] == '1') {
      leadingZeros++;
    } else {
      break;
    }
  }

  // Decode base58
  var decoded = BigInt.zero;
  final base = BigInt.from(58);

  for (var i = leadingZeros; i < input.length; i++) {
    final char = input[i];
    final index = _base58Alphabet.indexOf(char);
    if (index == -1) {
      throw ArgumentError('Invalid base58 character: $char');
    }
    decoded = decoded * base + BigInt.from(index);
  }

  // Convert to bytes
  final bytes = <int>[];
  while (decoded > BigInt.zero) {
    bytes.insert(0, (decoded % BigInt.from(256)).toInt());
    decoded = decoded ~/ BigInt.from(256);
  }

  // Add leading zeros
  for (var i = 0; i < leadingZeros; i++) {
    bytes.insert(0, 0);
  }

  return Uint8List.fromList(bytes);
}

/// Simplified bech32 decoding for injective addresses
Uint8List _simpleBech32Decode(String address) {
  // This is a simplified implementation
  // In production, use a proper bech32 library
  if (!address.startsWith('inj')) {
    throw ArgumentError('Invalid injective address');
  }

  // For now, return a 20-byte placeholder
  // In real implementation, would decode the bech32 properly
  return Uint8List(20);
}

/// Simple IPv6 address parsing
Uint8List _parseIPv6(String address) {
  // This is a simplified implementation
  // In production, use a proper IPv6 parsing library
  try {
    final parts = address.split(':');
    final bytes = <int>[];

    for (final part in parts) {
      if (part.isEmpty) continue;
      final value = int.parse(part, radix: 16);
      bytes.add((value >> 8) & 0xFF);
      bytes.add(value & 0xFF);
    }

    // Pad to 16 bytes if needed
    while (bytes.length < 16) {
      bytes.add(0);
    }

    return Uint8List.fromList(bytes.take(16).toList());
  } on Exception catch (e) {
    throw InvalidAAAARecordError('Invalid IPv6 address format');
  }
}
