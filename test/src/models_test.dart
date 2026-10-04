import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:code_map_repository/code_map_repository.dart';
import 'package:test/test.dart';

void main() {
  group(CodeMapSummary, () {
    test('is derived from a file and round-trips through JSON', () {
      final file = CodeMapFile(
        id: 'id',
        name: 'AltMe',
        bytes: Uint8List(10),
        project: ProjectInfo(
          generator: 'g',
          source: const ZipDescriptor(fileName: 'a.zip'),
          createdAt: DateTime.utc(2026),
          stats: const GraphStats(nodes: 3, links: 4),
        ),
      );

      final summary = file.summary;

      expect(summary.nodeCount, 3);
      expect(summary.linkCount, 4);
      expect(summary.sizeBytes, 10);
      expect(CodeMapSummary.fromJson(summary.toJson()), summary);
      expect(file.props, hasLength(4));
    });
  });

  group(BuildFailure, () {
    test('describes itself', () {
      expect(
        const BuildFailure(BuildFailureKind.network, 'offline').toString(),
        'BuildFailure(network): offline',
      );
    });
  });

  group(BuildEvent, () {
    test('compares by value', () {
      // Built at runtime: identical constants would skip the comparison.
      final fraction = [0.5].single;
      expect(
        BuildProgress(BuildStage.fetching, fraction, detail: 'a'),
        BuildProgress(BuildStage.fetching, fraction, detail: 'a'),
      );
      final failure = BuildFailure(BuildFailureKind.cancelled, ['x'].single);
      expect(BuildFailed(failure), BuildFailed(failure));
      final file = CodeMapFile(
        id: 'i',
        name: 'n',
        bytes: Uint8List(0),
        project: ProjectInfo(
          generator: 'g',
          source: const ZipDescriptor(fileName: 'a.zip'),
          createdAt: DateTime.utc(2026),
        ),
      );
      expect(BuildSucceeded(file), BuildSucceeded(file));
    });
  });
}
