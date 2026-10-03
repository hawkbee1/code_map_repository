import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_layout/code_layout.dart';

/// The heavy work after the analysis: layout, encoding and decoding take
/// seconds on large projects, so native platforms run it in an isolate.
abstract interface class MapWorker {
  /// Lays out [graph] and encodes it as a `.dc3d` file.
  Future<(CodeMap, Uint8List)> layoutAndEncode(CodeGraph graph);

  /// Decodes a `.dc3d` or `.fscene` file (throws `CodeMapFormatException`).
  Future<CodeMap> decode(Uint8List bytes);
}

/// Does the work on the current thread (web, tests).
class InlineMapWorker implements MapWorker {
  /// Creates the worker.
  const new({this.layoutEngine = const CodeLayoutEngine()});

  /// The layout engine.
  final CodeLayoutEngine layoutEngine;

  @override
  Future<(CodeMap, Uint8List)> layoutAndEncode(CodeGraph graph) async =>
      layoutAndEncodeNow(graph, layoutEngine);

  @override
  Future<CodeMap> decode(Uint8List bytes) async =>
      const CodeMapCodec().decodeFromBytes(bytes);
}

/// Lays out and encodes [graph] synchronously.
(CodeMap, Uint8List) layoutAndEncodeNow(
  CodeGraph graph,
  CodeLayoutEngine layoutEngine,
) {
  final map = layoutEngine.layout(graph);
  return (map, const CodeMapCodec().encodeToBytes(map));
}
