import 'dart:async';

import '../rpc/rpc_client.dart';

/// Solana Name Service (SNS) client with built-in caching and performance optimizations.
///
/// Provides efficient access to SNS operations with configurable caching behavior
/// to reduce network traffic and improve response times. The client wraps an RPC
/// client and adds intelligent caching for domain resolution and record lookups.
///
/// Example:
/// ```dart
/// final rpc = HttpRpcClient('https://api.mainnet-beta.solana.com');
/// final client = SnsClient(rpc, maxCacheSize: 500);
///
/// final owner = await resolve(client, 'domain');
/// ```
class SnsClient {
  /// Creates a new SNS client with configurable caching options.
  ///
  /// [_rpc] The RPC client to use for network communication.
  /// [maxCacheSize] Maximum number of entries to keep in cache (defaults to 1000).
  /// [defaultTtl] Default time-to-live for cache entries (defaults to 5 minutes).
  SnsClient(
    this._rpc, {
    int maxCacheSize = 1000,
    Duration defaultTtl = const Duration(minutes: 5),
  })  : _maxCacheSize = maxCacheSize,
        _defaultTtl = defaultTtl;
  final RpcClient _rpc;
  final Map<String, CacheEntry> _cache = {};
  final int _maxCacheSize;
  final Duration _defaultTtl;

  /// Returns the underlying RPC client used for network communication.
  RpcClient get rpc => _rpc;

  /// Executes a function with caching based on a key and time-to-live (TTL).
  ///
  /// Provides intelligent caching that checks for valid cached entries before
  /// making network calls. Automatically manages cache size and evicts expired entries.
  ///
  /// [key] The cache key to use for lookup and storage.
  /// [call] The function to execute if cache miss occurs.
  /// [ttl] Optional TTL override (defaults to instance default TTL).
  ///
  /// Returns the cached or freshly retrieved result of type [T].
  Future<T> _cachedCall<T>(
    String key,
    Future<T> Function() call, {
    Duration? ttl,
  }) async {
    final effectiveTtl = ttl ?? _defaultTtl;
    final now = DateTime.now();

    // Check if we have a valid cached entry
    final entry = _cache[key];
    if (entry != null && now.isBefore(entry.expiresAt)) {
      return entry.value as T;
    }

    // Make the call and cache the result
    final result = await call();

    // Manage cache size
    if (_cache.length >= _maxCacheSize) {
      _evictOldestEntries();
    }

    _cache[key] = CacheEntry(
      value: result,
      createdAt: now,
      expiresAt: now.add(effectiveTtl),
    );

    return result;
  }

  /// Get account information with caching
  Future<AccountInfo> getAccountInfo(String address) async => _cachedCall(
        'account_info_$address',
        () => _rpc.fetchEncodedAccount(address),
      );

  /// Evict oldest cache entries when cache is full
  void _evictOldestEntries() {
    final entries = _cache.entries.toList();
    entries.sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));

    // Remove oldest 20% of entries
    final toRemove = (_maxCacheSize * 0.2).ceil();
    for (var i = 0; i < toRemove && entries.isNotEmpty; i++) {
      _cache.remove(entries[i].key);
    }
  }

  /// Clear the cache
  void clearCache() {
    _cache.clear();
  }

  /// Clear specific cache entries by pattern
  void clearCachePattern(String pattern) {
    final regex = RegExp(pattern);
    _cache.removeWhere((key, value) => regex.hasMatch(key));
  }

  /// Get cache statistics
  CacheStats getCacheStats() {
    final now = DateTime.now();
    var validEntries = 0;
    var expiredEntries = 0;

    for (final entry in _cache.values) {
      if (now.isBefore(entry.expiresAt)) {
        validEntries++;
      } else {
        expiredEntries++;
      }
    }

    return CacheStats(
      totalEntries: _cache.length,
      validEntries: validEntries,
      expiredEntries: expiredEntries,
      maxSize: _maxCacheSize,
    );
  }

  /// Background processing for long operations
  Stream<DomainEvent> watchDomainChanges(String domain) async* {
    // This would implement WebSocket or polling-based real-time updates
    // For now, we'll simulate with periodic checks
    while (true) {
      await Future.delayed(const Duration(seconds: 30));

      try {
        // In a real implementation, this would listen to blockchain events
        yield DomainEvent(
          domain: domain,
          eventType: DomainEventType.updated,
          timestamp: DateTime.now(),
        );
      } on Exception catch (e) {
        yield DomainEvent(
          domain: domain,
          eventType: DomainEventType.error,
          timestamp: DateTime.now(),
          error: e.toString(),
        );
      }
    }
  }
}

/// Cache entry with TTL
class CacheEntry {
  const CacheEntry({
    required this.value,
    required this.createdAt,
    required this.expiresAt,
  });
  final dynamic value;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// Cache statistics
class CacheStats {
  const CacheStats({
    required this.totalEntries,
    required this.validEntries,
    required this.expiredEntries,
    required this.maxSize,
  });
  final int totalEntries;
  final int validEntries;
  final int expiredEntries;
  final int maxSize;

  double get hitRatio => totalEntries > 0 ? validEntries / totalEntries : 0.0;
  double get fillRatio => maxSize > 0 ? totalEntries / maxSize : 0.0;

  @override
  String toString() => 'CacheStats(total: $totalEntries, valid: $validEntries, '
      'expired: $expiredEntries, hit ratio: ${(hitRatio * 100).toStringAsFixed(1)}%, '
      'fill ratio: ${(fillRatio * 100).toStringAsFixed(1)}%)';
}

/// Domain event for real-time updates
class DomainEvent {
  const DomainEvent({
    required this.domain,
    required this.eventType,
    required this.timestamp,
    this.error,
    this.data,
  });
  final String domain;
  final DomainEventType eventType;
  final DateTime timestamp;
  final String? error;
  final Map<String, dynamic>? data;
}

/// Types of domain events
enum DomainEventType {
  created,
  updated,
  transferred,
  burned,
  recordUpdated,
  error,
}
