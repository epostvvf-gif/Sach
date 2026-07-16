import 'file_item.dart';

enum MatchType { exactMd5, similarImage, similarName }

class DuplicateGroup {
  final FileItem original;
  final List<FileItem> duplicates;
  final MatchType matchType;
  final double confidence;

  const DuplicateGroup({
    required this.original,
    required this.duplicates,
    required this.matchType,
    this.confidence = 1.0,
  });

  int get reclaimableBytes =>
      duplicates.fold(0, (sum, f) => sum + f.sizeBytes);

  List<FileItem> get allFiles => [original, ...duplicates];

  int get count => duplicates.length + 1;

  Map<String, dynamic> toJson() => {
        'original':   original.toJson(),
        'duplicates': duplicates.map((f) => f.toJson()).toList(),
        'matchType':  matchType.name,
        'confidence': confidence,
      };

  factory DuplicateGroup.fromJson(Map<String, dynamic> j) => DuplicateGroup(
        original:   FileItem.fromJson(j['original'] as Map<String, dynamic>),
        duplicates: (j['duplicates'] as List<dynamic>)
            .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        matchType:  MatchType.values.byName(j['matchType'] as String),
        confidence: (j['confidence'] as num).toDouble(),
      );

  @override
  String toString() =>
      'DuplicateGroup(${matchType.name}, $count files, '
      '${(reclaimableBytes / 1024 / 1024).toStringAsFixed(1)} MB)';
}
