import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissions {
  const AppPermissions._();

  static Future<bool> requestStoragePermissions() async {
    if (!Platform.isAndroid) return true;

    final sdk = await _androidSdkVersion();

    if (sdk >= 33) {
      final results = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();

      // Also try MANAGE_EXTERNAL_STORAGE for full filesystem
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
      return results.values.any((s) => s.isGranted);
    }

    if (sdk >= 30) {
      if (!await Permission.manageExternalStorage.isGranted) {
        final status = await Permission.manageExternalStorage.request();
        return status.isGranted;
      }
      return true;
    }

    // Android 9–10
    final result = await Permission.storage.request();
    return result.isGranted;
  }

  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final sdk = await _androidSdkVersion();
    if (sdk >= 33) {
      return await Permission.photos.isGranted ||
          await Permission.manageExternalStorage.isGranted;
    }
    if (sdk >= 30) {
      return await Permission.manageExternalStorage.isGranted;
    }
    return await Permission.storage.isGranted;
  }

  static Future<void> openSettings() => openAppSettings();

  static Future<int> _androidSdkVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 0;
    } catch (e) {
      debugPrint('[Permissions] Could not read SDK version: $e');
      return 0;
    }
  }
}
