import 'dart:convert';
import 'dart:typed_data';

import 'package:code_analysis_engine/code_analysis_engine.dart';
import 'package:code_graph/code_graph.dart';
import 'package:code_map_repository/code_map_repository.dart';
import 'package:code_source_client/code_source_client.dart';

/// A snapshot that records whether it was disposed.
class TrackingSnapshot implements SourceSnapshot {
  /// Wraps [files] (path → text).
  new(Map<String, String> files)
    : _inner = MemorySnapshot(
        descriptor: const GitDescriptor(
          url: 'https://github.com/example/app',
          ref: 'main',
        ),
        files: {
          for (final MapEntry(:key, :value) in files.entries)
            key: Uint8List.fromList(utf8.encode(value)),
        },
      );

  final MemorySnapshot _inner;

  /// Whether [dispose] was called.
  bool disposed = false;

  @override
  SourceDescriptor get descriptor => _inner.descriptor;

  @override
  List<String> get paths => _inner.paths;

  @override
  Future<String> readAsString(String path) => _inner.readAsString(path);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _inner.dispose();
  }
}

/// A source client that replays [events].
class FakeSourceClient implements CodeSourceClient {
  /// Creates the fake.
  new(this.events);

  /// The events every fetch emits.
  final List<FetchEvent> events;

  @override
  int get maxArchiveBytes => 0;

  @override
  int get maxExtractedBytes => 0;

  @override
  Stream<FetchEvent> fetch(CodeSource source) => Stream.fromIterable(events);
}

/// An engine runner that replays [events].
class FakeEngineRunner implements EngineRunner {
  /// Creates the fake; [onRun] runs when an analysis starts.
  new(this.events, {this.onRun});

  /// The events every run emits.
  final List<AnalysisEvent> events;

  /// Called at the start of each run.
  final void Function()? onRun;

  @override
  Stream<AnalysisEvent> run(
    SourceSnapshot snapshot,
    AnalysisRules rules, {
    CancelToken? cancel,
  }) {
    onRun?.call();
    return Stream.fromIterable(events);
  }
}

/// A worker whose layout step runs [onLayout] first (to cancel, or throw).
class HookedWorker implements MapWorker {
  /// Creates the worker.
  new(this.onLayout);

  /// Called before laying out.
  final void Function() onLayout;

  @override
  Future<(CodeMap, Uint8List)> layoutAndEncode(CodeGraph graph) async {
    onLayout();
    return await const InlineMapWorker().layoutAndEncode(graph);
  }

  @override
  Future<CodeMap> decode(Uint8List bytes) =>
      const InlineMapWorker().decode(bytes);
}

/// A small project.
const projectFiles = {
  'pubspec.yaml': 'name: app',
  'lib/main.dart': "import 'src/a.dart';\nvoid main() { A().run(); }",
  'lib/src/a.dart': 'class A { void run() {} }',
};

/// A code graph of nothing, for fake analyses.
CodeGraph emptyGraph() => CodeGraph(
  project: ProjectInfo(
    generator: 'test',
    source: const GitDescriptor(url: 'https://github.com/example/app'),
    createdAt: DateTime.utc(2026),
  ),
  nodes: const {},
);
