import 'dart:typed_data';
import '../constants/records.dart';
import '../states/registry.dart';
import 'deserialize_record.dart' as main_deserialize;

/// Simple deserialization function that takes serialized data and record type directly
/// This function provides test compatibility with the JavaScript SDK pattern
///
/// @param serialized The serialized data as List<int> or Uint8List
/// @param record The record type enum
/// @returns Deserialized content as String, or null if empty
String? deserializeRecord(List<int> serialized, Record record) {
  // Create a mock registry state with the serialized data
  final mockRegistry = RegistryState(
    parentName: '',
    owner: '',
    classAddress: '',
    data: Uint8List.fromList(serialized),
  );

  // Use the main deserializeRecord function with mock data
  return main_deserialize.deserializeRecord(mockRegistry, record, '');
}
