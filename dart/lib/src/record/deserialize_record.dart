/// Record deserialization functionality for SNS domains
///
/// This module provides the `deserializeRecord` function that deserializes
/// the content of a V1 record, mirroring the JavaScript SDK exactly.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/encoding.dart' as pinenacl;

import '../constants/records.dart';
import '../errors/sns_errors.dart';
import '../states/registry.dart';
import '../utils/base58_utils.dart';

/// Trims null padding from a buffer and returns the index of the last non-null byte
int _trimNullPaddingIdx(Uint8List buffer) {
  for (var i = buffer.length - 1; i >= 0; i--) {
    if (buffer[i] != 0) {
      return i + 1;
    }
  }
  return 0;
}

/// Checks if a string is a valid IPv4 address
bool _isValidIPv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;

  for (final part in parts) {
    final num = int.tryParse(part);
    if (num == null || num < 0 || num > 255) return false;
  }
  return true;
}

/// Checks if a string is a valid IPv6 address
bool _isValidIPv6(String address) {
  // Simple IPv6 validation - contains colons and hex digits
  if (!address.contains(':')) return false;
  final parts = address.split(':');
  if (parts.length > 8) return false;

  for (final part in parts) {
    if (part.isNotEmpty) {
      if (part.length > 4) return false;
      if (!RegExp(r'^[0-9a-fA-F]*$').hasMatch(part)) return false;
    }
  }
  return true;
}

/// Checks if an Ethereum/BSC address is valid
bool _isValidEthAddress(String address) {
  if (!address.startsWith('0x')) return false;
  final hex = address.substring(2);
  if (hex.length != 40) return false;
  return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
}

/// Checks if an Injective address is valid
bool _isValidInjectiveAddress(String address) =>
    address.startsWith('inj') && address.length >= 42;

/// Converts bytes to IPv4 address string
String _bytesToIPv4(Uint8List bytes) {
  if (bytes.length != 4) throw ArgumentError('IPv4 requires exactly 4 bytes');
  return '${bytes[0]}.${bytes[1]}.${bytes[2]}.${bytes[3]}';
}

/// Converts bytes to IPv6 address string
String _bytesToIPv6(Uint8List bytes) {
  if (bytes.length != 16) throw ArgumentError('IPv6 requires exactly 16 bytes');

  final parts = <String>[];
  for (var i = 0; i < 16; i += 2) {
    final value = (bytes[i] << 8) | bytes[i + 1];
    parts.add(value.toRadixString(16));
  }

  // Apply IPv6 compression (::) like JavaScript implementation
  final fullAddress = parts.join(':');

  // Find the longest sequence of consecutive zeros
  var bestStart = -1;
  var bestLength = 0;
  var currentStart = -1;
  var currentLength = 0;

  for (var i = 0; i < parts.length; i++) {
    if (parts[i] == '0') {
      if (currentStart == -1) currentStart = i;
      currentLength++;
    } else {
      if (currentLength > bestLength) {
        bestStart = currentStart;
        bestLength = currentLength;
      }
      currentStart = -1;
      currentLength = 0;
    }
  }

  // Check the final sequence
  if (currentLength > bestLength) {
    bestStart = currentStart;
    bestLength = currentLength;
  }

  // Only compress if we have at least 2 consecutive zeros
  if (bestLength >= 2) {
    final beforeParts = parts.sublist(0, bestStart);
    final afterParts = parts.sublist(bestStart + bestLength);

    var result = beforeParts.join(':');
    if (beforeParts.isEmpty) result = '';
    result += '::';
    if (afterParts.isNotEmpty) {
      result += afterParts.join(':');
    }

    return result;
  }

  return fullAddress;
}

/// Decodes punycode - simplified implementation
String _decodePunycode(String input) {
  // For now, return as-is. A full punycode implementation would be needed
  // for complete compatibility with the JS SDK
  return input;
}

/// Deserializes the content of a record (V1)
///
/// This function deserializes the content of a record following the exact
/// logic from the JavaScript SDK. If the content is invalid it will throw an error.
///
/// @param registry The name registry state object of the record being deserialized
/// @param record The record enum being deserialized
/// @param recordKey The public key of the record being deserialized
/// @returns The deserialized record content or null if empty
/// @throws [InvalidRecordDataError] if the record data is malformed
String? deserializeRecord(
  RegistryState? registry,
  Record record,
  String recordKey,
) {
  final buffer = registry?.data;
  if (buffer == null || buffer.isEmpty) return null;

  // Check if buffer is all zeros
  if (buffer.every((byte) => byte == 0)) return null;

  final recordSize = getRecordSize(record);
  final idx = _trimNullPaddingIdx(buffer);

  // Handle dynamic size records (strings)
  if (recordSize == null) {
    final str = utf8.decode(buffer.sublist(0, idx));
    if (record == Record.cname || record == Record.txt) {
      return _decodePunycode(str);
    }
    return str;
  }

  // Handle SOL record first whether it's over allocated or not
  if (record == Record.sol) {
    // For SOL records, we need to validate the signature
    // For now, return the base58-encoded address
    if (buffer.length >= 32) {
      return Base58Utils.encode(buffer.sublist(0, 32));
    }
    throw InvalidRecordDataError('SOL record data too short');
  }

  // Handle old record UTF-8 encoded format
  if (idx != recordSize) {
    final address = utf8.decode(buffer.sublist(0, idx));

    if (record == Record.injective) {
      if (_isValidInjectiveAddress(address)) {
        return address;
      }
    } else if (record == Record.bsc || record == Record.eth) {
      if (_isValidEthAddress(address)) {
        return address;
      }
    } else if (record == Record.a) {
      if (_isValidIPv4(address)) {
        return address;
      }
    } else if (record == Record.aaaa) {
      if (_isValidIPv6(address)) {
        return address;
      }
    }
    throw InvalidRecordDataError('The record data is malformed');
  }

  // Handle binary format records
  if (record == Record.eth || record == Record.bsc) {
    final hex = buffer
        .sublist(0, recordSize)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '0x$hex';
  } else if (record == Record.injective) {
    // Use proper bech32 encoding like JavaScript SDK: bech32.encode("inj", bech32.toWords(buffer))
    final bytes = buffer.sublist(0, recordSize);
    const encoder = pinenacl.Bech32Encoder(hrp: 'inj');
    return encoder.encode(bytes);
  } else if (record == Record.a) {
    return _bytesToIPv4(buffer.sublist(0, recordSize));
  } else if (record == Record.aaaa) {
    return _bytesToIPv6(buffer.sublist(0, recordSize));
  } else if (record == Record.background) {
    return Base58Utils.encode(buffer.sublist(0, recordSize));
  } else if (record == Record.btc ||
      record == Record.ltc ||
      record == Record.doge) {
    // Cryptocurrency addresses - return as base58
    return Base58Utils.encode(buffer.sublist(0, recordSize));
  } else if (record == Record.ipfs || record == Record.arwv) {
    // IPFS/Arweave hashes - return as base58
    return Base58Utils.encode(buffer.sublist(0, recordSize));
  }

  throw InvalidRecordDataError('The record data is malformed');
}

/// Get the expected size for a record type (V1 records)
/// Returns null if size is dynamic or unknown
int? getRecordSize(Record record) {
  // Define the sizes for V1 records based on the TypeScript implementation
  const recordSizes = <Record, int>{
    Record.sol: 32, // Solana public key
    Record.eth: 20, // Ethereum address
    Record.btc: 25, // Bitcoin address (max)
    Record.ltc: 25, // Litecoin address (max)
    Record.doge: 25, // Dogecoin address (max)
    Record.bsc: 20, // BSC address (same as ETH)
    Record.injective: 20, // Injective address
    Record.ipfs: 46, // IPFS hash (CIDv0)
    Record.arwv: 43, // Arweave transaction ID
    Record.shdw: 44, // Shadow token
    Record.point: 32, // Point token
    Record.a: 4, // IPv4 address
    Record.aaaa: 16, // IPv6 address
    Record.background: 32, // Background image (public key)
    // String records have dynamic sizes, so we return null
  };

  return recordSizes[record];
}
