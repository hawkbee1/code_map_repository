// The platform's default worker: an isolate on native platforms, inline on
// the web.
export 'worker_web.dart' if (dart.library.io) 'worker_io.dart';
