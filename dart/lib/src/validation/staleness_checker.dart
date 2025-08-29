import 'dart:typed_data';
import '../rpc/rpc_client.dart';

/// Parameters for staleness checking
class StalenessCheckParams {
  const StalenessCheckParams({
    required this.rpcClient,
    required this.recordAddress,
    this.maxStalenessSeconds = 300, // 5 minutes default
  });

  /// RPC client for blockchain queries
  final RpcClient rpcClient;

  /// The record address to check for staleness
  final String recordAddress;

  /// Maximum allowed staleness in seconds (default: 300 = 5 minutes)
  final int maxStalenessSeconds;
}

/// Result of staleness validation
class StalenessResult {
  const StalenessResult({
    required this.isStale,
    required this.ageSeconds,
    required this.stalenessThreshold,
    this.lastUpdated,
  });

  /// Whether the record is considered stale
  final bool isStale;

  /// The age of the record in seconds
  final int ageSeconds;

  /// The timestamp when the record was last updated
  final DateTime? lastUpdated;

  /// The threshold used for staleness checking
  final int stalenessThreshold;

  @override
  String toString() =>
      'StalenessResult(isStale: $isStale, ageSeconds: $ageSeconds, '
      'lastUpdated: $lastUpdated, threshold: $stalenessThreshold)';
}

/// Staleness checking mechanisms for SNS records
///
/// This class provides functionality to check if SNS records are stale,
/// particularly important for price feed validation and ROA verification.
/// It integrates with Pyth price feeds and other oracle systems to ensure
/// data freshness.
class StalenessChecker {
  /// Check if a record is stale based on its last update time
  ///
  /// This method fetches the record account data and analyzes its timestamp
  /// to determine if it exceeds the staleness threshold.
  ///
  /// Returns [StalenessResult] with staleness information.
  static Future<StalenessResult> checkRecordStaleness(
    StalenessCheckParams params,
  ) async {
    try {
      // Fetch the record account data
      final accountInfo = await params.rpcClient.fetchEncodedAccount(
        params.recordAddress,
      );

      if (!accountInfo.exists || accountInfo.data.isEmpty) {
        // If no account data, consider it stale
        return StalenessResult(
          isStale: true,
          ageSeconds: params.maxStalenessSeconds + 1,
          stalenessThreshold: params.maxStalenessSeconds,
        );
      }

      // Parse the record timestamp from account data
      // The timestamp is typically stored in the first 8 bytes as a u64
      final timestamp =
          _parseTimestampFromAccountData(Uint8List.fromList(accountInfo.data));
      final currentTime = DateTime.now();
      final lastUpdated = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      final ageSeconds = currentTime.difference(lastUpdated).inSeconds;

      final isStale = ageSeconds > params.maxStalenessSeconds;

      return StalenessResult(
        isStale: isStale,
        ageSeconds: ageSeconds,
        lastUpdated: lastUpdated,
        stalenessThreshold: params.maxStalenessSeconds,
      );
    } on Exception catch (e) {
      // On error, consider the record stale for safety
      return StalenessResult(
        isStale: true,
        ageSeconds: params.maxStalenessSeconds + 1,
        stalenessThreshold: params.maxStalenessSeconds,
      );
    }
  }

  /// Check multiple records for staleness in batch
  ///
  /// This method efficiently checks staleness for multiple records
  /// using batch RPC requests to improve performance.
  static Future<Map<String, StalenessResult>> checkMultipleRecordStaleness(
    RpcClient rpcClient,
    List<String> recordAddresses, {
    int maxStalenessSeconds = 300,
  }) async {
    final results = <String, StalenessResult>{};

    // Process in batches to avoid overwhelming the RPC
    const batchSize = 10;
    for (var i = 0; i < recordAddresses.length; i += batchSize) {
      final batch = recordAddresses.skip(i).take(batchSize).toList();

      // Check each record in the current batch
      final batchResults = await Future.wait(
        batch.map((address) => checkRecordStaleness(
              StalenessCheckParams(
                rpcClient: rpcClient,
                recordAddress: address,
                maxStalenessSeconds: maxStalenessSeconds,
              ),
            )),
      );

      // Add batch results to the final map
      for (var j = 0; j < batch.length; j++) {
        results[batch[j]] = batchResults[j];
      }
    }

    return results;
  }

  /// Validate Pyth price feed staleness
  ///
  /// This method specifically checks Pyth price feed accounts for staleness,
  /// which is critical for price-based validations in SNS.
  static Future<StalenessResult> validatePythFeedStaleness({
    required RpcClient rpcClient,
    required String pythPriceAccount,
    int maxStalenessSeconds = 60, // Pyth feeds should be very fresh
  }) async {
    try {
      final accountInfo = await rpcClient.fetchEncodedAccount(pythPriceAccount);

      if (!accountInfo.exists || accountInfo.data.isEmpty) {
        return StalenessResult(
          isStale: true,
          ageSeconds: maxStalenessSeconds + 1,
          stalenessThreshold: maxStalenessSeconds,
        );
      }

      // Parse Pyth price feed timestamp (specific to Pyth format)
      final timestamp =
          _parsePythTimestamp(Uint8List.fromList(accountInfo.data));
      final currentTime = DateTime.now();
      final lastUpdated = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      final ageSeconds = currentTime.difference(lastUpdated).inSeconds;

      final isStale = ageSeconds > maxStalenessSeconds;

      return StalenessResult(
        isStale: isStale,
        ageSeconds: ageSeconds,
        lastUpdated: lastUpdated,
        stalenessThreshold: maxStalenessSeconds,
      );
    } on Exception catch (e) {
      return StalenessResult(
        isStale: true,
        ageSeconds: maxStalenessSeconds + 1,
        stalenessThreshold: maxStalenessSeconds,
      );
    }
  }

  /// Parse timestamp from generic account data
  ///
  /// Assumes timestamp is stored as a little-endian u64 in the first 8 bytes
  static int _parseTimestampFromAccountData(Uint8List data) {
    if (data.length < 8) {
      throw ArgumentError('Account data too short to contain timestamp');
    }

    final byteData = ByteData.sublistView(data, 0, 8);
    return byteData.getUint64(0, Endian.little);
  }

  /// Parse timestamp from Pyth price feed data
  ///
  /// Pyth price feeds have a specific data format where the timestamp
  /// is located at a specific offset within the account data structure.
  static int _parsePythTimestamp(Uint8List data) {
    // Pyth price feed structure (simplified):
    // - Account type (4 bytes)
    // - Version (4 bytes)
    // - Price data structure...
    // - Timestamp at offset 208 (8 bytes, little-endian)

    const timestampOffset = 208;
    if (data.length < timestampOffset + 8) {
      throw ArgumentError('Pyth account data too short');
    }

    final byteData =
        ByteData.sublistView(data, timestampOffset, timestampOffset + 8);
    return byteData.getUint64(0, Endian.little);
  }
}
