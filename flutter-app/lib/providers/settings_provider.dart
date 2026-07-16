import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final bool   dryRun;
  final int    maxFileSizeBytes;
  final double imageSimilarityThreshold;
  final double textSimilarityThreshold;
  final bool   scanInternalStorage;
  final bool   scanSdCard;
  final bool   datedSubfolders;
  final bool   includeHiddenFiles;
  final List<String> customScanPaths;
  final String? customDestinationPath;

  const AppSettings({
    this.dryRun                   = true,
    this.maxFileSizeBytes         = 52428800,
    this.imageSimilarityThreshold = 0.85,
    this.textSimilarityThreshold  = 0.50,
    this.scanInternalStorage      = true,
    this.scanSdCard               = true,
    this.datedSubfolders          = true,
    this.includeHiddenFiles       = false,
    this.customScanPaths          = const [],
    this.customDestinationPath,
  });

  AppSettings copyWith({
    bool?         dryRun,
    int?          maxFileSizeBytes,
    double?       imageSimilarityThreshold,
    double?       textSimilarityThreshold,
    bool?         scanInternalStorage,
    bool?         scanSdCard,
    bool?         datedSubfolders,
    bool?         includeHiddenFiles,
    List<String>? customScanPaths,
    String?       customDestinationPath,
    bool          clearDestination = false,
  }) =>
      AppSettings(
        dryRun:                   dryRun                   ?? this.dryRun,
        maxFileSizeBytes:         maxFileSizeBytes          ?? this.maxFileSizeBytes,
        imageSimilarityThreshold: imageSimilarityThreshold  ?? this.imageSimilarityThreshold,
        textSimilarityThreshold:  textSimilarityThreshold   ?? this.textSimilarityThreshold,
        scanInternalStorage:      scanInternalStorage        ?? this.scanInternalStorage,
        scanSdCard:               scanSdCard                ?? this.scanSdCard,
        datedSubfolders:          datedSubfolders           ?? this.datedSubfolders,
        includeHiddenFiles:       includeHiddenFiles        ?? this.includeHiddenFiles,
        customScanPaths:          customScanPaths           ?? this.customScanPaths,
        customDestinationPath: clearDestination
            ? null
            : customDestinationPath ?? this.customDestinationPath,
      );
}

// ── SharedPreferences keys ────────────────────────────────────────────────────
const _kDryRun       = 'dry_run';
const _kMaxFileSize  = 'max_file_size';
const _kImgThreshold = 'img_threshold';
const _kTxtThreshold = 'txt_threshold';
const _kScanInternal = 'scan_internal';
const _kScanSdCard   = 'scan_sd_card';
const _kDatedFolders = 'dated_folders';
const _kHiddenFiles  = 'hidden_files';
const _kCustomPaths  = 'custom_paths';
const _kCustomDest   = 'custom_dest';

// ── Notifier ──────────────────────────────────────────────────────────────────
class SettingsNotifier extends Notifier<AppSettings> {
  late SharedPreferences _prefs;

  @override
  AppSettings build() {
    _loadFromPrefs();
    return const AppSettings();
  }

  Future<void> _loadFromPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      dryRun:                   _prefs.getBool(_kDryRun)           ?? true,
      maxFileSizeBytes:         _prefs.getInt(_kMaxFileSize)        ?? 52428800,
      imageSimilarityThreshold: _prefs.getDouble(_kImgThreshold)   ?? 0.85,
      textSimilarityThreshold:  _prefs.getDouble(_kTxtThreshold)   ?? 0.50,
      scanInternalStorage:      _prefs.getBool(_kScanInternal)     ?? true,
      scanSdCard:               _prefs.getBool(_kScanSdCard)       ?? true,
      datedSubfolders:          _prefs.getBool(_kDatedFolders)     ?? true,
      includeHiddenFiles:       _prefs.getBool(_kHiddenFiles)      ?? false,
      customScanPaths:          _prefs.getStringList(_kCustomPaths) ?? [],
      customDestinationPath:    _prefs.getString(_kCustomDest),
    );
  }

  Future<void> _save() async {
    final s = state;
    await Future.wait([
      _prefs.setBool(_kDryRun,        s.dryRun),
      _prefs.setInt(_kMaxFileSize,    s.maxFileSizeBytes),
      _prefs.setDouble(_kImgThreshold, s.imageSimilarityThreshold),
      _prefs.setDouble(_kTxtThreshold, s.textSimilarityThreshold),
      _prefs.setBool(_kScanInternal,  s.scanInternalStorage),
      _prefs.setBool(_kScanSdCard,    s.scanSdCard),
      _prefs.setBool(_kDatedFolders,  s.datedSubfolders),
      _prefs.setBool(_kHiddenFiles,   s.includeHiddenFiles),
      _prefs.setStringList(_kCustomPaths, s.customScanPaths),
      if (s.customDestinationPath != null)
        _prefs.setString(_kCustomDest, s.customDestinationPath!)
      else
        _prefs.remove(_kCustomDest),
    ]);
  }

  Future<void> setDryRun(bool v)           async { state = state.copyWith(dryRun: v);                      await _save(); }
  Future<void> setMaxFileSize(int b)        async { state = state.copyWith(maxFileSizeBytes: b);             await _save(); }
  Future<void> setImageThreshold(double v)  async { state = state.copyWith(imageSimilarityThreshold: v.clamp(0.0,1.0)); await _save(); }
  Future<void> setTextThreshold(double v)   async { state = state.copyWith(textSimilarityThreshold: v.clamp(0.0,1.0));  await _save(); }
  Future<void> setScanInternal(bool v)      async { state = state.copyWith(scanInternalStorage: v);         await _save(); }
  Future<void> setScanSdCard(bool v)        async { state = state.copyWith(scanSdCard: v);                  await _save(); }
  Future<void> setDatedSubfolders(bool v)   async { state = state.copyWith(datedSubfolders: v);             await _save(); }
  Future<void> setHiddenFiles(bool v)       async { state = state.copyWith(includeHiddenFiles: v);          await _save(); }

  Future<void> addCustomPath(String path) async {
    if (state.customScanPaths.contains(path)) return;
    state = state.copyWith(customScanPaths: [...state.customScanPaths, path]);
    await _save();
  }

  Future<void> removeCustomPath(String path) async {
    state = state.copyWith(
        customScanPaths: state.customScanPaths.where((p) => p != path).toList());
    await _save();
  }

  Future<void> setCustomDestination(String? path) async {
    state = path == null
        ? state.copyWith(clearDestination: true)
        : state.copyWith(customDestinationPath: path);
    await _save();
  }

  Future<void> resetToDefaults() async {
    state = const AppSettings();
    await _save();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
