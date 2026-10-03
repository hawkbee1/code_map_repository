import 'dart:isolate';
import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_layout/code_layout.dart';
import 'package:code_map_repository/src/worker/map_worker.dart';

/// Native platforms do the work in an isolate.
MapWorker defaultMapWorker() => const IsolateMapWorker();

/// Runs each task in a short-lived isolate of the same group (`Isolate.run`):
/// graphs and maps are passed without serialization.
class IsolateMapWorker implements MapWorker {
  /// Creates the worker.
  const new({this.layoutEngine = const CodeLayoutEngine()});

  /// The layout engine.
  final CodeLayoutEngine layoutEngine;

  @override
  Future<(CodeMap, Uint8List)> layoutAndEncode(CodeGraph graph) {
    final engine = layoutEngine;
    return Isolate.run(() => layoutAndEncodeNow(graph, engine));
  }

  @override
  Future<CodeMap> decode(Uint8List bytes) =>
      Isolate.run(() => const CodeMapCodec().decodeFromBytes(bytes));
}
