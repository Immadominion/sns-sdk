import 'package:sns_sdk/sns_sdk.dart';

/// Example demonstrating basic SNS SDK usage
Future<void> main() async {
  // Initialize RPC client and SNS client
  final rpc = HttpRpcClient('https://api.mainnet-beta.solana.com');
  final client = SnsClient(rpc);

  print('SNS Dart SDK Example');
  print('==================');

  try {
    // Example 1: Resolve domain to owner
    print('\n1. Resolving domain "bonfida"...');
    final owner = await resolve(
      client,
      'bonfida',
      config: ResolveConfig(allowPda: "any"),
    );
    print('Owner: $owner');

    // Example 2: Get domain address
    print('\n2. Getting domain address...');
    final result = await getDomainAddress(
      GetDomainAddressParams(domain: 'bonfida'),
    );
    print('Address: ${result.domainAddress}');
    print('Is subdomain: ${result.isSub}');

    // Example 3: Get domain records
    print('\n3. Getting domain records...');
    final record = await getDomainRecord(GetDomainRecordParams(
      rpc: rpc,
      domain: 'bonfida',
      record: Record.sol,
      options: GetDomainRecordOptions(deserialize: true),
    ));
    print('SOL record: ${record.deserializedContent}');
    print('Is valid: ${record.verified.staleness}');
  } catch (e) {
    print('Error: $e');
  }
}
