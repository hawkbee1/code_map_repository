import 'package:code_map_repository/src/worker/map_worker.dart';

/// The web has no isolates: the work runs inline.
MapWorker defaultMapWorker() => const InlineMapWorker();
