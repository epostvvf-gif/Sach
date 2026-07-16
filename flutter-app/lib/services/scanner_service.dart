import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/file_item.dart';
import '../models/scan_result.dart';

const int    _defaultMaxFileSizeBytes = 50 * 1024 * 1024; // 50 MB
const String _internalStorage        = '/storage/emulated/0';

const Set<String> _skipFolderNames = {
  'android', 'proc', 'sys', 'dev', 'acct', 'cache', 'obb',
};

class ScannerService {
  const ScannerService();

  /// Walk [roots] and emit live [ScanProgress] updates.
  Stream<ScanProgress> scan({
    List<String>? roots,
    int maxFileSizeBytes  = _defaultMaxFileSizeBytes,
    bool includeHidden    = false,
    CancelToken? cancelToken,
  }) async* {
    final scanRoots = roots ?? await _resolveRoots();

    yield ScanProgress(
      status:      ScanStatus.scanning,
      currentPath: 'Discovering storage roots…',
    );

    int scanned = 0;

    for (final root in scanRoots) {
      final dir = Directory(root);
      if (!dir.existsSync()) {
        debugPrint('[Scanner] Root not found: $root');
        continue;
      }

      yield ScanProgress(
        status:       ScanStatus.scanning,
        currentPath:  root,
        scannedFiles: scanned,
      );

      await for (final result in _walkDirectory(
        dir,
        maxFileSizeBytes: maxFileSizeBytes,
        includeHidden:    includeHidden,
        cancelToken:      cancelToken,
      )) {
        if (cancelToken?.isCancelled == true) {
          yield ScanProgress(
            status:       ScanStatus.cancelled,
            scannedFiles: scanned,
            currentPath:  'Cancelled',
          );
          return;
        }

        if (result is _ScanFile) {
          scanned++;
          yield ScanProgress(
            status:       ScanStatus.scanning,
            scannedFiles: scanned,
            currentPath:  result.item.path,
          );
        } else if (result is _ScanError) {
          debugPrint('[Scanner] ${result.error} @ ${result.path}');
        }
      }
    }

    yield ScanProgress(
      status:       ScanStatus.hashing,
      scannedFiles: scanned,
      totalFiles:   scanned,
      currentPath:  'Scan complete — $scanned files',
    );
  }

  /// Convenience: collect all FileItems into a list.
  Future<List<FileItem>> scanToList({
    List<String>? roots,
    int maxFileSizeBytes          = _defaultMaxFileSizeBytes,
    bool includeHidden            = false,
    CancelToken? cancelToken,
    void Function(ScanProgress)? onProgress,
  }) async {
    final items = <FileItem>[];

    await for (final progress in scan(
      roots:            roots,
      maxFileSizeBytes: maxFileSizeBytes,
      includeHidden:    includeHidden,
      cancelToken:      cancelToken,
    )) {
      onProgress?.call(progress);

      if (progress.status == ScanStatus.scanning &&
          progress.currentPath.isNotEmpty) {
        final file = File(progress.currentPath);
        if (file.existsSync()) {
          try {
            items.add(FileItem.fromFile(file));
          } catch (_) {}
        }
      }
    }
    return items;
  }

  /// Probe known Android mount points for SD card directories.
  Future<List<String>> findSdCardPaths() async {
    final found = <String>[];
    final storageDir = Directory('/storage');
    if (storageDir.existsSync()) {
      try {
        for (final entry in storageDir.listSync(followLinks: false)) {
          final name = entry.path.split('/').last;
          if (name == 'emulated' || name == 'self') continue;
          if (entry is Directory) found.add(entry.path);
        }
      } on FileSystemException catch (e) {
        debugPrint('[Scanner] Cannot list /storage: $e');
      }
    }
    return found;
  }

  Future<List<String>> _resolveRoots() async {
    final roots = <String>[_internalStorage];
    roots.addAll(await findSdCardPaths());
    debugPrint('[Scanner] Roots: $roots');
    return roots;
  }

  Stream<_WalkResult> _walkDirectory(
    Directory dir, {
    required int maxFileSizeBytes,
    required bool includeHidden,
    CancelToken? cancelToken,
  }) async* {
    if (cancelToken?.isCancelled == true) return;

    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException catch (e) {
      yield _ScanError(path: dir.path, error: e.toString());
      return;
    }

    for (final entry in entries) {
      if (cancelToken?.isCancelled == true) return;

      final name = entry.path.split('/').last;
      if (!includeHidden && name.startsWith('.')) continue;

      if (entry is Directory) {
        if (_skipFolderNames.contains(name.toLowerCase())) continue;
        yield* _walkDirectory(
          entry,
          maxFileSizeBytes: maxFileSizeBytes,
          includeHidden:    includeHidden,
          cancelToken:      cancelToken,
        );
      } else if (entry is File) {
        try {
          final stat = entry.statSync();
          if (maxFileSizeBytes > 0 && stat.size > maxFileSizeBytes) continue;

          yield _ScanFile(
            item: FileItem(
              path:       entry.path,
              name:       name,
              sizeBytes:  stat.size,
              modifiedAt: stat.modified,
              type:       FileItem.detectType(entry.path),
            ),
          );
        } on FileSystemException catch (e) {
          yield _ScanError(path: entry.path, error: e.toString());
        }
      }
    }
  }
}

// ── Cancellation token ────────────────────────────────────────────────────────

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

// ── Internal sealed results ───────────────────────────────────────────────────

sealed class _WalkResult {}

class _ScanFile extends _WalkResult {
  final FileItem item;
  _ScanFile({required this.item});
}

class _ScanError extends _WalkResult {
  final String path;
  final String error;
  _ScanError({required this.path, required this.error});
}
