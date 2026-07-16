import 'duplicate_group.dart';
import 'file_item.dart';

enum ScanStatus { idle, scanning, hashing, comparing, done, cancelled, error }

class ScanProgress {
  final ScanStatus status;
  final int scannedFiles;
  final int totalFiles;
  final String currentPath;
  final String? errorMessage;

  const ScanProgress({
    required this.status,
    this.scannedFiles = 0,
    this.totalFiles   = 0,
    this.currentPath  = '',
    this.errorMessage,
  });

  double get percent =>
      totalFiles > 0 ? (scannedFiles / totalFiles).clamp(0.0, 1.0) : 0.0;

  ScanProgress copyWith({
    ScanStatus? status,
    int?        scannedFiles,
    int?        totalFiles,
    String?     currentPath,
    String?     errorMessage,
  }) =>
      ScanProgress(
        status:       status       ?? this.status,
        scannedFiles: scannedFiles ?? this.scannedFiles,
        totalFiles:   totalFiles   ?? this.totalFiles,
        currentPath:  currentPath  ?? this.currentPath,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

class ScanResult {
  final String id;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<String> scannedPaths;
  final int totalFilesScanned;
  final List<DuplicateGroup> groups;
  final bool wasDryRun;

  const ScanResult({
    required this.id,
    required this.startedAt,
    required this.scannedPaths,
    required this.totalFilesScanned,
    required this.groups,
    required this.wasDryRun,
    this.finishedAt,
  });

  int get duplicateGroupCount => groups.length;

  int get duplicateFileCount =>
      groups.fold(0, (s, g) => s + g.duplicates.length);

  int get totalReclaimableBytes =>
      groups.fold(0, (s, g) => s + g.reclaimableBytes);

  Duration? get duration =>
      finishedAt != null ? finishedAt!.difference(startedAt) : null;

  List<FileItem> get allDuplicateFiles =>
      groups.expand((g) => g.duplicates).toList();

  Map<String, dynamic> toJson() => {
        'id':                id,
        'startedAt':         startedAt.toIso8601String(),
        'finishedAt':        finishedAt?.toIso8601String(),
        'scannedPaths':      scannedPaths,
        'totalFilesScanned': totalFilesScanned,
        'groups':            groups.map((g) => g.toJson()).toList(),
        'wasDryRun':         wasDryRun,
      };

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        id:                j['id']                as String,
        startedAt:         DateTime.parse(j['startedAt'] as String),
        finishedAt:        j['finishedAt'] != null
            ? DateTime.parse(j['finishedAt'] as String)
            : null,
        scannedPaths:      List<String>.from(j['scannedPaths'] as List),
        totalFilesScanned: j['totalFilesScanned'] as int,
        groups:            (j['groups'] as List<dynamic>)
            .map((e) => DuplicateGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        wasDryRun: j['wasDryRun'] as bool,
      );

  @override
  String toString() =>
      'ScanResult($id, $duplicateGroupCount groups, '
      '${(totalReclaimableBytes / 1024 / 1024).toStringAsFixed(1)} MB)';
}
