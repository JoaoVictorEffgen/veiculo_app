import 'dart:convert';
import 'dart:typed_data';

abstract final class VehicleMaintenancePlanLimits {
  static const chunkSizeBytes = 700 * 1024;
  static const maxFileSizeBytes = 3 * 1024 * 1024;
}

abstract final class VehicleMaintenancePlanCodec {
  static List<Uint8List> split(Uint8List bytes) {
    if (bytes.length <= VehicleMaintenancePlanLimits.chunkSizeBytes) {
      return [bytes];
    }

    final chunks = <Uint8List>[];
    for (var offset = 0; offset < bytes.length; offset += VehicleMaintenancePlanLimits.chunkSizeBytes) {
      final end = (offset + VehicleMaintenancePlanLimits.chunkSizeBytes).clamp(0, bytes.length);
      chunks.add(Uint8List.sublistView(bytes, offset, end));
    }
    return chunks;
  }

  static Uint8List merge(List<String> encodedChunks) {
    final builder = BytesBuilder(copy: false);
    for (final encoded in encodedChunks) {
      builder.add(base64Decode(encoded));
    }
    return builder.toBytes();
  }
}
