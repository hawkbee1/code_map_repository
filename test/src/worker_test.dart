import 'package:code_graph/code_graph.dart';
import 'package:code_map_repository/code_map_repository.dart';
import 'package:code_map_repository/src/worker/worker_io.dart'
    show IsolateMapWorker;
import 'package:test/test.dart';

void main() {
  group(IsolateMapWorker, () {
    test('lays out, encodes and decodes in isolates', () async {
      final graph = CodeGraph(
        project: ProjectInfo(
          generator: 'g',
          source: const ZipDescriptor(fileName: 'a.zip'),
          createdAt: DateTime.utc(2026),
        ),
        nodes: const {
          'A': CodeNode(id: 'A', kind: CodeNodeKind.classDecl, name: 'A'),
        },
      );
      const worker = IsolateMapWorker();

      final (map, bytes) = await worker.layoutAndEncode(graph);
      final decoded = await worker.decode(bytes);

      expect(decoded, map);
    });
  });

  test('defaultMapWorker uses an isolate on native platforms', () {
    expect(defaultMapWorker(), isA<IsolateMapWorker>());
  });
}
