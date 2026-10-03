# code_map_repository

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

The repository the [dart_code_3D](https://github.com/hawkbee1/dart_code_3d) blocs use: it
**builds** code maps (fetch → analyze → layout → encode), **opens**, **imports**, **stores**
and **shares** them. Pure Dart.

## Part of hawkbee

This repository is a git submodule of the
[hawkbee](https://github.com/hawkbee1/hawkbee) monorepo and **only builds inside it**:

```sh
git clone --recurse-submodules https://github.com/hawkbee1/hawkbee.git
cd hawkbee && flutter pub get
```

## Usage

```dart
final repository = CodeMapRepository(
  sourceClient: CodeSourceClient(),
  store: InMemoryCodeMapStore(), // the app provides platform storage
);
await for (final event in repository.build(source, rules, cancel: token)) {
  switch (event) {
    case BuildProgress(:final stage, :final fraction):
      print('$stage ${(fraction * 100).round()}%');
    case BuildSucceeded(:final file):
      await repository.save(file);
    case BuildFailed(:final failure):
      print('${failure.kind}: ${failure.message}');
  }
}
```

- **Progress** is weighted per stage (fetch 0–20%, analysis 20–80%, layout 80–95%, encoding
  95–100%) and never goes backwards.
- **Failures** are typed (`BuildFailureKind`: source not found, invalid URL, private or missing
  repository, rate limited, network, invalid archive, unsupported on web, invalid file,
  analysis error, cancelled), with a message and technical details.
- The fetched code (`SourceSnapshot`) is **always disposed**, including on cancel.
- The analysis runs through `defaultEngineRunner()` and layout, encoding and decoding through
  `defaultMapWorker()`: isolates on native platforms, inline on the web.
- `open(file)` decodes for the viewer; `importBytes(name, bytes)` accepts `.dc3d` and plain
  `.fscene` (a newer schema gives an "update the app" failure); `exportForSharing(file)` gives
  `<name>.dc3d`; `recent()` lists stored maps newest first.
- `CodeMapStore` is implemented by the app with platform storage; `InMemoryCodeMapStore` serves
  tests and the web.

Measured on 2026-10-04, building from a local folder: flutter_scene in 7.8 s (1.64 MB), AltMe in
7.6 s (1.50 MB); opening either takes about 0.85 s.

## Running tests

```sh
very_good test --coverage
```

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
