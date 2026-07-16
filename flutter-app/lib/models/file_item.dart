import 'dart:io';

enum FileType { image, video, audio, document, archive, other }

FileType _detectType(String path) {
  final ext = path.split('.').last.toLowerCase();
  const images   = {'jpg','jpeg','png','gif','bmp','webp','heic','heif','tiff'};
  const videos   = {'mp4','mkv','avi','mov','wmv','flv','3gp','webm','m4v'};
  const audio    = {'mp3','aac','wav','flac','ogg','m4a','wma','opus'};
  const docs     = {'pdf','doc','docx','xls','xlsx','ppt','pptx','txt','md','csv'};
  const archives = {'zip','rar','7z','tar','gz','bz2','apk'};

  if (images.contains(ext))   return FileType.image;
  if (videos.contains(ext))   return FileType.video;
  if (audio.contains(ext))    return FileType.audio;
  if (docs.contains(ext))     return FileType.document;
  if (archives.contains(ext)) return FileType.archive;
  return FileType.other;
}

class FileItem {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;
  final FileType type;
  final String? md5;
  final String? perceptualHash;

  const FileItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.type,
    this.md5,
    this.perceptualHash,
  });

  // ── Static helpers ────────────────────────────────────────────────────────

  static FileType detectType(String path) => _detectType(path);

  factory FileItem.fromFile(File file) {
    final stat = file.statSync();
    return FileItem(
      path:       file.path,
      name:       file.path.split('/').last,
      sizeBytes:  stat.size,
      modifiedAt: stat.modified,
      type:       _detectType(file.path),
    );
  }

  static FileItem? fromFilePath(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return FileItem.fromFile(file);
    } catch (_) {
      return null;
    }
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  FileItem copyWith({String? md5, String? perceptualHash}) => FileItem(
        path:           path,
        name:           name,
        sizeBytes:      sizeBytes,
        modifiedAt:     modifiedAt,
        type:           type,
        md5:            md5            ?? this.md5,
        perceptualHash: perceptualHash ?? this.perceptualHash,
      );

  // ── JSON ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'path':           path,
        'name':           name,
        'sizeBytes':      sizeBytes,
        'modifiedAt':     modifiedAt.toIso8601String(),
        'type':           type.name,
        'md5':            md5,
        'perceptualHash': perceptualHash,
      };

  factory FileItem.fromJson(Map<String, dynamic> j) => FileItem(
        path:           j['path']          as String,
        name:           j['name']          as String,
        sizeBytes:      j['sizeBytes']     as int,
        modifiedAt:     DateTime.parse(j['modifiedAt'] as String),
        type:           FileType.values.byName(j['type'] as String),
        md5:            j['md5']           as String?,
        perceptualHash: j['perceptualHash'] as String?,
      );

  @override
  bool operator ==(Object other) => other is FileItem && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'FileItem($name, ${sizeBytes}B, $type)';
}
