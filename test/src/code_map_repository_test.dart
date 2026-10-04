import 'dart:convert';
import 'dart:typed_data';

import 'package:code_analysis_engine/code_analysis_engine.dart';
import 'package:code_graph/code_graph.dart';
import 'package:code_map_repository/code_map_repository.dart';
import 'package:code_source_client/code_source_client.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  group(CodeMapRepository, () {
    late TrackingSnapshot snapshot;
    late InMemoryCodeMapStore store;

    setUp(() {
      snapshot = TrackingSnapshot(projectFiles);
      store = InMemoryCodeMapStore();
    });

    CodeMapRepository repository({
      List<FetchEvent>? fetch,
      EngineRunner? engineRunner,
      MapWorker? worker,
    }) => CodeMapRepository(
      sourceClient: FakeSourceClient(
        fetch ??
            [
              const FetchProgress(FetchPhase.downloading, done: 50, total: 100),
              FetchDone(snapshot),
            ],
      ),
      store: store,
      engineRunner: engineRunner ?? InlineEngineRunner(),
      worker: worker ?? const InlineMapWorker(),
      clock: () => DateTime.utc(2026, 10, 4, 12),
    );

    const source = GitRepositorySource('https://github.com/example/app');

    group('build', () {
      test('goes through every stage and returns a readable file', () async {
        final events = await repository()
            .build(source, AnalysisRules.defaults())
            .toList();

        final progress = events.whereType<BuildProgress>().toList();
        expect(progress.map((e) => e.stage).toSet(), BuildStage.values.toSet());
        for (var i = 1; i < progress.length; i++) {
          expect(
            progress[i].fraction,
            greaterThanOrEqualTo(progress[i - 1].fraction),
          );
        }
        expect(progress[1].fraction, 0.1);
        expect(progress.last.fraction, 1);
        final file = (events.last as BuildSucceeded).file;
        expect(file.name, 'app @ main');
        expect(
          file.id,
          startsWith(
            '${DateTime.utc(2026, 10, 4, 12).millisecondsSinceEpoch}-',
          ),
        );
        final map = const CodeMapCodec().decodeFromBytes(file.bytes);
        expect(map.graph.nodes.keys, contains('lib/src/a.dart#A.run'));
        expect(snapshot.disposed, isTrue);
      });

      test('treats an unknown download size as half way', () async {
        final events = await repository(
          fetch: [
            const FetchProgress(FetchPhase.downloading, done: 10),
            FetchDone(snapshot),
          ],
        ).build(source, AnalysisRules.defaults()).toList();

        expect((events[1] as BuildProgress).fraction, 0.1);
      });

      final fetchFailures = <FetchFailure, BuildFailureKind>{
        const SourceNotFound('/x'): BuildFailureKind.sourceNotFound,
        const InvalidGitUrl('x'): BuildFailureKind.invalidGitUrl,
        const RepositoryNotFound('u'): BuildFailureKind.privateOrMissingRepo,
        const RateLimited(): BuildFailureKind.rateLimited,
        const NetworkFailure('x'): BuildFailureKind.network,
        const ArchiveTooLarge(1): BuildFailureKind.invalidArchive,
        const InvalidArchive('x'): BuildFailureKind.invalidArchive,
        const UnsupportedOnWeb('git repository'):
            BuildFailureKind.unsupportedOnWeb,
      };
      for (final MapEntry(key: failure, value: kind) in fetchFailures.entries) {
        test('maps ${failure.runtimeType} to ${kind.name}', () async {
          final events = await repository(fetch: [FetchFailed(failure)])
              .build(source, AnalysisRules.defaults())
              .toList();

          expect(events.last, BuildFailed(BuildFailure(kind, failure.message)));
        });
      }

      test('reports an analysis bug with its details', () async {
        final events = await repository(
          engineRunner: FakeEngineRunner([AnalysisFailed(StateError('boom'))]),
        ).build(source, AnalysisRules.defaults()).toList();

        final failure = (events.last as BuildFailed).failure;
        expect(failure.kind, BuildFailureKind.analysisError);
        expect(failure.details, contains('boom'));
        expect(snapshot.disposed, isTrue);
      });

      test('reports a layout bug as an analysis error', () async {
        final events = await repository(
          worker: HookedWorker(() => throw StateError('layout')),
        ).build(source, AnalysisRules.defaults()).toList();

        final failure = (events.last as BuildFailed).failure;
        expect(failure.kind, BuildFailureKind.analysisError);
        expect(failure.details, contains('layout'));
        expect(snapshot.disposed, isTrue);
      });

      group('cancelled', () {
        const cancelled = BuildFailed(
          BuildFailure(
            BuildFailureKind.cancelled,
            'The analysis was cancelled.',
          ),
        );

        test('while fetching', () async {
          final events = await repository()
              .build(
                source,
                AnalysisRules.defaults(),
                cancel: CancelToken()..cancel(),
              )
              .toList();

          expect(events.last, cancelled);
        });

        test('once the code is fetched', () async {
          final token = CancelToken();
          final events = await repository(fetch: [FetchDone(snapshot)])
              .build(source, AnalysisRules.defaults(), cancel: token)
              .map((e) {
                token.cancel();
                return e;
              })
              .toList();

          expect(events.last, cancelled);
          expect(snapshot.disposed, isTrue);
        });

        test('by the engine', () async {
          final events = await repository(
            engineRunner: FakeEngineRunner([
              const AnalysisFailed(AnalysisCancelled()),
            ]),
          ).build(source, AnalysisRules.defaults()).toList();

          expect(events.last, cancelled);
        });

        test('after the analysis', () async {
          final token = CancelToken();
          final events = await repository(
            engineRunner: FakeEngineRunner([
              AnalysisDone(emptyGraph()),
            ], onRun: token.cancel),
          ).build(source, AnalysisRules.defaults(), cancel: token).toList();

          expect(events.last, cancelled);
        });

        test('during the layout', () async {
          final token = CancelToken();
          final events = await repository(worker: HookedWorker(token.cancel))
              .build(source, AnalysisRules.defaults(), cancel: token)
              .toList();

          expect(events.last, cancelled);
          expect(snapshot.disposed, isTrue);
        });
      });
    });

    group('open', () {
      test('decodes a built file', () async {
        final events = await repository()
            .build(source, AnalysisRules.defaults())
            .toList();
        final file = (events.last as BuildSucceeded).file;

        final map = await repository().open(file);

        expect(map.graph.project, file.project);
      });

      test('throws an invalidFile failure for unreadable bytes', () {
        final file = CodeMapFile(
          id: 'x',
          name: 'x',
          bytes: Uint8List.fromList([1, 2, 3]),
          project: emptyGraph().project,
        );

        expect(
          () => repository().open(file),
          throwsA(
            isA<BuildFailure>().having(
              (f) => f.kind,
              'kind',
              BuildFailureKind.invalidFile,
            ),
          ),
        );
      });
    });

    group('openBytes', () {
      test('decodes the bytes of a code map', () async {
        final bytes = const CodeMapCodec().encodeToBytes(
          CodeMap(graph: emptyGraph(), placements: const {}),
        );

        final map = await repository().openBytes(bytes);

        expect(map.graph.project, emptyGraph().project);
      });

      test('throws an invalidFile failure for unreadable bytes', () {
        expect(
          () => repository().openBytes(Uint8List.fromList([1, 2, 3])),
          throwsA(
            isA<BuildFailure>().having(
              (f) => f.kind,
              'kind',
              BuildFailureKind.invalidFile,
            ),
          ),
        );
      });
    });

    group('importBytes', () {
      late CodeMap map;

      setUp(() {
        map = CodeMap(graph: emptyGraph(), placements: const {});
      });

      test('keeps a .dc3d file as it is', () async {
        final bytes = const CodeMapCodec().encodeToBytes(map);

        final file = await repository().importBytes('AltMe.dc3d', bytes);

        expect(file.name, 'AltMe');
        expect(file.bytes, bytes);
        expect(file.project, map.graph.project);
      });

      test('compresses a plain .fscene', () async {
        final bytes = Uint8List.fromList(
          utf8.encode(const CodeMapCodec().encodeToJson(map)),
        );

        final file = await repository().importBytes('.fscene', bytes);

        expect(file.name, 'app');
        expect(file.bytes.take(2), [0x1F, 0x8B]);
      });

      test('throws an invalidFile failure for garbage', () {
        expect(
          () => repository().importBytes('x.dc3d', Uint8List.fromList([9])),
          throwsA(isA<BuildFailure>()),
        );
      });

      test('explains that a newer map needs a newer app', () async {
        final newer = CodeMap(
          graph: CodeGraph(
            project: ProjectInfo(
              generator: 'future',
              source: const ZipDescriptor(fileName: 'a.zip'),
              createdAt: DateTime.utc(2030),
              schemaVersion: ProjectInfo.currentSchemaVersion + 1,
            ),
            nodes: const {},
          ),
          placements: const {},
        );

        expect(
          () => repository().importBytes(
            'future.dc3d',
            const CodeMapCodec().encodeToBytes(newer),
          ),
          throwsA(
            isA<BuildFailure>().having(
              (f) => f.message,
              'message',
              contains('Update the app'),
            ),
          ),
        );
      });
    });

    test('exports with a safe .dc3d file name', () {
      CodeMapFile named(String name) => CodeMapFile(
        id: 'x',
        name: name,
        bytes: Uint8List(1),
        project: emptyGraph().project,
      );

      expect(
        repository().exportForSharing(named('AltMe @ main')).fileName,
        'AltMe_main.dc3d',
      );
      expect(repository().exportForSharing(named('@@')).fileName, '_.dc3d');
      expect(
        repository().exportForSharing(named('')).fileName,
        'code_map.dc3d',
      );
    });

    test('saves, lists newest first, loads and deletes', () async {
      final repo = repository();
      CodeMapFile file(String id, int year) => CodeMapFile(
        id: id,
        name: id,
        bytes: Uint8List(3),
        project: ProjectInfo(
          generator: 'g',
          source: const ZipDescriptor(fileName: 'a.zip'),
          createdAt: DateTime.utc(year),
        ),
      );

      await repo.save(file('old', 2020));
      await repo.save(file('new', 2026));
      await repo.save(file('also-new', 2026));

      expect((await repo.recent()).map((s) => s.id), [
        'also-new',
        'new',
        'old',
      ]);
      expect((await repo.load('old'))!.name, 'old');
      await repo.delete('old');
      expect(await repo.load('old'), isNull);
    });

    test('uses the platform runner and worker by default', () async {
      final repo = CodeMapRepository(
        sourceClient: FakeSourceClient([FetchDone(snapshot)]),
        store: store,
      );

      final last = await repo.build(source, AnalysisRules.defaults()).last;

      expect(last, isA<BuildSucceeded>());
    });
  });
}
