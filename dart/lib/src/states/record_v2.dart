import 'dart:typed_data';
import '../rpc/rpc_client.dart';
import '../types/validation.dart';

/// The length of the NAME_REGISTRY data structure (96 bytes)
///
/// This critical offset mirrors js-kit/src/states/record.ts NAME_REGISTRY_LEN
const int NAME_REGISTRY_LEN = 96;

/// Record header state for Record V2 following JavaScript SDK structure
///
/// Mirrors js-kit/src/states/record.ts RecordHeaderState class
class RecordHeaderState {
  const RecordHeaderState({
    required this.stalenessValidation,
    required this.rightOfAssociationValidation,
    required this.contentLength,
  });

  /// Staleness validation type (u16)
  final int stalenessValidation;

  /// Right of Association validation type (u16)
  final int rightOfAssociationValidation;

  /// Content length in bytes (u32)
  final int contentLength;

  /// The total length of the RecordHeaderState struct in bytes
  /// Calculated as: stalenessValidation(2) + rightOfAssociationValidation(2) + contentLength(4) = 8 bytes
  static const int LEN = 8;

  /// Deserialize RecordHeaderState from raw bytes using Borsh format
  ///
  /// Mirrors js-kit/src/states/record.ts RecordHeaderState.deserialize
  static RecordHeaderState deserialize(Uint8List data) {
    if (data.length < LEN) {
      throw ArgumentError(
          'Record header data too short: ${data.length} < $LEN');
    }

    // Parse Borsh format: u16 + u16 + u32 (little-endian)
    final stalenessValidation = data[0] | (data[1] << 8);
    final rightOfAssociationValidation = data[2] | (data[3] << 8);
    final contentLength =
        data[4] | (data[5] << 8) | (data[6] << 16) | (data[7] << 24);

    return RecordHeaderState(
      stalenessValidation: stalenessValidation,
      rightOfAssociationValidation: rightOfAssociationValidation,
      contentLength: contentLength,
    );
  }

  /// Retrieve RecordHeaderState from account address
  ///
  /// Mirrors js-kit/src/states/record.ts RecordHeaderState.retrieve
  static Future<RecordHeaderState> retrieve(
    RpcClient rpc,
    String address,
  ) async {
    final accountInfo = await rpc.fetchEncodedAccount(address);

    if (!accountInfo.exists) {
      throw Exception('Record header account not found');
    }

    // Extract header data at NAME_REGISTRY_LEN offset
    final headerData = Uint8List.fromList(
      accountInfo.data.sublist(NAME_REGISTRY_LEN, NAME_REGISTRY_LEN + LEN),
    );

    return deserialize(headerData);
  }

  /// Check if both validation methods are Solana (value 1)
  bool get isSolanaValidation =>
      stalenessValidation == 1 && rightOfAssociationValidation == 1;
}

/// Record V2 state implementation following JavaScript SDK structure
///
/// Mirrors js-kit/src/states/record.ts RecordState class with proper offset handling
class RecordState {
  const RecordState({
    required this.header,
    required this.data,
  });

  /// Record header containing validation info and content length
  final RecordHeaderState header;

  /// Raw record data (after NAME_REGISTRY_LEN + RecordHeaderState.LEN offset)
  final Uint8List data;

  /// Deserialize RecordState from account data
  ///
  /// Mirrors js-kit/src/states/record.ts RecordState.deserialize with proper NAME_REGISTRY_LEN offset
  static RecordState deserialize(Uint8List accountData) {
    if (accountData.length < NAME_REGISTRY_LEN + RecordHeaderState.LEN) {
      throw ArgumentError(
          'Record account data too short: ${accountData.length} < ${NAME_REGISTRY_LEN + RecordHeaderState.LEN}');
    }

    // Parse header at NAME_REGISTRY_LEN offset
    final headerData = accountData.sublist(
      NAME_REGISTRY_LEN,
      NAME_REGISTRY_LEN + RecordHeaderState.LEN,
    );
    final header = RecordHeaderState.deserialize(headerData);

    // Extract data after header
    const dataOffset = NAME_REGISTRY_LEN + RecordHeaderState.LEN;
    final data = accountData.sublist(dataOffset);

    return RecordState(header: header, data: data);
  }

  /// Retrieve RecordState from account address
  ///
  /// Mirrors js-kit/src/states/record.ts RecordState.retrieve
  static Future<RecordState> retrieve(
    RpcClient rpc,
    String address,
  ) async {
    final accountInfo = await rpc.fetchEncodedAccount(address);

    if (!accountInfo.exists) {
      throw Exception('Record account not found');
    }

    return deserialize(Uint8List.fromList(accountInfo.data));
  }

  /// Retrieve multiple RecordState instances in batch
  ///
  /// Mirrors js-kit/src/states/record.ts RecordState.retrieveBatch
  static Future<List<RecordState?>> retrieveBatch(
    RpcClient rpc,
    List<String> addresses,
  ) async {
    final accountInfos = await rpc.fetchEncodedAccounts(addresses);

    return accountInfos.map((accountInfo) {
      if (!accountInfo.exists) return null;
      return deserialize(Uint8List.fromList(accountInfo.data));
    }).toList();
  }

  /// Get content data (after staleness and RoA validation data)
  ///
  /// Mirrors js-kit/src/states/record.ts RecordState.getContent
  Uint8List getContent() {
    final stalenessLength =
        getValidationLengthFromValue(header.stalenessValidation);
    final roaLength =
        getValidationLengthFromValue(header.rightOfAssociationValidation);
    final startOffset = stalenessLength + roaLength;

    if (startOffset >= data.length) return Uint8List(0);
    return data.sublist(startOffset);
  }

  /// Get staleness validation ID
  ///
  /// Mirrors js-kit/src/states/record.ts RecordState.getStalenessId
  Uint8List getStalenessId() {
    final endOffset = getValidationLengthFromValue(header.stalenessValidation);
    if (endOffset == 0 || endOffset > data.length) return Uint8List(0);
    return data.sublist(0, endOffset);
  }

  /// Get Right of Association validation ID
  ///
  /// Mirrors js-kit/src/states/record.ts RecordState.getRoAId
  Uint8List getRoAId() {
    final stalenessLength =
        getValidationLengthFromValue(header.stalenessValidation);
    final roaLength =
        getValidationLengthFromValue(header.rightOfAssociationValidation);

    if (roaLength == 0) return Uint8List(0);

    final startOffset = stalenessLength;
    final endOffset = startOffset + roaLength;

    if (endOffset > data.length) return Uint8List(0);
    return data.sublist(startOffset, endOffset);
  }
}
