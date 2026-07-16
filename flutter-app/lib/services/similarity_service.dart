import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/duplicate_group.dart';
import '../models/file_item.dart';

const int    _imageHammingThreshold = 10;   // out of 64 bits
const double _textJaccardThreshold  = 0.5;
const int    _maxTextBytes          = 256 * 1024; // 256 KB

const _textExtensions = {
  'txt','md','csv','json','xml','html','htm','yaml','yml',
  'ini','log','dart','java','kt','py','js','ts','css','sql',
};

bool _isImage(FileItem f)   => f.type == FileType.image;
bool _isTextDoc(FileItem f) =>
    f.type == FileType.document ||
    _textExtensions.contains(f.path.split('.').last.toLowerCase());

// ── Similarity result ─────────────────────────────────────────────────────────

class SimilarityResult {
  final double    confidence;
  final MatchType matchType;
  final bool      isSimilar;

  const SimilarityResult({
    required this.confidence,
    required this.matchType,
    required this.isSimilar,
  });

  static const none = SimilarityResult(
    confidence: 0.0,
    matchType:  MatchType.exactMd5,
    isSimilar:  false,
  );
}

// ── Isolate payloads (plain Dart — sendable across isolates) ──────────────────

class _ImageHashPayload {
  final String pathA, pathB;
  const _ImageHashPayload(this.pathA, this.pathB);
}

class _TextPayload {
  final String pathA, pathB;
  const _TextPayload(this.pathA, this.pathB);
}

// ── Top-level isolate functions ───────────────────────────────────────────────

Future<int> _computeHammingDistance(_ImageHashPayload p) async {
  try {
    final hashA = await _perceptualHash(p.pathA);
    final hashB = await _perceptualHash(p.pathB);
    if (hashA == null || hashB == null) return -1;
    return _hamming64(hashA, hashB);
  } catch (e) {
    debugPrint('[Similarity] Hamming error: $e');
    return -1;
  }
}

Future<double> _computeJaccard(_TextPayload p) async {
  try {
    final tokensA = await _tokeniseFile(p.pathA);
    final tokensB = await _tokeniseFile(p.pathB);
    if (tokensA == null || tokensB == null) return -1;
    return _jaccard(tokensA, tokensB);
  } catch (e) {
    debugPrint('[Similarity] Jaccard error: $e');
    return -1;
  }
}

Future<int?> _isolatePerceptualHash(String path) => _perceptualHash(path);

// ── Perceptual hash (average hash — aHash) ────────────────────────────────────

Future<int?> _perceptualHash(String path) async {
  try {
    final bytes   = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final small = img.copyResize(decoded,
        width: 8, height: 8, interpolation: img.Interpolation.average);

    final pixels = List<int>.generate(64, (i) {
      final pixel = small.getPixel(i % 8, i ~/ 8);
      return ((0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b))
          .round();
    });

    final avg = pixels.reduce((a, b) => a + b) ~/ 64;

    int hash = 0;
    for (int i = 0; i < 64; i++) {
      if (pixels[i] >= avg) hash |= (1 << i);
    }
    return hash;
  } catch (_) {
    return null;
  }
}

int _hamming64(int a, int b) {
  int xor   = a ^ b;
  int count = 0;
  while (xor != 0) {
    count += xor & 1;
    xor >>= 1;
  }
  return count;
}

double _hammingToConfidence(int distance) => 1.0 - (distance / 64.0);

// ── Text similarity (Jaccard on word tokens) ──────────────────────────────────

Future<Set<String>?> _tokeniseFile(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;

    final size    = file.statSync().size;
    final readSize = math.min(size, _maxTextBytes);

    final raf = file.openSync();
    final Uint8List bytes = raf.readSync(readSize);
    raf.closeSync();

    return String.fromCharCodes(bytes)
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length > 2)
        .toSet();
  } catch (_) {
    return null;
  }
}

double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  return a.intersection(b).length / a.union(b).length;
}

// ── Public service ────────────────────────────────────────────────────────────

class SimilarityService {
  const SimilarityService();

  Future<SimilarityResult> compareFiles(FileItem a, FileItem b) async {
    if (a.type != b.type) return SimilarityResult.none;
    if (_isImage(a))   return _compareImages(a.path, b.path);
    if (_isTextDoc(a)) return _compareText(a.path, b.path);
    if (a.name.toLowerCase() == b.name.toLowerCase()) {
      return const SimilarityResult(
          confidence: 0.7,
          matchType:  MatchType.similarName,
          isSimilar:  true);
    }
    return SimilarityResult.none;
  }

  Future<SimilarityResult> _compareImages(String a, String b) async {
    final distance = await compute(
        _computeHammingDistance, _ImageHashPayload(a, b));
    if (distance < 0) return SimilarityResult.none;
    return SimilarityResult(
      confidence: _hammingToConfidence(distance),
      matchType:  MatchType.similarImage,
      isSimilar:  distance <= _imageHammingThreshold,
    );
  }

  Future<SimilarityResult> _compareText(String a, String b) async {
    final score = await compute(_computeJaccard, _TextPayload(a, b));
    if (score < 0) return SimilarityResult.none;
    return SimilarityResult(
      confidence: score,
      matchType:  MatchType.similarName,
      isSimilar:  score >= _textJaccardThreshold,
    );
  }

  Future<List<({FileItem a, FileItem b, SimilarityResult result})>>
      findSimilarPairs(List<FileItem> files, {int concurrency = 3}) async {
    final pairs = <({FileItem a, FileItem b})>[];
    for (int i = 0; i < files.length; i++) {
      for (int j = i + 1; j < files.length; j++) {
        if (files[i].type == files[j].type) {
          pairs.add((a: files[i], b: files[j]));
        }
      }
    }

    final out   = <({FileItem a, FileItem b, SimilarityResult result})>[];
    final queue = List.of(pairs);

    while (queue.isNotEmpty) {
      final batch = <({FileItem a, FileItem b})>[];
      while (batch.length < concurrency && queue.isNotEmpty) {
        batch.add(queue.removeAt(0));
      }
      final results =
          await Future.wait(batch.map((p) => compareFiles(p.a, p.b)));
      for (var i = 0; i < batch.length; i++) {
        if (results[i].isSimilar) {
          out.add((a: batch[i].a, b: batch[i].b, result: results[i]));
        }
      }
    }
    return out;
  }

  Future<int?> perceptualHashOf(String imagePath) async {
    try {
      return await compute(_isolatePerceptualHash, imagePath);
    } catch (_) {
      return null;
    }
  }
}
