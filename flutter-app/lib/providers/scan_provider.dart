import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/duplicate_group.dart';
import '../models/file_item.dart';
import '../models/scan_result.dart';
import '../services/cleaner_service.dart';
import '../services/hash_service.dart';
import '../services/scanner_service.dart';
import '../services/similarity_service.dart';
import 'settings_provider.dart';

// ── Scan state ────────────────────────────────────────────────────────────────

class ScanState {
  final ScanStatus     status;
  final ScanProgress?  latestProgress;
  final ScanResult?    result;
  final CleanSummary?  lastCleanSummary;
  final String?        errorMessage;

  const ScanState({
    this.status          = ScanStatus.idle,
    this.latestProgress,
    this.result,
    this.lastCleanSummary,
    this.errorMessage,
  });

  bool get isRunning => status == ScanStatus.scanning ||
      status == ScanStatus.hashing ||
      status == ScanStatus.comparing;
  bool get isDone     => status == ScanStatus.done;
  bool get hasResults => result != null && result!.groups.isNotEmpty;

  ScanState copyWith({
    ScanStatus?    status,
    ScanProgress?  latestProgress,
    ScanResult?    result,
    CleanSummary?  lastCleanSummary,
    String?        errorMessage,
    bool           clearError = false,
  }) =>
      ScanState(
        status:           status           ?? this.status,
        latestProgress:   latestProgress   ?? this.latestProgress,
        result:           result           ?? this.result,
        lastCleanSummary: lastCleanSummary ?? this.lastCleanSummary,
        errorMessage:     clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Service providers ─────────────────────────────────────────────────────────

final scannerServiceProvider    = Provider((_) => const ScannerService());
final hashServiceProvider       = Provider((_) => const HashService());
final similarityServiceProvider = Provider((_) => const SimilarityService());
final cleanerServiceProvider    = Provider((_) => const CleanerService());

// ── Scan notifier ─────────────────────────────────────────────────────────────

class ScanNotifier extends Notifier<ScanState> {
  CancelToken? _cancelToken;

  @override
  ScanState build() => const ScanState();

  Future<void> startScan() async {
    if (state.isRunning) return;

    final settings = ref.read(settingsProvider);
    final scanner  = ref.read(scannerServiceProvider);
    final hasher   = ref.read(hashServiceProvider);
    final similar  = ref.read(similarityServiceProvider);

    _cancelToken = CancelToken();
    state = state.copyWith(status: ScanStatus.scanning, clearError: true);

    try {
      // ── Phase 1: Walk directories ─────────────────────────────────────────
      final roots    = _buildRoots(settings);
      final allFiles = <FileItem>[];

      await for (final progress in scanner.scan(
        roots:            roots,
        maxFileSizeBytes: settings.maxFileSizeBytes,
        includeHidden:    settings.includeHiddenFiles,
        cancelToken:      _cancelToken,
      )) {
        if (_cancelToken?.isCancelled == true) {
          state = state.copyWith(status: ScanStatus.cancelled);
          return;
        }
        state = state.copyWith(latestProgress: progress);

        if (progress.status == ScanStatus.scanning &&
            progress.currentPath.isNotEmpty) {
          final item = FileItem.fromFilePath(progress.currentPath);
          if (item != null) allFiles.add(item);
        }
      }

      if (_cancelToken?.isCancelled == true) {
        state = state.copyWith(status: ScanStatus.cancelled);
        return;
      }

      // ── Phase 2: Hash (MD5) ───────────────────────────────────────────────
      state = state.copyWith(
        status: ScanStatus.hashing,
        latestProgress: ScanProgress(
          status:      ScanStatus.hashing,
          totalFiles:  allFiles.length,
          currentPath: 'Computing MD5 hashes…',
        ),
      );

      final hashMap = await hasher.hashAll(
        allFiles.map((f) => f.path).toList(),
        concurrency: 4,
      );

      final hashedFiles = allFiles.map((f) {
        final h = hashMap[f.path];
        return h != null ? f.copyWith(md5: h) : f;
      }).toList();

      if (_cancelToken?.isCancelled == true) {
        state = state.copyWith(status: ScanStatus.cancelled);
        return;
      }

      // ── Phase 3: Exact duplicates (same MD5) ──────────────────────────────
      state = state.copyWith(
        status: ScanStatus.comparing,
        latestProgress: ScanProgress(
          status:      ScanStatus.comparing,
          totalFiles:  hashedFiles.length,
          currentPath: 'Finding exact duplicates…',
        ),
      );

      final exactGroups = _groupByMd5(hashedFiles);

      // ── Phase 4: Similar files ────────────────────────────────────────────
      final exactPaths = exactGroups
          .expand((g) => g.allFiles)
          .map((f) => f.path)
          .toSet();

      final candidates = hashedFiles
          .where((f) => !exactPaths.contains(f.path))
          .toList();

      final semanticGroups = <DuplicateGroup>[];
      final byType = <FileType, List<FileItem>>{};
      for (final f in candidates) {
        (byType[f.type] ??= []).add(f);
      }

      for (final bucket in byType.values) {
        if (bucket.length < 2) continue;
        final pairs = await similar.findSimilarPairs(bucket, concurrency: 3);
        for (final pair in pairs) {
          semanticGroups.add(DuplicateGroup(
            original:   pair.a,
            duplicates: [pair.b],
            matchType:  pair.result.matchType,
            confidence: pair.result.confidence,
          ));
        }
      }

      // ── Phase 5: Build result ─────────────────────────────────────────────
      final allGroups = [...exactGroups, ...semanticGroups];

      state = state.copyWith(
        status: ScanStatus.done,
        result: ScanResult(
          id:                DateTime.now().millisecondsSinceEpoch.toString(),
          startedAt:         DateTime.now(),
          finishedAt:        DateTime.now(),
          scannedPaths:      roots ?? ['/storage/emulated/0'],
          totalFilesScanned: allFiles.length,
          groups:            allGroups,
          wasDryRun:         settings.dryRun,
        ),
        latestProgress: ScanProgress(
          status:       ScanStatus.done,
          totalFiles:   allFiles.length,
          scannedFiles: allFiles.length,
          currentPath:  'Done — ${allGroups.length} groups found',
        ),
      );
    } catch (e, st) {
      state = state.copyWith(
        status:       ScanStatus.error,
        errorMessage: e.toString(),
      );
      assert(() {
        // ignore: avoid_print
        print('[ScanNotifier] Error:\n$e\n$st');
        return true;
      }());
    }
  }

  void cancelScan() {
    _cancelToken?.cancel();
    state = state.copyWith(status: ScanStatus.cancelled);
  }

  Future<void> cleanDuplicates({List<DuplicateGroup>? groups}) async {
    final settings = ref.read(settingsProvider);
    final cleaner  = ref.read(cleanerServiceProvider);
    final target   = groups ?? state.result?.groups ?? [];
    if (target.isEmpty) return;

    final summary = await cleaner.cleanGroups(
      groups:          target,
      dryRun:          settings.dryRun,
      datedSubfolders: settings.datedSubfolders,
      baseDir:         settings.customDestinationPath,
    );
    state = state.copyWith(lastCleanSummary: summary);
  }

  Future<void> undoLastClean() async {
    final last = state.lastCleanSummary;
    if (last == null) return;
    final cleaner = ref.read(cleanerServiceProvider);
    final undone  = await cleaner.undoClean(last);
    state = state.copyWith(lastCleanSummary: undone);
  }

  void reset() {
    _cancelToken?.cancel();
    state = const ScanState();
  }

  List<String>? _buildRoots(AppSettings s) {
    if (s.customScanPaths.isNotEmpty) return s.customScanPaths;
    // null = ScannerService auto-discovers internal + SD card
    if (s.scanInternalStorage && s.scanSdCard) return null;
    if (s.scanInternalStorage) return ['/storage/emulated/0'];
    return null;
  }

  List<DuplicateGroup> _groupByMd5(List<FileItem> files) {
    final map = <String, List<FileItem>>{};
    for (final f in files) {
      final h = f.md5;
      if (h == null || h.isEmpty) continue;
      (map[h] ??= []).add(f);
    }

    return map.entries
        .where((e) => e.value.length >= 2)
        .map((e) {
          final bucket = e.value
            ..sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
          return DuplicateGroup(
            original:   bucket.first,
            duplicates: bucket.skip(1).toList(),
            matchType:  MatchType.exactMd5,
            confidence: 1.0,
          );
        })
        .toList();
  }
}

final scanProvider = NotifierProvider<ScanNotifier, ScanState>(
  ScanNotifier.new,
);
