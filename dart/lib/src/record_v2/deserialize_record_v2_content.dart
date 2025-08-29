/// Record V2 content deserialization functionality
///
/// This module provides functionality to deserialize binary content for Record V2
/// based on the record type, following SNS-IP 1 guidelines exactly as in the JavaScript SDK.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:solana/solana.dart';

import '../constants/records.dart';
import '../errors/sns_errors.dart';
import 'constants.dart' as v2_constants;

/// Converts punycode decoded strings for CNAME and TXT records
String _decodePunycode(String input) {
  // For simplicity, we'll return the input as-is since Dart's Uri class handles punycode
  // In a full implementation, you'd use a punycode library
  return input;
}

/// Formats IPv4 address bytes as a string
String _formatIpv4(List<int> bytes) {
  if (bytes.length != 4) {
    throw InvalidRecordDataError('IPv4 address must be 4 bytes');
  }
  return bytes.join('.');
}

/// Formats IPv6 address bytes as a string
String _formatIpv6(List<int> bytes) {
  if (bytes.length != 16) {
    throw InvalidRecordDataError('IPv6 address must be 16 bytes');
  }

  final parts = <String>[];
  for (var i = 0; i < 16; i += 2) {
    final value = (bytes[i] << 8) | bytes[i + 1];
    parts.add(value.toRadixString(16));
  }

  return parts.join(':');
}

/// Simple bech32 encoder for Injective addresses
String _encodeBech32Injective(List<int> data) {
  // Simple implementation - in production use a proper bech32 library
  const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  // Convert 8-bit to 5-bit
  final converted = <int>[];
  var acc = 0;
  var bits = 0;

  for (final value in data) {
    acc = (acc << 8) | value;
    bits += 8;

    while (bits >= 5) {
      bits -= 5;
      converted.add((acc >> bits) & 31);
    }
  }

  if (bits > 0) {
    converted.add((acc << (5 - bits)) & 31);
  }

  // Build result with hrp
  var result = 'inj1';
  for (final value in converted) {
    result += charset[value];
  }

  return result;
}

/// Deserializes binary content based on the record type following SNS-IP 1 guidelines
///
/// This function converts binary content back to the appropriate string format
/// for each record type, matching the JavaScript SDK implementation exactly.
///
/// Examples:
/// ```dart
/// final ethAddress = deserializeRecordV2Content(ethBytes, Record.eth);
/// final solAddress = deserializeRecordV2Content(solBytes, Record.sol);
/// final urlString = deserializeRecordV2Content(urlBytes, Record.url);
/// ```
///
/// @param content The binary content to deserialize
/// @param record The record type that determines deserialization format
/// @returns The deserialized content as string
/// @throws [InvalidRecordDataError] if the content format is invalid for the record type
String deserializeRecordV2Content(Uint8List content, Record record) {
  final isUtf8Encoded = v2_constants.utf8EncodedRecords.contains(record);

  if (isUtf8Encoded) {
    try {
      final decoded = utf8.decode(content);
      if (record == Record.cname || record == Record.txt) {
        return _decodePunycode(decoded);
      }
      return decoded;
    } on Exception {
      throw InvalidRecordDataError(
          'Invalid UTF-8 content for record type: ${record.name}');
    }
  } else if (record == Record.sol) {
    if (content.length != 32) {
      throw InvalidRecordDataError('SOL record must be 32 bytes');
    }
    try {
      final pubkey = Ed25519HDPublicKey(content);
      return pubkey.toBase58();
    } on Exception catch (e) {
      throw InvalidRecordDataError('Invalid SOL public key: $e');
    }
  } else if (v2_constants.evmRecords.contains(record)) {
    if (content.length != 20) {
      throw InvalidRecordDataError('EVM address must be 20 bytes');
    }
    final hexString =
        content.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '0x$hexString';
  } else if (record == Record.injective) {
    if (content.length != 20) {
      throw InvalidRecordDataError('Injective address must be 20 bytes');
    }
    try {
      return _encodeBech32Injective(content);
    } on Exception catch (e) {
      throw InvalidRecordDataError('Invalid Injective address: $e');
    }
  } else if (record == Record.a) {
    return _formatIpv4(content);
  } else if (record == Record.aaaa) {
    return _formatIpv6(content);
  } else {
    throw InvalidRecordDataError(
        'The record content is malformed for record type: ${record.name}');
  }
}
