library;

import 'dart:typed_data';

/// Exact bytes received from a logical GIULIA device stream.
///
/// PRIMARY Ercolina frames contain both physical sides. They must therefore
/// be stored once at device level instead of being copied into one side's
/// sensor row. Decoding metadata is only an index; [bytes] remains the source
/// of truth for a future decoder.
class RawDeviceFrame {
  RawDeviceFrame({
    required this.deviceId,
    required this.receivedAtUs,
    required List<int> bytes,
    required this.decoderVersion,
    required this.valid,
    this.channel = 'measurement',
    this.failureCode,
    this.deviceTimeUs,
    this.sequence,
    this.streamEpoch,
    this.schemaId,
    this.flags,
  }) : bytes = Uint8List.fromList(bytes);

  final String deviceId;
  final int receivedAtUs;
  final Uint8List bytes;
  final String decoderVersion;
  final bool valid;
  final String channel;
  final String? failureCode;
  final int? deviceTimeUs;
  final int? sequence;
  final int? streamEpoch;
  final int? schemaId;
  final int? flags;
}
