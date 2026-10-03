import 'dart:typed_data';

import 'package:code_graph/code_graph.dart';
import 'package:equatable/equatable.dart';

/// A stored code map: a `.dc3d` file and what it is about.
class CodeMapFile extends Equatable {
  /// Creates a file.
  const new({
    required this.id,
    required this.name,
    required this.bytes,
    required this.project,
  });

  /// Unique id in the store.
  final String id;

  /// Name shown to the user, e.g. `AltMe @ main`.
  final String name;

  /// The `.dc3d` file: `CodeMapCodec.encodeToBytes` (gzipped `.fscene`).
  final Uint8List bytes;

  /// Metadata of the analysis.
  final ProjectInfo project;

  /// The summary shown in lists.
  CodeMapSummary get summary => CodeMapSummary(
    id: id,
    name: name,
    source: project.source,
    createdAt: project.createdAt,
    nodeCount: project.stats.nodes,
    linkCount: project.stats.links,
    sizeBytes: bytes.length,
  );

  @override
  List<Object?> get props => [id, name, bytes, project];
}

/// What a list of code maps shows, without the file's bytes.
class CodeMapSummary extends Equatable {
  /// Creates a summary.
  const new({
    required this.id,
    required this.name,
    required this.source,
    required this.createdAt,
    required this.nodeCount,
    required this.linkCount,
    required this.sizeBytes,
  });

  /// Reads a summary written by [toJson].
  factory fromJson(Map<String, Object?> json) => CodeMapSummary(
    id: json['id']! as String,
    name: json['name']! as String,
    source: SourceDescriptor.fromJson(json['source']! as Map<String, Object?>),
    createdAt: DateTime.parse(json['createdAt']! as String),
    nodeCount: json['nodeCount']! as int,
    linkCount: json['linkCount']! as int,
    sizeBytes: json['sizeBytes']! as int,
  );

  /// Id of the file in the store.
  final String id;

  /// Name shown to the user.
  final String name;

  /// Where the code came from.
  final SourceDescriptor source;

  /// When the analysis ran.
  final DateTime createdAt;

  /// Number of spheres.
  final int nodeCount;

  /// Number of links.
  final int linkCount;

  /// Size of the `.dc3d` file.
  final int sizeBytes;

  /// A JSON representation (store indexes).
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'source': source.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'nodeCount': nodeCount,
    'linkCount': linkCount,
    'sizeBytes': sizeBytes,
  };

  @override
  List<Object?> get props => [
    id,
    name,
    source,
    createdAt,
    nodeCount,
    linkCount,
    sizeBytes,
  ];
}

/// What a build is doing.
enum BuildStage {
  /// Getting the code.
  fetching,

  /// Analyzing it.
  analyzing,

  /// Placing the spheres.
  layingOut,

  /// Writing the file.
  encoding,
}

/// Why a build, an import or an open failed.
enum BuildFailureKind {
  /// The local folder does not exist.
  sourceNotFound,

  /// Not a GitHub or GitLab URL.
  invalidGitUrl,

  /// The repository does not exist or is private.
  privateOrMissingRepo,

  /// The host refuses more downloads for now.
  rateLimited,

  /// The download failed.
  network,

  /// The archive is invalid or too large.
  invalidArchive,

  /// The source cannot be used in a browser.
  unsupportedOnWeb,

  /// The file is not a code map, or is from a newer app.
  invalidFile,

  /// The analysis (or layout) failed: a bug.
  analysisError,

  /// The user cancelled.
  cancelled,
}

/// A typed failure with a message for the user (in English; the app
/// localizes by [kind]) and technical [details] for the error box.
class BuildFailure extends Equatable implements Exception {
  /// Creates a failure.
  const new(this.kind, this.message, {this.details});

  /// What went wrong.
  final BuildFailureKind kind;

  /// A message for the user.
  final String message;

  /// Technical details (an error and its stack trace), if any.
  final String? details;

  @override
  List<Object?> get props => [kind, message, details];

  @override
  String toString() => 'BuildFailure(${kind.name}): $message';
}

/// Something that happened during a build.
sealed class BuildEvent extends Equatable {
  const new();
}

/// Progress: [fraction] (0–1, never decreasing) in [stage]; [detail] is the
/// file being handled, if any.
class BuildProgress extends BuildEvent {
  /// Creates the event.
  const new(this.stage, this.fraction, {this.detail});

  /// What the build is doing.
  final BuildStage stage;

  /// Overall progress, 0 to 1.
  final double fraction;

  /// What is being handled.
  final String? detail;

  @override
  List<Object?> get props => [stage, fraction, detail];
}

/// The map is built (not saved yet: call `CodeMapRepository.save`).
class BuildSucceeded extends BuildEvent {
  /// Creates the event.
  const new(this.file);

  /// The new code map file.
  final CodeMapFile file;

  @override
  List<Object?> get props => [file];
}

/// The build failed or was cancelled.
class BuildFailed extends BuildEvent {
  /// Creates the event.
  const new(this.failure);

  /// Why.
  final BuildFailure failure;

  @override
  List<Object?> get props => [failure];
}
