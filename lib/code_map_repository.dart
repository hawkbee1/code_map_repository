/// The dart_code_3D repository that builds, opens, imports, stores and
/// shares code maps.
library;

// What the app needs to describe a build, so it does not depend on the data
// packages (architecture.md §3).
export 'package:code_analysis_engine/code_analysis_engine.dart'
    show CancelToken;
export 'package:code_source_client/code_source_client.dart'
    show
        CodeSource,
        GitHost,
        GitRepositorySource,
        GitUrl,
        LocalFolderSource,
        ZipBytesSource;

export 'src/code_map_repository.dart';
export 'src/models.dart';
export 'src/store.dart';
export 'src/worker/map_worker.dart';
export 'src/worker/worker.dart' show defaultMapWorker;
