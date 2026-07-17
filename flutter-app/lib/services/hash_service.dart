import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const int _chunkSize = 1 * 1024 * 1024; // 1 MB chunks

// Simple Sink<Digest> implementation — avoids dart:convert compatibility issues
class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

// Top-level — required by compute()
Future<String?> _computeMd5(String filePath) async {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return null;

    final stat = file.statSync();
    if (stat.size == 0) return null;

    final sink  = _DigestSink();
    final input = md5.startChunkedConversion(sink);

    final raf = file.openSync(mode: FileMode.read);
    try {
      int offset = 0;
      final size = stat.size;
      while (offset < size) {
        final toRead = (size - offset).clamp(0, _chunkSize);
        final chunk  = raf.readSync(toRead);
        if (chunk.isEmpty) break;
        input.add(chunk);
        offset += chunk.length;
      }
      input.close();
    } finally {
      raf.closeSync();
    }

    return sink.value?.toString();
  } on FileSystemException catch (e) {
    debugPrint('[HashService] FileSystemException: $e');
    return null;
  } catch (e) {
    debugPrint('[HashService] Error: $e');
    return null;
  }
}

class HashService {
  const HashService();

  /// MD5 of a single file — runs in a separate Isolate via compute().
  Future<String?> md5Of(String filePath) => compute(_computeMd5, filePath);

  /// Hash many files with limited concurrency (default 4 isolates at once).
  Future<Map<String, String?>> hashAll(
    List<String> paths, {
    int concurrency = 4,
  }) async {
    final results = <String, String?>{};
    final queue   = List<String>.from(paths);

    while (queue.isNotEmpty) {
      final batch = <String>[];
      while (batch.length < concurrency && queue.isNotEmpty) {
        batch.add(queue.removeAt(0));
      }
      final hashes = await Future.wait(batch.map(md5Of));
      for (var i = 0; i < batch.length; i++) {
        results[batch[i]] = hashes[i];
      }
    }
    return results;
  }

  /// Quick check: same size AND same MD5 → truly identical.
  Future<bool> areIdentical(String a, String b) async {
    try {
      if (File(a).statSync().size != File(b).statSync().size) return false;
      final ha = await md5Of(a);
      final hb = await md5Of(b);
      return ha != null && ha == hb;
    } catch (_) {
      return false;
    }
  }
}
