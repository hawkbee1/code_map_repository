import 'dart:typed_data';

import 'package:code_map_repository/code_map_repository.dart';
import 'package:test/test.dart';

void main() {
  group('library', () {
    test('exports what the app needs to start a build', () {
      // Only the barrel is imported: the app never reaches the data packages.
      final sources = <CodeSource>[
        const LocalFolderSource('/tmp/app'),
        const GitRepositorySource('https://github.com/o/r', ref: 'main'),
        ZipBytesSource(fileName: 'a.zip', bytes: Uint8List(0)),
      ];

      expect(sources, hasLength(3));
      expect(GitUrl.tryParse('github.com/o/r')?.host, GitHost.github);
      expect(CancelToken().isCancelled, isFalse);
    });
  });
}
