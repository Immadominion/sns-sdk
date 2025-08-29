/// Simple bech32 decoding utilities
///
/// Provides basic bech32 decoding for Injective addresses.
/// This is a simplified implementation for SNS purposes.
library;

/// Result of bech32 decoding
class Bech32DecodeResult {
  const Bech32DecodeResult(this.hrp, this.data);
  final String hrp;
  final List<int> data;
}

/// Simple bech32 decoder for Injective addresses
class SimpleBech32 {
  static const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  /// Converts 5-bit data to 8-bit data
  static List<int> convertBits(
      List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final maxv = (1 << toBits) - 1;
    final maxAcc = (1 << (fromBits + toBits - 1)) - 1;
    final result = <int>[];

    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw ArgumentError('Invalid data for convertBits');
      }
      acc = ((acc << fromBits) | value) & maxAcc;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw ArgumentError('Invalid padding in convertBits');
    }

    return result;
  }

  /// Decodes a bech32 string and returns HRP and data
  static Bech32DecodeResult decode(String input) {
    if (input.length < 8 || input.length > 90) {
      throw ArgumentError('Invalid bech32 string length');
    }

    input = input.toLowerCase();
    final pos = input.lastIndexOf('1');
    if (pos < 1 || pos + 7 > input.length) {
      throw ArgumentError('Invalid bech32 separator position');
    }

    final hrp = input.substring(0, pos);
    final data = input.substring(pos + 1);

    // Decode data part
    final decoded = <int>[];
    for (var i = 0; i < data.length; i++) {
      final charIndex = _charset.indexOf(data[i]);
      if (charIndex == -1) {
        throw ArgumentError('Invalid character in bech32 data');
      }
      decoded.add(charIndex);
    }

    // Remove checksum (last 6 characters)
    if (decoded.length < 6) {
      throw ArgumentError('Invalid bech32 data length');
    }
    final payload = decoded.sublist(0, decoded.length - 6);

    // Convert 5-bit to 8-bit
    final converted = convertBits(payload, 5, 8, false);

    return Bech32DecodeResult(hrp, converted);
  }
}
