import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scan_result.dart';
import '../../providers/scan_provider.dart';
import '../results/results_page.dart';

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double>   _anim;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_started) {
        _started = true;
        ref.read(scanProvider.notifier).startScan();
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final tt       = Theme.of(context).textTheme;
    final scanSt   = ref.watch(scanProvider);
    final progress = scanSt.latestProgress;

    ref.listen<ScanState>(scanProvider, (_, next) {
      if (next.status == ScanStatus.done && mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const ResultsPage()));
      }
    });

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(_statusTitle(scanSt.status)),
        backgroundColor: Colors.transparent,
        actions: [
          if (scanSt.isRunning)
            TextButton.icon(
              onPressed: () {
                ref.read(scanProvider.notifier).cancelScan();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Pulse animation
            AnimatedBuilder(
              animation: _anim,
              builder: (_, child) => Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width:  160 + (_anim.value * 30),
                    height: 160 + (_anim.value * 30),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primaryContainer
                          .withOpacity(0.3 * _anim.value),
                    ),
                  ),
                  Container(
                    width: 140, height: 140,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primaryContainer),
                    child: child,
                  ),
                ],
              ),
              child: Icon(_statusIcon(scanSt.status), size: 60, color: cs.primary),
            ),

            const SizedBox(height: 36),
            Text(_statusTitle(scanSt.status),
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),

            const SizedBox(height: 10),
            if (progress != null && progress.currentPath.isNotEmpty)
              Text(
                _shortenPath(progress.currentPath),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

            const SizedBox(height: 32),

            // Progress bar
            if (progress != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: progress.totalFiles > 0 ? progress.percent : null,
                  minHeight: 10,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${progress.scannedFiles} files',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  if (progress.totalFiles > 0)
                    Text('${(progress.percent * 100).round()}%',
                        style: tt.bodySmall?.copyWith(
                            color: cs.primary, fontWeight: FontWeight.bold)),
                ],
              ),
            ],

            const SizedBox(height: 40),
            _PhaseRow(currentStatus: scanSt.status),
            const Spacer(flex: 3),

            if (scanSt.status == ScanStatus.error)
              _ErrorCard(
                message: scanSt.errorMessage ?? 'Unknown error',
                onRetry: () => ref.read(scanProvider.notifier).startScan(),
              ),

            if (scanSt.status == ScanStatus.cancelled)
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Home'),
              ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(ScanStatus s) => switch (s) {
        ScanStatus.idle      => Icons.hourglass_empty_rounded,
        ScanStatus.scanning  => Icons.search_rounded,
        ScanStatus.hashing   => Icons.fingerprint,
        ScanStatus.comparing => Icons.compare_rounded,
        ScanStatus.done      => Icons.check_circle_outline_rounded,
        ScanStatus.error     => Icons.error_outline_rounded,
        ScanStatus.cancelled => Icons.cancel_outlined,
      };

  String _statusTitle(ScanStatus s) => switch (s) {
        ScanStatus.idle      => 'Getting ready…',
        ScanStatus.scanning  => 'Walking directories…',
        ScanStatus.hashing   => 'Computing MD5 hashes…',
        ScanStatus.comparing => 'Finding duplicates…',
        ScanStatus.done      => 'Scan complete!',
        ScanStatus.error     => 'Something went wrong',
        ScanStatus.cancelled => 'Scan cancelled',
      };

  String _shortenPath(String path) {
    final parts = path.split('/');
    if (parts.length <= 4) return path;
    return '…/${parts.sublist(parts.length - 3).join('/')}';
  }
}

// ── Phase row ─────────────────────────────────────────────────────────────────

class _PhaseRow extends StatelessWidget {
  final ScanStatus currentStatus;
  const _PhaseRow({required this.currentStatus});

  @override
  Widget build(BuildContext context) {
    const phases = [
      (ScanStatus.scanning,  Icons.folder_open_rounded, 'Walk'),
      (ScanStatus.hashing,   Icons.fingerprint,         'Hash'),
      (ScanStatus.comparing, Icons.compare_rounded,     'Compare'),
      (ScanStatus.done,      Icons.check_rounded,       'Done'),
    ];
    final activeIndex =
        phases.indexWhere((p) => p.$1 == currentStatus);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(phases.length * 2 - 1, (i) {
        if (i.isOdd) {
          return _PhaseLine(active: i ~/ 2 < activeIndex);
        }
        final idx   = i ~/ 2;
        return _PhaseNode(
          icon:   phases[idx].$2,
          label:  phases[idx].$3,
          done:   idx < activeIndex,
          active: idx == activeIndex,
        );
      }),
    );
  }
}

class _PhaseNode extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     done, active;
  const _PhaseNode({required this.icon, required this.label,
      required this.done, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final color = done || active ? cs.primary : cs.outlineVariant;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done || active ? cs.primaryContainer : cs.surfaceContainerHighest,
          border: Border.all(color: color, width: 2),
        ),
        child: Icon(done ? Icons.check_rounded : icon, size: 18, color: color),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: active ? FontWeight.bold : FontWeight.normal)),
    ]);
  }
}

class _PhaseLine extends StatelessWidget {
  final bool active;
  const _PhaseLine({required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 30, height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: active ? cs.primary : cs.outlineVariant,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(message,
              style: TextStyle(color: cs.onErrorContainer),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ]),
      ),
    );
  }
}
