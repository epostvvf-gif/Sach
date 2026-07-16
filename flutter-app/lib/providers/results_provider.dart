import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/duplicate_group.dart';
import '../models/file_item.dart';
import 'scan_provider.dart';

enum ResultFilter { all, exactOnly, similarOnly, imagesOnly, documentsOnly, videosOnly }
enum ResultSort   { reclaimableSizeDesc, reclaimableSizeAsc, groupCountDesc, confidenceDesc, dateNewest, dateOldest }

// ── Filter state ──────────────────────────────────────────────────────────────

class ResultsFilter {
  final ResultFilter filter;
  final ResultSort   sort;
  final String       searchQuery;
  final int          minReclaimBytes;

  const ResultsFilter({
    this.filter          = ResultFilter.all,
    this.sort            = ResultSort.reclaimableSizeDesc,
    this.searchQuery     = '',
    this.minReclaimBytes = 0,
  });

  ResultsFilter copyWith({
    ResultFilter? filter,
    ResultSort?   sort,
    String?       searchQuery,
    int?          minReclaimBytes,
  }) =>
      ResultsFilter(
        filter:          filter          ?? this.filter,
        sort:            sort            ?? this.sort,
        searchQuery:     searchQuery     ?? this.searchQuery,
        minReclaimBytes: minReclaimBytes ?? this.minReclaimBytes,
      );
}

class ResultsFilterNotifier extends Notifier<ResultsFilter> {
  @override
  ResultsFilter build() => const ResultsFilter();

  void setFilter(ResultFilter f) => state = state.copyWith(filter: f);
  void setSort(ResultSort s)     => state = state.copyWith(sort: s);
  void setSearch(String q)       => state = state.copyWith(searchQuery: q);
  void setMinReclaim(int b)      => state = state.copyWith(minReclaimBytes: b);
  void reset()                   => state = const ResultsFilter();
}

final resultsFilterProvider =
    NotifierProvider<ResultsFilterNotifier, ResultsFilter>(
  ResultsFilterNotifier.new,
);

// ── Derived: filtered + sorted groups ────────────────────────────────────────

final filteredGroupsProvider = Provider<List<DuplicateGroup>>((ref) {
  final groups = ref.watch(scanProvider).result?.groups ?? [];
  final opts   = ref.watch(resultsFilterProvider);

  var result = groups.toList();

  // Filter by type
  result = result.where((g) {
    switch (opts.filter) {
      case ResultFilter.all:          return true;
      case ResultFilter.exactOnly:    return g.matchType == MatchType.exactMd5;
      case ResultFilter.similarOnly:  return g.matchType != MatchType.exactMd5;
      case ResultFilter.imagesOnly:   return g.original.type == FileType.image;
      case ResultFilter.documentsOnly:return g.original.type == FileType.document;
      case ResultFilter.videosOnly:   return g.original.type == FileType.video;
    }
  }).toList();

  // Search
  if (opts.searchQuery.isNotEmpty) {
    final q = opts.searchQuery.toLowerCase();
    result = result
        .where((g) => g.allFiles.any((f) => f.name.toLowerCase().contains(q)))
        .toList();
  }

  // Min reclaim
  if (opts.minReclaimBytes > 0) {
    result = result.where((g) => g.reclaimableBytes >= opts.minReclaimBytes).toList();
  }

  // Sort
  switch (opts.sort) {
    case ResultSort.reclaimableSizeDesc:
      result.sort((a, b) => b.reclaimableBytes.compareTo(a.reclaimableBytes));
    case ResultSort.reclaimableSizeAsc:
      result.sort((a, b) => a.reclaimableBytes.compareTo(b.reclaimableBytes));
    case ResultSort.groupCountDesc:
      result.sort((a, b) => b.count.compareTo(a.count));
    case ResultSort.confidenceDesc:
      result.sort((a, b) => b.confidence.compareTo(a.confidence));
    case ResultSort.dateNewest:
      result.sort((a, b) => b.original.modifiedAt.compareTo(a.original.modifiedAt));
    case ResultSort.dateOldest:
      result.sort((a, b) => a.original.modifiedAt.compareTo(b.original.modifiedAt));
  }

  return result;
});

// ── Derived: summary stats ────────────────────────────────────────────────────

class ResultsStats {
  final int totalGroups;
  final int totalDuplicateFiles;
  final int totalReclaimableBytes;
  final int exactGroups;
  final int semanticGroups;

  const ResultsStats({
    this.totalGroups           = 0,
    this.totalDuplicateFiles   = 0,
    this.totalReclaimableBytes = 0,
    this.exactGroups           = 0,
    this.semanticGroups        = 0,
  });
}

final resultStatsProvider = Provider<ResultsStats>((ref) {
  final groups = ref.watch(filteredGroupsProvider);
  if (groups.isEmpty) return const ResultsStats();
  return ResultsStats(
    totalGroups:           groups.length,
    totalDuplicateFiles:   groups.fold(0, (s, g) => s + g.duplicates.length),
    totalReclaimableBytes: groups.fold(0, (s, g) => s + g.reclaimableBytes),
    exactGroups:    groups.where((g) => g.matchType == MatchType.exactMd5).length,
    semanticGroups: groups.where((g) => g.matchType != MatchType.exactMd5).length,
  );
});

// ── Selection for bulk actions ────────────────────────────────────────────────

class SelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    final next = Set<String>.from(state);
    if (next.contains(id)) next.remove(id); else next.add(id);
    state = next;
  }

  void selectAll(List<DuplicateGroup> groups) {
    state = groups.map((g) => g.original.md5 ?? g.original.path).toSet();
  }

  void clearAll() => state = {};

  bool isSelected(DuplicateGroup g) =>
      state.contains(g.original.md5 ?? g.original.path);
}

final selectionProvider = NotifierProvider<SelectionNotifier, Set<String>>(
  SelectionNotifier.new,
);
