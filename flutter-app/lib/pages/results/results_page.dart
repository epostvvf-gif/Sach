import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/duplicate_group.dart';
import '../../models/file_item.dart';
import '../../providers/results_provider.dart';
import '../../providers/scan_provider.dart';
import '../../providers/settings_provider.dart';

class ResultsPage extends ConsumerStatefulWidget {
  const ResultsPage({super.key});

  @override
  ConsumerState<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends ConsumerState<ResultsPage> {
  final _searchCtrl = TextEditingController();
  bool _showSearch  = false;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final groups   = ref.watch(filteredGroupsProvider);
    final stats    = ref.watch(resultStatsProvider);
    final settings = ref.watch(settingsProvider);
    final selected = ref.watch(selectionProvider);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true,
            title: _showSearch
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'Search files…', border: InputBorder.none),
                    onChanged: (q) =>
                        ref.read(resultsFilterProvider.notifier).setSearch(q),
                  )
                : const Text('Results'),
            actions: [
              IconButton(
                icon: Icon(_showSearch
                    ? Icons.close_rounded
                    : Icons.search_rounded),
                onPressed: () {
                  setState(() => _showSearch = !_showSearch);
                  if (!_showSearch) {
                    _searchCtrl.clear();
                    ref.read(resultsFilterProvider.notifier).setSearch('');
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.sort_rounded),
                onPressed: () => _showSortSheet(context),
              ),
            ],
          ),
          SliverToBoxAdapter(
              child: _SummaryBar(stats: stats, isDryRun: settings.dryRun)),
          SliverToBoxAdapter(child: _FilterChips()),
        ],
        body: groups.isEmpty
            ? const _EmptyState()
            : Column(children: [
                if (selected.isNotEmpty)
                  _BulkBar(
                    count: selected.length,
                    isDryRun: settings.dryRun,
                    onClean: () => _cleanSelected(context),
                    onClear: () =>
                        ref.read(selectionProvider.notifier).clearAll(),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: groups.length,
                    itemBuilder: (_, i) {
                      final g = groups[i];
                      final id = g.original.md5 ?? g.original.path;
                      return _GroupTile(
                        group:      g,
                        isSelected: ref.watch(selectionProvider.notifier).isSelected(g),
                        onToggle:   () => ref.read(selectionProvider.notifier).toggle(id),
                        onClean:    () => _cleanGroup(context, g),
                      );
                    },
                  ),
                ),
              ]),
      ),
      floatingActionButton: groups.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                if (selected.isEmpty) {
                  ref.read(selectionProvider.notifier).selectAll(groups);
                } else {
                  _cleanSelected(context);
                }
              },
              icon: Icon(selected.isEmpty
                  ? Icons.checklist_rounded
                  : Icons.cleaning_services_rounded),
              label: Text(selected.isEmpty
                  ? 'Select All'
                  : 'Clean ${selected.length}'),
            ),
    );
  }

  Future<void> _cleanGroup(BuildContext ctx, DuplicateGroup g) async {
    final dry = ref.read(settingsProvider).dryRun;
    await ref.read(scanProvider.notifier).cleanDuplicates(groups: [g]);
    if (mounted) {
      _snack(ctx, dry
          ? 'Dry run: would move ${g.duplicates.length} file(s)'
          : 'Moved ${g.duplicates.length} file(s) to quarantine');
    }
  }

  Future<void> _cleanSelected(BuildContext ctx) async {
    final sel    = ref.read(selectionProvider);
    final groups = ref.read(filteredGroupsProvider);
    final target = groups
        .where((g) => sel.contains(g.original.md5 ?? g.original.path))
        .toList();
    await ref.read(scanProvider.notifier).cleanDuplicates(groups: target);
    ref.read(selectionProvider.notifier).clearAll();
    if (mounted) {
      final dry = ref.read(settingsProvider).dryRun;
      _snack(ctx, dry
          ? 'Dry run: would move files from ${target.length} group(s)'
          : 'Cleaned ${target.length} group(s)');
    }
  }

  void _snack(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showSortSheet(BuildContext ctx) {
    final cur = ref.read(resultsFilterProvider).sort;
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SortSheet(current: cur),
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final ResultsStats stats;
  final bool isDryRun;
  const _SummaryBar({required this.stats, required this.isDryRun});

  String _fmt(int b) {
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
    if (b >= 1048576)    return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Cell('Groups',     '${stats.totalGroups}'),
          _Cell('Duplicates', '${stats.totalDuplicateFiles}'),
          _Cell('Save',       _fmt(stats.totalReclaimableBytes)),
          if (isDryRun)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: cs.tertiary, borderRadius: BorderRadius.circular(8)),
              child: Text('DRY RUN',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: cs.onTertiary)),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label, value;
  const _Cell(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: cs.onPrimaryContainer)),
      Text(label,
          style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
    ]);
  }
}

// ── Filter chips ──────────────────────────────────────────────────────────────

class _FilterChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(resultsFilterProvider).filter;
    final n      = ref.read(resultsFilterProvider.notifier);
    const chips  = [
      (ResultFilter.all,           'All'),
      (ResultFilter.exactOnly,     'Exact'),
      (ResultFilter.similarOnly,   'Similar'),
      (ResultFilter.imagesOnly,    'Images'),
      (ResultFilter.documentsOnly, 'Docs'),
      (ResultFilter.videosOnly,    'Videos'),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: chips.length,
        itemBuilder: (_, i) => FilterChip(
          label: Text(chips[i].$2),
          selected: active == chips[i].$1,
          onSelected: (_) => n.setFilter(chips[i].$1),
        ),
      ),
    );
  }
}

// ── Group tile ────────────────────────────────────────────────────────────────

class _GroupTile extends StatelessWidget {
  final DuplicateGroup group;
  final bool isSelected;
  final VoidCallback onToggle, onClean;
  const _GroupTile({required this.group, required this.isSelected,
      required this.onToggle, required this.onClean});

  String _fmt(int b) {
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final tt    = Theme.of(context).textTheme;
    final exact = group.matchType == MatchType.exactMd5;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isSelected
          ? cs.primaryContainer.withOpacity(0.5)
          : cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: exact ? cs.errorContainer : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_typeIcon(group.original.type),
                    color: exact ? cs.error : cs.secondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(group.original.name,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  _Badge(exact ? 'EXACT' : 'SIMILAR',
                      exact ? cs.error : cs.secondary),
                  const SizedBox(width: 6),
                  Text('${(group.confidence * 100).round()}% match',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ])),
              Checkbox(
                value: isSelected,
                onChanged: (_) => onToggle(),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ]),
            const SizedBox(height: 10),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 10),
            _FileRow(file: group.original, label: 'Keep', color: cs.primary),
            ...group.duplicates.map((f) =>
                _FileRow(file: f, label: 'Move', color: cs.error)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${group.duplicates.length} dup${group.duplicates.length > 1 ? 's' : ''}'
                  ' · Save ${_fmt(group.reclaimableBytes)}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                TextButton.icon(
                  onPressed: onClean,
                  style: TextButton.styleFrom(
                      foregroundColor: cs.error,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4)),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                  label: const Text('Clean'),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  IconData _typeIcon(FileType t) => switch (t) {
        FileType.image    => Icons.image_outlined,
        FileType.video    => Icons.videocam_outlined,
        FileType.audio    => Icons.audiotrack_outlined,
        FileType.document => Icons.description_outlined,
        FileType.archive  => Icons.folder_zip_outlined,
        FileType.other    => Icons.insert_drive_file_outlined,
      };
}

class _FileRow extends StatelessWidget {
  final FileItem file;
  final String label;
  final Color color;
  const _FileRow({required this.file, required this.label, required this.color});

  String _fmt(int b) {
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final parts = file.path.split('/');
    final dir   = parts.length > 1
        ? parts.sublist(0, parts.length - 1).join('/')
            .replaceAll('/storage/emulated/0', '📱')
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            dir.isEmpty ? file.name : '$dir/${file.name}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(_fmt(file.sizeBytes),
            style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color  color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );
}

// ── Bulk action bar ───────────────────────────────────────────────────────────

class _BulkBar extends StatelessWidget {
  final int count;
  final bool isDryRun;
  final VoidCallback onClean, onClear;
  const _BulkBar({required this.count, required this.isDryRun,
      required this.onClean, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Text('$count selected',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSecondaryContainer)),
        const Spacer(),
        TextButton(onPressed: onClear, child: const Text('Clear')),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onClean,
          style: FilledButton.styleFrom(
              backgroundColor: isDryRun ? cs.tertiary : cs.error),
          icon: const Icon(Icons.cleaning_services_rounded, size: 18),
          label: Text(isDryRun ? 'Dry Clean' : 'Clean'),
        ),
      ]),
    );
  }
}

// ── Sort sheet ────────────────────────────────────────────────────────────────

class _SortSheet extends ConsumerWidget {
  final ResultSort current;
  const _SortSheet({required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const options = [
      (ResultSort.reclaimableSizeDesc, Icons.arrow_downward_rounded, 'Largest savings first'),
      (ResultSort.reclaimableSizeAsc,  Icons.arrow_upward_rounded,   'Smallest savings first'),
      (ResultSort.groupCountDesc,      Icons.group_work_outlined,    'Most duplicates first'),
      (ResultSort.confidenceDesc,      Icons.percent_rounded,        'Highest confidence first'),
      (ResultSort.dateNewest,          Icons.schedule_rounded,       'Newest files first'),
      (ResultSort.dateOldest,          Icons.history_rounded,        'Oldest files first'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sort by',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...options.map((o) => RadioListTile<ResultSort>(
                value:      o.$1,
                groupValue: current,
                title: Row(children: [
                  Icon(o.$2, size: 18),
                  const SizedBox(width: 10),
                  Text(o.$3),
                ]),
                onChanged: (v) {
                  if (v != null) {
                    ref.read(resultsFilterProvider.notifier).setSort(v);
                    Navigator.pop(context);
                  }
                },
                contentPadding: EdgeInsets.zero,
              )),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline_rounded, size: 80, color: cs.primary),
        const SizedBox(height: 20),
        Text('No duplicates found',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Your storage looks clean!',
            style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
