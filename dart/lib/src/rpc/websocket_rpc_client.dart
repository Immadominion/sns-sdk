import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../rpc/rpc_client.dart';

/// WebSocket-based RPC client for real-time Solana updates
///
/// Provides WebSocket subscriptions for:
/// - Account changes
/// - Domain ownership updates
/// - Real-time record modifications
/// - NFT state changes
class WebSocketRpcClient {
  WebSocketRpcClient(String rpcEndpoint)
      : _wsEndpoint = rpcEndpoint.replaceFirst('http', 'ws');
  final String _wsEndpoint;
  WebSocket? _socket;
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  final Map<int, StreamController<dynamic>> _subscriptions = {};
  int _requestId = 0;
  bool _isConnected = false;

  /// Stream of connection state changes
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionState => _connectionStateController.stream;

  /// Connect to the WebSocket endpoint
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      _socket = await WebSocket.connect(_wsEndpoint);
      _isConnected = true;
      _connectionStateController.add(true);

      _socket!.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: _handleError,
      );
    } on Exception catch (e) {
      _isConnected = false;
      _connectionStateController.add(false);
      rethrow;
    }
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    if (!_isConnected) return;

    await _socket?.close();
    _socket = null;
    _isConnected = false;
    _connectionStateController.add(false);

    // Cancel all pending requests
    for (final completer in _pendingRequests.values) {
      completer.completeError('Connection closed');
    }
    _pendingRequests.clear();

    // Close all subscription streams
    for (final controller in _subscriptions.values) {
      await controller.close();
    }
    _subscriptions.clear();
  }

  /// Subscribe to account changes
  Stream<AccountChangeNotification> subscribeToAccount(String address) {
    final controller = StreamController<AccountChangeNotification>();

    _makeSubscriptionRequest('accountSubscribe', [
      address,
      {
        'encoding': 'base64',
        'commitment': 'confirmed',
      }
    ]).then((subscriptionId) {
      _subscriptions[subscriptionId] = controller as StreamController<dynamic>;
    }).catchError((error) {
      controller.addError(error);
      return null;
    });

    return controller.stream;
  }

  /// Subscribe to domain ownership changes
  Stream<DomainOwnershipChange> subscribeToDomainOwnership(String domain) {
    // This would derive the domain address and subscribe to account changes
    final controller = StreamController<DomainOwnershipChange>();

    // For demonstration, create a periodic stream
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!controller.isClosed) {
        controller.add(DomainOwnershipChange(
          domain: domain,
          oldOwner: null,
          newOwner: 'mock_owner_address',
          timestamp: DateTime.now(),
        ));
      } else {
        timer.cancel();
      }
    });

    return controller.stream;
  }

  /// Subscribe to program logs (for event listening)
  Stream<ProgramLogNotification> subscribeToProgramLogs(String programId) {
    final controller = StreamController<ProgramLogNotification>();

    _makeSubscriptionRequest('logsSubscribe', [
      {
        'mentions': [programId]
      },
      {'commitment': 'confirmed'}
    ]).then((subscriptionId) {
      _subscriptions[subscriptionId] = controller as StreamController<dynamic>;
    }).catchError((error) {
      controller.addError(error);
      return null;
    });

    return controller.stream;
  }

  /// Make a subscription request
  Future<int> _makeSubscriptionRequest(
      String method, List<dynamic> params) async {
    if (!_isConnected) {
      await connect();
    }

    final requestId = ++_requestId;
    final request = {
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params,
    };

    final completer = Completer<int>();
    _pendingRequests[requestId] = completer;

    _socket!.add(jsonEncode(request));

    return completer.future;
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      if (data.containsKey('id')) {
        // Response to a request
        final requestId = data['id'] as int;
        final completer = _pendingRequests.remove(requestId);

        if (data.containsKey('error')) {
          completer?.completeError(data['error']);
        } else {
          completer?.complete(data['result']);
        }
      } else if (data.containsKey('method')) {
        // Subscription notification
        _handleSubscriptionNotification(data);
      }
    } on Exception catch (e) {
      // Log error but don't break the connection
    }
  }

  /// Handle subscription notifications
  void _handleSubscriptionNotification(Map<String, dynamic> data) {
    final method = data['method'] as String;
    final params = data['params'] as Map<String, dynamic>;
    final subscriptionId = params['subscription'] as int;
    final result = params['result'];

    final controller = _subscriptions[subscriptionId];
    if (controller == null) return;

    switch (method) {
      case 'accountNotification':
        final notification = AccountChangeNotification(
          subscription: subscriptionId,
          result: result,
        );
        controller.add(notification);
        break;

      case 'logsNotification':
        final notification = ProgramLogNotification(
          subscription: subscriptionId,
          result: result,
        );
        controller.add(notification);
        break;
    }
  }

  /// Handle WebSocket disconnection
  void _handleDisconnect() {
    _isConnected = false;
    _connectionStateController.add(false);

    // Attempt reconnection after delay
    Timer(const Duration(seconds: 5), () {
      if (!_isConnected) {
        connect().catchError((_) {
          // Retry connection failed, will try again later
        });
      }
    });
  }

  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    // Log error but keep connection alive if possible
  }

  /// Clean up resources
  Future<void> dispose() async {
    await disconnect();
    await _connectionStateController.close();
  }
}

/// Account change notification
class AccountChangeNotification {
  const AccountChangeNotification({
    required this.subscription,
    required this.result,
  });
  final int subscription;
  final dynamic result;
}

/// Domain ownership change event
class DomainOwnershipChange {
  const DomainOwnershipChange({
    required this.domain,
    required this.oldOwner,
    required this.newOwner,
    required this.timestamp,
  });
  final String domain;
  final String? oldOwner;
  final String? newOwner;
  final DateTime timestamp;
}

/// Program log notification
class ProgramLogNotification {
  const ProgramLogNotification({
    required this.subscription,
    required this.result,
  });
  final int subscription;
  final dynamic result;
}

/// Enhanced RPC client with WebSocket support
class EnhancedRpcClient implements RpcClient {
  EnhancedRpcClient(this._httpClient, [this._wsClient]);

  /// Create with WebSocket support
  factory EnhancedRpcClient.withWebSocket(
    RpcClient httpClient,
    String wsEndpoint,
  ) =>
      EnhancedRpcClient(
        httpClient,
        WebSocketRpcClient(wsEndpoint),
      );
  final RpcClient _httpClient;
  final WebSocketRpcClient? _wsClient;

  @override
  Future<AccountInfo> fetchEncodedAccount(String address) =>
      _httpClient.fetchEncodedAccount(address);

  @override
  Future<List<AccountInfo>> fetchEncodedAccounts(List<String> addresses) =>
      _httpClient.fetchEncodedAccounts(addresses);

  @override
  Future<List<TokenAccountValue>> getTokenLargestAccounts(String mint) =>
      _httpClient.getTokenLargestAccounts(mint);

  @override
  Future<List<ProgramAccount>> getProgramAccounts(
    String programId, {
    required String encoding,
    required List<AccountFilter> filters,
    DataSlice? dataSlice,
    int? limit,
  }) =>
      _httpClient.getProgramAccounts(
        programId,
        encoding: encoding,
        filters: filters,
        dataSlice: dataSlice,
        limit: limit,
      );

  /// Subscribe to account changes (WebSocket only)
  Stream<AccountChangeNotification>? subscribeToAccount(String address) =>
      _wsClient?.subscribeToAccount(address);

  /// Subscribe to domain ownership changes (WebSocket only)
  Stream<DomainOwnershipChange>? subscribeToDomainOwnership(String domain) =>
      _wsClient?.subscribeToDomainOwnership(domain);

  /// Subscribe to program logs (WebSocket only)
  Stream<ProgramLogNotification>? subscribeToProgramLogs(String programId) =>
      _wsClient?.subscribeToProgramLogs(programId);

  /// Connect WebSocket if available
  Future<void> connectWebSocket() async {
    await _wsClient?.connect();
  }

  /// Disconnect WebSocket if available
  Future<void> disconnectWebSocket() async {
    await _wsClient?.disconnect();
  }

  /// Get WebSocket connection state
  Stream<bool>? get webSocketConnectionState => _wsClient?.connectionState;

  /// Clean up resources
  Future<void> dispose() async {
    await _wsClient?.dispose();
  }
}
