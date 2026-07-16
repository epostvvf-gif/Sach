import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/duplicate_group.dart';
import '../models/file_item.dart';

// ── Result types ──────────────────────────────────────────────────────────────

enum MoveStatus { moved, skippedDryRun, skippedAlreadyGone, failed }

class MoveRecord {
  final String     sourcePath;
  final String     destinationPath;
  final MoveStatus status;
  final String?    errorMessage;

  const MoveRecord({
    required this.sourcePath,
    required this.destinationPath,
    required this.status,
    this.errorMessage,
  });

  bool get succeeded => status == MoveStatus.moved;

  @override
  String toString() =>
      '[${status.name}] $sourcePath → $destinationPath'
      '${errorMessage != null ? " ($errorMessage)" : ""}';
}

class CleanSummary {
  final bool          wasDryRun;
  final List<MoveRecord> records;
  final DateTime      completedAt;

  const CleanSummary({
    required this.wasDryRun,
    required this.records,
    required this.completedAt,
  });

  int get totalAttempted => records.length;
  int get totalMoved     => records.where((r) => r.succeeded).length;
  int get totalFailed    => records.where((r) => r.status == MoveStatus.failed).length;
  int get totalSkipped   => records.where((r) =>
      r.status == MoveStatus.skippedDryRun ||
      r.status == MoveStatus.skippedAlreadyGone).length;

  List<MoveRecord> get moved  => records.where((r) => r.succeeded).toList();
  List<MoveRecord> get failed => records.where((r) => r.status == MoveStatus.failed).toList();

  @override
  String toString() =>
      'CleanSummary(dryRun=$wasDryRun, moved=$totalMoved, '
      'failed=$totalFailed, skipped=$totalSkipped)';
}

const _exactFolderBase    = 'Duplicates_Exact';
const _semanticFolderBase = 'Duplicates_Semantic';

// ── Service ───────────────────────────────────────────────────────────────────

class CleanerService {
  const CleanerService();

  Future<CleanSummary> cleanGroups({
    required List<DuplicateGroup> groups,
    bool dryRun          = false,
    bool datedSubfolders = true,
    String? baseDir,
    void Function(MoveRecord)? onProgress,
  }) async {
    final root       = baseDir ?? await _defaultBaseDir();
    final dateSuffix = datedSubfolders ? '_${_today()}' : '';
    final records    = <MoveRecord>[];

    for (final group in groups) {
      final folderName = group.matchType == MatchType.exactMd5
          ? '$_exactFolderBase$dateSuffix'
          : '$_semanticFolderBase$dateSuffix';
      final destDir = Directory(p.join(root, folderName));
      if (!dryRun) await _ensureDir(destDir);

      for (final file in group.duplicates) {
        final record = await _moveOne(
            source: file, destDir: destDir, dryRun: dryRun);
        records.add(record);
        onProgress?.call(record);
      }
    }

    return CleanSummary(
      wasDryRun:   dryRun,
      records:     records,
      completedAt: DateTime.now(),
    );
  }

  Future<CleanSummary> cleanSingle({
    required FileItem file,
    required MatchType matchType,
    bool dryRun          = false,
    bool datedSubfolders = true,
    String? baseDir,
  }) async {
    final root       = baseDir ?? await _defaultBaseDir();
    final dateSuffix = datedSubfolders ? '_${_today()}' : '';
    final folderName = matchType == MatchType.exactMd5
        ? '$_exactFolderBase$dateSuffix'
        : '$_semanticFolderBase$dateSuffix';
    final destDir = Directory(p.join(root, folderName));
    if (!dryRun) await _ensureDir(destDir);

    final record = await _moveOne(source: file, destDir: destDir, dryRun: dryRun);
    return CleanSummary(
      wasDryRun:   dryRun,
      records:     [record],
      completedAt: DateTime.now(),
    );
  }

  Future<CleanSummary> undoClean(CleanSummary summary) async {
    if (summary.wasDryRun) {
      return CleanSummary(
          wasDryRun: true, records: [], completedAt: DateTime.now());
    }
    final undoRecords = <MoveRecord>[];

    for (final record in summary.moved) {
      final src  = File(record.destinationPath);
      final dest = File(record.sourcePath);

      if (!src.existsSync()) {
        undoRecords.add(MoveRecord(
          sourcePath:      record.destinationPath,
          destinationPath: record.sourcePath,
          status:          MoveStatus.skippedAlreadyGone,
        ));
        continue;
      }

      final r = await _doMove(
          src: src, destDir: dest.parent, forceName: dest.path.split('/').last);
      undoRecords.add(r);
    }

    return CleanSummary(
      wasDryRun:   false,
      records:     undoRecords,
      completedAt: DateTime.now(),
    );
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<MoveRecord> _moveOne({
    required FileItem file,
    required Directory destDir,
    required bool dryRun,
  }) async {
    final src = File(file.path);
    if (!src.existsSync()) {
      return MoveRecord(
        sourcePath:      file.path,
        destinationPath: destDir.path,
        status:          MoveStatus.skippedAlreadyGone,
      );
    }
    if (dryRun) {
      final dest = _resolveDestPath(destDir, file.name);
      debugPrint('[DryRun] Would move: ${file.path} → $dest');
      return MoveRecord(
        sourcePath:      file.path,
        destinationPath: dest,
        status:          MoveStatus.skippedDryRun,
      );
    }
    return _doMove(src: src, destDir: destDir);
  }

  Future<MoveRecord> _doMove({
    required File src,
    required Directory destDir,
    String? forceName,
  }) async {
    final name     = forceName ?? src.path.split('/').last;
    final destPath = _resolveDestPath(destDir, name);

    try {
      try {
        await src.rename(destPath); // atomic rename (same filesystem)
      } on FileSystemException {
        await src.copy(destPath);   // cross-filesystem fallback
        await src.delete();
      }
      debugPrint('[Cleaner] Moved: ${src.path} → $destPath');
      return MoveRecord(
          sourcePath: src.path, destinationPath: destPath, status: MoveStatus.moved);
    } on FileSystemException catch (e) {
      return MoveRecord(
          sourcePath: src.path, destinationPath: destPath,
          status: MoveStatus.failed, errorMessage: e.message);
    } catch (e) {
      return MoveRecord(
          sourcePath: src.path, destinationPath: destPath,
          status: MoveStatus.failed, errorMessage: e.toString());
    }
  }

  String _resolveDestPath(Directory destDir, String fileName) {
    var candidate = p.join(destDir.path, fileName);
    if (!File(candidate).existsSync()) return candidate;

    final ext   = p.extension(fileName);
    final base  = p.basenameWithoutExtension(fileName);
    int counter = 1;
    while (File(candidate).existsSync() && counter <= 999) {
      candidate = p.join(destDir.path, '${base}_($counter)$ext');
      counter++;
    }
    return candidate;
  }

  Future<void> _ensureDir(Directory dir) async {
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
      debugPrint('[Cleaner] Created: ${dir.path}');
    }
  }

  Future<String> _defaultBaseDir() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final root = ext.path.split('Android').first;
        return p.join(root, 'DuplicateCleaner');
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'DuplicateCleaner');
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }
}
