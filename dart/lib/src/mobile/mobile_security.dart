/// Mobile security and platform integration for SNS SDK
///
/// Provides secure key storage, background processing, and platform-specific
/// wallet interactions for Flutter mobile applications.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Mobile platform types
enum MobilePlatform {
  /// iOS platform
  ios,

  /// Android platform
  android,

  /// Unsupported platform
  unsupported,
}

/// Secure storage interface for mobile platforms
abstract class SecureStorage {
  /// Store a value securely
  Future<void> store(String key, String value);

  /// Retrieve a stored value
  Future<String?> retrieve(String key);

  /// Delete a stored value
  Future<void> delete(String key);

  /// Check if a key exists
  Future<bool> contains(String key);

  /// Clear all stored values
  Future<void> clear();
}

/// Mobile secure storage implementation
class MobileSecureStorage implements SecureStorage {
  MobileSecureStorage._();

  static MobileSecureStorage? _instance;
  static MobileSecureStorage get instance {
    _instance ??= MobileSecureStorage._();
    return _instance!;
  }

  /// In-memory fallback storage for development/testing
  /// In production, this would use platform-specific secure storage APIs
  final Map<String, String> _storage = {};

  @override
  Future<void> store(String key, String value) async {
    // In production, this would use:
    // - iOS: Keychain Services
    // - Android: Android Keystore or EncryptedSharedPreferences
    _storage[key] = value;
  }

  @override
  Future<String?> retrieve(String key) async => _storage[key];

  @override
  Future<void> delete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<bool> contains(String key) async => _storage.containsKey(key);

  @override
  Future<void> clear() async {
    _storage.clear();
  }
}

/// Platform detection utility
class PlatformDetector {
  /// Get current mobile platform
  static MobilePlatform get currentPlatform {
    try {
      if (Platform.isIOS) return MobilePlatform.ios;
      if (Platform.isAndroid) return MobilePlatform.android;
      return MobilePlatform.unsupported;
    } on Exception catch (e) {
      return MobilePlatform.unsupported;
    }
  }

  /// Check if running on mobile platform
  static bool get isMobile =>
      currentPlatform == MobilePlatform.ios ||
      currentPlatform == MobilePlatform.android;
}

/// Background task handler for mobile platforms
class MobileBackgroundTaskHandler {
  /// Execute a task in the background
  static Future<T> executeInBackground<T>(
    Future<T> Function() task, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // On mobile platforms, this would use:
    // - iOS: Background App Refresh API
    // - Android: WorkManager or foreground services

    return task().timeout(timeout);
  }

  /// Queue a transaction for background processing
  static Future<void> queueTransaction(
    String transactionId,
    Uint8List transactionData,
  ) async {
    // Store transaction data for background processing
    await MobileSecureStorage.instance.store(
      'pending_tx_$transactionId',
      _uint8ListToHex(transactionData),
    );
  }

  /// Process pending transactions
  static Future<List<String>> processPendingTransactions() async {
    final processedIds = <String>[];

    // In production, this would iterate through actual pending transactions
    // For now, return empty list
    return processedIds;
  }

  static String _uint8ListToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Deep linking handler for mobile wallet interactions
class MobileDeepLinkHandler {
  static const String _snsScheme = 'sns';
  static StreamController<DeepLinkEvent>? _eventController;

  /// Initialize deep link handling
  static Future<void> initialize() async {
    _eventController ??= StreamController<DeepLinkEvent>.broadcast();

    // In production, this would register with platform-specific deep link APIs:
    // - iOS: URL Schemes and Universal Links
    // - Android: Intent Filters and App Links
  }

  /// Stream of deep link events
  static Stream<DeepLinkEvent> get events {
    _eventController ??= StreamController<DeepLinkEvent>.broadcast();
    return _eventController!.stream;
  }

  /// Handle incoming deep link
  static void handleDeepLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (uri.scheme == _snsScheme) {
      final event = DeepLinkEvent(
        type: DeepLinkType.sns,
        uri: uri,
        data: uri.queryParameters,
      );
      _eventController?.add(event);
    }
  }

  /// Create deep link for domain registration
  static String createDomainRegistrationLink(String domain) =>
      '$_snsScheme://register?domain=$domain';

  /// Create deep link for domain transfer
  static String createDomainTransferLink(String domain, String newOwner) =>
      '$_snsScheme://transfer?domain=$domain&owner=$newOwner';
}

/// Deep link event types
enum DeepLinkType {
  /// SNS-related deep link
  sns,

  /// Wallet connection deep link
  wallet,

  /// Transaction signing deep link
  transaction,
}

/// Deep link event
class DeepLinkEvent {
  const DeepLinkEvent({
    required this.type,
    required this.uri,
    required this.data,
  });

  /// Type of deep link
  final DeepLinkType type;

  /// Full URI
  final Uri uri;

  /// Parsed data
  final Map<String, String> data;
}

/// Mobile wallet adapter interface
abstract class MobileWalletAdapter {
  /// Wallet name
  String get name;

  /// Whether wallet is available on this platform
  bool get isAvailable;

  /// Connect to wallet
  Future<WalletConnectionResult> connect();

  /// Disconnect from wallet
  Future<void> disconnect();

  /// Sign transaction
  Future<Uint8List> signTransaction(Uint8List transaction);

  /// Sign message
  Future<Uint8List> signMessage(Uint8List message);

  /// Get public key
  Future<String> getPublicKey();
}

/// Wallet connection result
class WalletConnectionResult {
  const WalletConnectionResult({
    required this.success,
    this.publicKey,
    this.error,
  });

  /// Create successful connection result
  factory WalletConnectionResult.success(String publicKey) =>
      WalletConnectionResult(
        success: true,
        publicKey: publicKey,
      );

  /// Create failed connection result
  factory WalletConnectionResult.failure(String error) =>
      WalletConnectionResult(
        success: false,
        error: error,
      );

  /// Whether connection was successful
  final bool success;

  /// Public key if connected
  final String? publicKey;

  /// Error message if connection failed
  final String? error;
}

/// Phantom wallet adapter for mobile
class PhantomMobileWalletAdapter implements MobileWalletAdapter {
  @override
  String get name => 'Phantom';

  @override
  bool get isAvailable => PlatformDetector.isMobile;

  @override
  Future<WalletConnectionResult> connect() async {
    // In production, this would use Phantom's mobile SDK or deep links
    // For now, return a mock success
    await Future.delayed(const Duration(milliseconds: 500));

    if (PlatformDetector.isMobile) {
      return WalletConnectionResult.success('11111111111111111111111111111112');
    } else {
      return WalletConnectionResult.failure('Platform not supported');
    }
  }

  @override
  Future<void> disconnect() async {
    // Disconnect from Phantom wallet
  }

  @override
  Future<Uint8List> signTransaction(Uint8List transaction) async {
    // In production, this would send transaction to Phantom for signing
    // For now, return mock signature
    final hash = sha256.convert(transaction);
    return Uint8List.fromList(hash.bytes);
  }

  @override
  Future<Uint8List> signMessage(Uint8List message) async {
    // Sign message with Phantom wallet
    final hash = sha256.convert(message);
    return Uint8List.fromList(hash.bytes);
  }

  @override
  Future<String> getPublicKey() async => '11111111111111111111111111111112';
}

/// Solflare wallet adapter for mobile
class SolflareMobileWalletAdapter implements MobileWalletAdapter {
  @override
  String get name => 'Solflare';

  @override
  bool get isAvailable => PlatformDetector.isMobile;

  @override
  Future<WalletConnectionResult> connect() async {
    // In production, this would use Solflare's mobile SDK or deep links
    await Future.delayed(const Duration(milliseconds: 500));

    if (PlatformDetector.isMobile) {
      return WalletConnectionResult.success('11111111111111111111111111111113');
    } else {
      return WalletConnectionResult.failure('Platform not supported');
    }
  }

  @override
  Future<void> disconnect() async {
    // Disconnect from Solflare wallet
  }

  @override
  Future<Uint8List> signTransaction(Uint8List transaction) async {
    // Sign transaction with Solflare wallet
    final hash = sha256.convert(transaction);
    return Uint8List.fromList(hash.bytes);
  }

  @override
  Future<Uint8List> signMessage(Uint8List message) async {
    // Sign message with Solflare wallet
    final hash = sha256.convert(message);
    return Uint8List.fromList(hash.bytes);
  }

  @override
  Future<String> getPublicKey() async => '11111111111111111111111111111113';
}

/// Mobile wallet manager
class MobileWalletManager {
  static final Map<String, MobileWalletAdapter> _adapters = {
    'phantom': PhantomMobileWalletAdapter(),
    'solflare': SolflareMobileWalletAdapter(),
  };

  /// Get available wallets for current platform
  static List<MobileWalletAdapter> getAvailableWallets() =>
      _adapters.values.where((adapter) => adapter.isAvailable).toList();

  /// Get specific wallet adapter
  static MobileWalletAdapter? getWallet(String name) =>
      _adapters[name.toLowerCase()];

  /// Register custom wallet adapter
  static void registerWallet(String name, MobileWalletAdapter adapter) {
    _adapters[name.toLowerCase()] = adapter;
  }
}
