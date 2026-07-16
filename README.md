# Duplicate Cleaner — Flutter Android App

Scans phone storage and SD card for duplicate files (exact MD5 + similar images/documents) and safely moves them to a quarantine folder.

## ✨ Features

- 🔍 **Exact duplicate detection** — MD5 hash comparison
- 🖼️ **Similar image detection** — perceptual hashing (average hash)
- 📄 **Similar document detection** — Jaccard token similarity
- 🧪 **Dry Run mode** — preview moves without touching any files
- 📁 **SD Card support** — scans both internal and external storage
- 📊 **Live progress** — real-time file count and current path
- ↩️ **Undo** — move quarantined files back to original location
- 🗓️ **Dated quarantine folders** — `Duplicates_Exact_2025-07-17/`

## 📱 Download APK

1. Go to **Actions** tab above
2. Click the latest **Build Flutter APK** run
3. Download **duplicate-cleaner-debug-apk** artifact
4. Install the APK on your Android device
   - Enable "Install from unknown sources" in Settings → Security

## 🛠️ Build Locally

```bash
git clone <this-repo>
cd <repo>

# Copy source into a fresh Flutter project
flutter create --org com.example --project-name duplicate_cleaner myapp
cp -r flutter-app/lib myapp/
cp flutter-app/pubspec.yaml myapp/pubspec.yaml
cp flutter-app/android/AndroidManifest.xml myapp/android/app/src/main/AndroidManifest.xml

cd myapp
flutter pub get
flutter run          # debug on connected device
flutter build apk    # release APK (needs signing)
```

## 📂 Project Structure

```
flutter-app/
├── pubspec.yaml
├── android/
│   ├── AndroidManifest.xml    ← storage permissions
│   └── file_paths.xml         ← FileProvider paths
└── lib/
    ├── main.dart              ← permission gate + app entry
    ├── app.dart               ← MaterialApp + M3 theme
    ├── core/
    │   └── permissions.dart   ← Android storage permission logic
    ├── models/
    │   ├── file_item.dart     ← file data + MD5/hash fields
    │   ├── duplicate_group.dart ← original + duplicates + match type
    │   └── scan_result.dart   ← scan state, progress, result
    ├── services/
    │   ├── hash_service.dart      ← MD5 via Isolate, chunked
    │   ├── scanner_service.dart   ← recursive directory walk
    │   ├── similarity_service.dart ← perceptual hash + Jaccard
    │   └── cleaner_service.dart   ← move/undo with dry-run
    ├── providers/
    │   ├── settings_provider.dart ← persisted user prefs
    │   ├── scan_provider.dart     ← scan lifecycle + clean/undo
    │   └── results_provider.dart  ← filter/sort/selection
    └── pages/
        ├── home/home_page.dart    ← storage cards, start scan
        ├── scan/scan_page.dart    ← live progress animation
        └── results/results_page.dart ← duplicate groups + bulk clean
```

## ⚙️ Permissions Required

| Permission | Purpose |
|---|---|
| `READ_MEDIA_IMAGES/VIDEO/AUDIO` | Android 13+ media access |
| `MANAGE_EXTERNAL_STORAGE` | Android 11+ full filesystem |
| `READ/WRITE_EXTERNAL_STORAGE` | Android 9-10 |

## 🔒 Safety

- **Dry Run is ON by default** — no files are moved until you disable it
- Files are **moved** to `/storage/emulated/0/DuplicateCleaner/`, never deleted
- **Undo** button restores all moved files to their original paths
