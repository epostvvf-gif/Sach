import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/scan_provider.dart';
import '../../providers/settings_provider.dart';
import '../results/results_page.dart';
import '../scan/scan_page.dart';

// ── Storage info ──────────────────────────────────────────────────────────────

class _StorageInfo {
  final String label;
  final int totalBytes;
  final int freeBytes;
  const _StorageInfo(this.label, this.totalBytes, this.freeBytes);

  int    get usedBytes    => totalBytes - freeBytes;
  double get usedFraction => totalBytes > 0
      ? (usedBytes / totalBytes).clamp(0.0, 1.0)
      : 0;

  String _fmt(int b) {
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
    if (b >= 1048576)    return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  String get usedLabel  => _fmt(usedBytes);
  String get totalLabel => _fmt(totalBytes);
  String get freeLabel  => _fmt(freeBytes);
}

Future<List<_StorageInfo>> _loadStorageInfo() async {
  final infos = <_StorageInfo>[];
  try {
    final r = await Process.run('df', ['-k', '/storage/emulated/0']);
    final lines = r.stdout.toString().trim().split('\n');
    if (lines.length >= 2) {
      final cols = lines.last.trim().split(RegExp(r'\s+'));
      if (cols.length >= 4) {
        final total = (int.tryParse(cols[1]) ?? 0) * 1024;
        final free  = (int.tryParse(cols[3]) ?? 0) * 1024;
        if (total > 0) infos.add(_StorageInfo('Internal Storage', total, free));
      }
    }
  } catch (_) {}

  try {
    for (final entry in Directory('/storage').listSync()) {
      final name = entry.path.split('/').last;
      if (name == 'emulated' || name == 'self') continue;
      if (entry is! Directory) continue;
      final r2 = await Process.run('df', ['-k', entry.path]);
      final ls = r2.stdout.toString().trim().split('\n');
      if (ls.length >= 2) {
        final cols = ls.last.trim().split(RegExp(r'\s+'));
        if (cols.length >= 4) {
          final total = (int.tryParse(cols[1]) ?? 0) * 1024;
          final free  = (int.tryParse(cols[3]) ?? 0) * 1024;
          if (total > 0) infos.add(_StorageInfo('SD Card ($name)', total, free));
        }
      }
    }
  } catch (_) {}

  if (infos.isEmpty) {
    infos.add(const _StorageInfo('Internal Storage', 0, 0));
  }
  return infos;
}

// ── Home page ─────────────────────────────────────────────────────────────────

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<_StorageInfo> _storage = [];

  @override
  void initState() {
    super.initState();
    _loadStorageInfo().then((s) {
      if (mounted) setState(() => _storage = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final tt       = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final scanSt   = ref.watch(scanProvider);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Duplicate Cleaner'),
            actions: [
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Settings',
                onPressed: () => _showSettings(context),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (settings.dryRun)
                  _DryRunBanner(
                    onDisable: () =>
                        ref.read(settingsProvider.notifier).setDryRun(false),
                  ),
                const SizedBox(height: 16),

                Text('Storage', style: tt.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _storage.isEmpty
                    ? _StorageShimmer()
                    : Column(
                        children: _storage.map((s) => _StorageCard(info: s)).toList()),

                const SizedBox(height: 28),

                if (scanSt.result != null) ...[
                  Text('Last Scan', style: tt.titleMedium?.copyWith(
                      color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  _LastScanCard(
                    result: scanSt.result!,
                    onView: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ResultsPage())),
                  ),
                  const SizedBox(height: 28),
                ],

                Text('Will scan for', style: tt.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: const [
                  _Chip(Icons.fingerprint,          'Exact MD5 duplicates'),
                  _Chip(Icons.image_search,          'Similar images'),
                  _Chip(Icons.description_outlined,  'Similar documents'),
                  _Chip(Icons.sd_card_outlined,      'SD card'),
                ]),

                const SizedBox(height: 48),
                _StartButton(
                  isRunning: scanSt.isRunning,
                  onTap: () {
                    if (scanSt.isRunning) {
                      ref.read(scanProvider.notifier).cancelScan();
                    } else {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ScanPage()));
                    }
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _SettingsSheet(),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _DryRunBanner extends StatelessWidget {
  final VoidCallback onDisable;
  const _DryRunBanner({required this.onDisable});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.science_outlined, color: cs.onTertiaryContainer),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Dry Run ON — no files will be moved.',
              style: TextStyle(
                  color: cs.onTertiaryContainer, fontWeight: FontWeight.w500)),
        ),
        TextButton(onPressed: onDisable, child: const Text('Disable')),
      ]),
    );
  }
}

class _StorageCard extends StatelessWidget {
  final _StorageInfo info;
  const _StorageCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final fraction = info.usedFraction;
    final color    = fraction > 0.85 ? cs.error : cs.primary;

    return Card(
      color: cs.surfaceContainer,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.storage_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Text(info.label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${info.usedLabel} / ${info.totalLabel}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 10,
              backgroundColor: cs.surfaceContainerHighest,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text('${info.freeLabel} free',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _StorageShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 100,
      decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(20)),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _LastScanCard extends StatelessWidget {
  final dynamic result;
  final VoidCallback onView;
  const _LastScanCard({required this.result, required this.onView});

  String _fmt(int b) {
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
    if (b >= 1048576)    return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _Stat('Groups',     '${result.duplicateGroupCount}'),
            _Stat('Duplicates', '${result.duplicateFileCount}'),
            _Stat('Save',       _fmt(result.totalReclaimableBytes)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
                onPressed: onView, child: const Text('View Results')),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(children: [
      Text(value,
          style: tt.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
      Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(50)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: cs.onSecondaryContainer),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _StartButton extends StatelessWidget {
  final bool isRunning;
  final VoidCallback onTap;
  const _StartButton({required this.isRunning, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(isRunning ? Icons.stop_rounded : Icons.search_rounded),
        label: Text(isRunning ? 'Cancel Scan' : 'Start Scan',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isRunning ? cs.error : null,
        ),
      ),
    );
  }
}

// ── Settings sheet ────────────────────────────────────────────────────────────

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s  = ref.watch(settingsProvider);
    final sn = ref.read(settingsProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          Text('Settings',
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _SettingTile(
            icon: Icons.science_outlined,
            title: 'Dry Run Mode',
            subtitle: 'Preview moves without touching files',
            trailing: Switch(value: s.dryRun, onChanged: sn.setDryRun),
          ),
          _SettingTile(
            icon: Icons.folder_outlined,
            title: 'Dated Subfolders',
            subtitle: 'e.g. Duplicates_Exact_2025-07-17',
            trailing: Switch(value: s.datedSubfolders, onChanged: sn.setDatedSubfolders),
          ),
          _SettingTile(
            icon: Icons.sd_card_outlined,
            title: 'Scan SD Card',
            subtitle: 'Include external SD card storage',
            trailing: Switch(value: s.scanSdCard, onChanged: sn.setScanSdCard),
          ),
          _SettingTile(
            icon: Icons.visibility_off_outlined,
            title: 'Include Hidden Files',
            subtitle: 'Files and folders starting with .',
            trailing: Switch(value: s.includeHiddenFiles, onChanged: sn.setHiddenFiles),
          ),
          const Divider(height: 28),
          Text('Image similarity threshold',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '${(s.imageSimilarityThreshold * 100).round()}%  — '
            '${s.imageSimilarityThreshold >= 0.95 ? "nearly identical" : s.imageSimilarityThreshold >= 0.75 ? "similar" : "loose match"}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Slider(
            value: s.imageSimilarityThreshold,
            min: 0.5, max: 1.0, divisions: 10,
            onChanged: sn.setImageThreshold,
          ),
          const SizedBox(height: 8),
          Text('Skip files larger than',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            s.maxFileSizeBytes == 0
                ? 'No limit'
                : '${s.maxFileSizeBytes ~/ 1048576} MB',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Slider(
            value: (s.maxFileSizeBytes / 1048576).clamp(0, 500),
            min: 0, max: 500, divisions: 20,
            onChanged: (v) => sn.setMaxFileSize((v * 1048576).round()),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () { sn.resetToDefaults(); Navigator.pop(context); },
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset to Defaults'),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String   title, subtitle;
  final Widget   trailing;
  const _SettingTile({
    required this.icon, required this.title,
    required this.subtitle, required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: cs.onSecondaryContainer, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ])),
        trailing,
      ]),
    );
  }
}
