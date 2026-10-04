import 'dart:async';
import 'dart:typed_data';

import 'package:code_analysis_engine/code_analysis_engine.dart';
import 'package:code_graph/code_graph.dart';
import 'package:code_map_repository/src/models.dart';
import 'package:code_map_repository/src/store.dart';
import 'package:code_map_repository/src/worker/map_worker.dart';
import 'package:code_map_repository/src/worker/worker.dart';
import 'package:code_source_client/code_source_client.dart';

/// Builds, opens, imports, stores and shares code maps: what the app's
/// blocs use.
///
/// A build chains fetch → analyze → layout → encode, with one progress
/// stream (fetch 0–20%, analysis 20–80%, layout 80–95%, encoding 95–100%,
/// never going backwards), cancellation, and typed failures. The snapshot
/// of the code is always disposed.
class CodeMapRepository {
  /// Creates the repository. [engineRunner] and [worker] default to the
  /// platform's (isolates on native platforms, inline on the web).
  new({
    required this._sourceClient,
    required this._store,
    EngineRunner? engineRunner,
    MapWorker? worker,
    DateTime Function()? clock,
  }) : _engineRunner = engineRunner ?? defaultEngineRunner(),
       _worker = worker ?? defaultMapWorker(),
       _clock = clock ?? DateTime.now;

  final CodeSourceClient _sourceClient;
  final CodeMapStore _store;
  final EngineRunner _engineRunner;
  final MapWorker _worker;
  final DateTime Function() _clock;

  final _changes = StreamController<void>.broadcast(sync: true);

  static const _cancelled = BuildFailure(
    BuildFailureKind.cancelled,
    'The analysis was cancelled.',
  );

  /// Builds a code map of [source] with [rules].
  ///
  /// Emits [BuildProgress] events, then one [BuildSucceeded] (the file is
  /// not saved: call [save]) or [BuildFailed].
  Stream<BuildEvent> build(
    CodeSource source,
    AnalysisRules rules, {
    CancelToken? cancel,
  }) async* {
    final token = cancel ?? CancelToken();
    var reported = 0.0;
    BuildProgress progress(
      BuildStage stage,
      double fraction, [
      String? detail,
    ]) {
      reported = fraction > reported ? fraction : reported;
      return BuildProgress(stage, reported, detail: detail);
    }

    SourceSnapshot? snapshot;
    try {
      yield progress(BuildStage.fetching, 0);
      await for (final event in _sourceClient.fetch(source)) {
        // Take the snapshot before checking for cancellation, so it is
        // always disposed.
        if (event is FetchDone) snapshot = event.snapshot;
        if (token.isCancelled) throw _cancelled;
        switch (event) {
          case FetchProgress(:final done, :final total):
            final share = total == null || total == 0 ? 0.5 : done / total;
            yield progress(BuildStage.fetching, 0.2 * share.clamp(0, 1));
          case FetchDone():
            break;
          case FetchFailed(:final failure):
            throw _fromFetch(failure);
        }
      }
      if (token.isCancelled) throw _cancelled;

      CodeGraph? graph;
      await for (final event in _engineRunner.run(
        snapshot!,
        rules,
        cancel: token,
      )) {
        switch (event) {
          case AnalysisProgress(:final stage, :final done, :final total):
            yield progress(
              BuildStage.analyzing,
              _analysisFraction(stage, done, total),
              event.currentPath,
            );
          case AnalysisDone(graph: final done):
            graph = done;
          case AnalysisFailed(:final error, :final stackTrace):
            throw error is AnalysisCancelled
                ? _cancelled
                : BuildFailure(
                    BuildFailureKind.analysisError,
                    'The analysis failed.',
                    details: '$error\n${stackTrace ?? ''}',
                  );
        }
      }
      if (token.isCancelled) throw _cancelled;

      yield progress(BuildStage.layingOut, 0.8);
      final (_, bytes) = await _worker.layoutAndEncode(graph!);
      if (token.isCancelled) throw _cancelled;
      yield progress(BuildStage.encoding, 0.95);

      final createdAt = _clock().toUtc();
      yield progress(BuildStage.encoding, 1);
      yield BuildSucceeded(
        CodeMapFile(
          id: _newId(graph.project.source.label, createdAt),
          name: graph.project.source.label,
          bytes: bytes,
          project: graph.project,
        ),
      );
    } on BuildFailure catch (failure) {
      yield BuildFailed(failure);
      // A bug in layout or encoding must still end the stream properly.
    } on Object catch (error, stackTrace) {
      yield BuildFailed(
        BuildFailure(
          BuildFailureKind.analysisError,
          'Building the 3D map failed.',
          details: '$error\n$stackTrace',
        ),
      );
    } finally {
      await snapshot?.dispose();
    }
  }

  /// Decodes [file] for the viewer.
  ///
  /// Throws a [BuildFailure] (`invalidFile`) when it cannot be read.
  Future<CodeMap> open(CodeMapFile file) => openBytes(file.bytes);

  /// Decodes `.dc3d` or `.fscene` [bytes] for the viewer, off the UI
  /// thread on native platforms.
  ///
  /// Throws a [BuildFailure] (`invalidFile`) when they are not a readable
  /// code map, including a map written by a newer app.
  Future<CodeMap> openBytes(Uint8List bytes) async {
    try {
      return await _worker.decode(bytes);
    } on CodeMapFormatException catch (e) {
      throw BuildFailure(BuildFailureKind.invalidFile, e.message);
    }
  }

  /// Reads a `.dc3d` or `.fscene` file chosen by the user and returns it as
  /// a [CodeMapFile] (not saved yet).
  ///
  /// Throws a [BuildFailure] (`invalidFile`) when it is not a readable code
  /// map, including a map written by a newer app.
  Future<CodeMapFile> importBytes(String fileName, Uint8List bytes) async {
    final CodeMap map;
    try {
      map = await _worker.decode(bytes);
    } on CodeMapFormatException catch (e) {
      throw BuildFailure(BuildFailureKind.invalidFile, e.message);
    }
    final project = map.graph.project;
    final name = fileName.replaceFirst(RegExp(r'\.(dc3d|fscene)$'), '');
    // A plain .fscene is stored compressed, like every other map.
    final isGzip = bytes.length > 1 && bytes[0] == 0x1F && bytes[1] == 0x8B;
    return CodeMapFile(
      id: _newId(name, _clock().toUtc()),
      name: name.isEmpty ? project.source.label : name,
      bytes: isGzip ? bytes : const CodeMapCodec().encodeToBytes(map),
      project: project,
    );
  }

  /// The file to share: its name (`<name>.dc3d`) and bytes.
  ({String fileName, Uint8List bytes}) exportForSharing(CodeMapFile file) => (
    fileName: '${_safeFileName(file.name)}.${CodeMapCodec.fileExtension}',
    bytes: file.bytes,
  );

  /// Fires after a map was saved or deleted, so lists can refresh.
  Stream<void> get changes => _changes.stream;

  /// The stored maps, newest first.
  ///
  /// Throws a [BuildFailure] (`storage`) when the store cannot be read, like
  /// [load], [save] and [delete].
  Future<List<CodeMapSummary>> recent() => _inStorage(
    'The stored maps could not be read.',
    () async => (await _store.list())
      ..sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      }),
  );

  /// The stored file [id], or null.
  Future<CodeMapFile?> load(String id) =>
      _inStorage('The map could not be read.', () => _store.load(id));

  /// Stores [file].
  Future<void> save(CodeMapFile file) =>
      _inStorage('The map could not be saved.', () async {
        await _store.save(file);
        _changes.add(null);
      });

  /// Deletes the stored file [id].
  Future<void> delete(String id) =>
      _inStorage('The map could not be deleted.', () async {
        await _store.delete(id);
        _changes.add(null);
      });

  static Future<T> _inStorage<T>(
    String message,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      throw BuildFailure(
        BuildFailureKind.storage,
        message,
        details: '$error\n$stackTrace',
      );
    }
  }

  static double _analysisFraction(AnalysisStage stage, int done, int total) {
    final share = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return switch (stage) {
      AnalysisStage.collecting => 0.2,
      AnalysisStage.parsing => 0.2 + 0.4 * share,
      AnalysisStage.declarations => 0.6,
      AnalysisStage.containment => 0.65,
      AnalysisStage.links => 0.65 + 0.15 * share,
    };
  }

  static BuildFailure _fromFetch(FetchFailure failure) {
    final kind = switch (failure) {
      SourceNotFound() => BuildFailureKind.sourceNotFound,
      InvalidGitUrl() => BuildFailureKind.invalidGitUrl,
      RepositoryNotFound() => BuildFailureKind.privateOrMissingRepo,
      RateLimited() => BuildFailureKind.rateLimited,
      NetworkFailure() => BuildFailureKind.network,
      ArchiveTooLarge() || InvalidArchive() => BuildFailureKind.invalidArchive,
      UnsupportedOnWeb() => BuildFailureKind.unsupportedOnWeb,
    };
    return BuildFailure(kind, failure.message);
  }

  static String _newId(String name, DateTime createdAt) =>
      '${createdAt.millisecondsSinceEpoch}-'
      '${stableHash(name).toRadixString(16)}';

  static String _safeFileName(String name) {
    final safe = name
        .replaceAll(RegExp('[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp('_+'), '_');
    return safe.isEmpty ? 'code_map' : safe;
  }
}
