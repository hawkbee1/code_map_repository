import 'package:code_map_repository/src/models.dart';

/// Where code map files are kept. The app implements it with platform
/// storage (files on native platforms); [InMemoryCodeMapStore] serves tests
/// and the web.
abstract interface class CodeMapStore {
  /// Saves [file], replacing a file with the same id.
  Future<void> save(CodeMapFile file);

  /// Every stored file's summary, in any order.
  Future<List<CodeMapSummary>> list();

  /// The file [id], or null.
  Future<CodeMapFile?> load(String id);

  /// Deletes the file [id] (nothing happens when it does not exist).
  Future<void> delete(String id);
}

/// Keeps files in memory: lost when the app stops.
class InMemoryCodeMapStore implements CodeMapStore {
  final _files = <String, CodeMapFile>{};

  @override
  Future<void> save(CodeMapFile file) async => _files[file.id] = file;

  @override
  Future<List<CodeMapSummary>> list() async => [
    for (final file in _files.values) file.summary,
  ];

  @override
  Future<CodeMapFile?> load(String id) async => _files[id];

  @override
  Future<void> delete(String id) async => _files.remove(id);
}
