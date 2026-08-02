/// One step in an evolution line — the species evolved into and the level
/// that step requires.
class EvolutionStep {
  const EvolutionStep({required this.cardId, required this.level});

  final String cardId;
  final int level;
}

/// The full evolution lineage around a species — every ancestor (oldest
/// first) and every descendant along a single unbranching path, stopping at
/// the first branch (e.g. Eevee) and returning its options separately since
/// a branching tree doesn't fit a linear chain display.
class EvolutionLine {
  const EvolutionLine({
    required this.ancestors,
    required this.descendants,
    required this.branchOptions,
  });

  final List<EvolutionStep> ancestors;
  final List<EvolutionStep> descendants;
  final List<EvolutionStep> branchOptions;

  bool get isStandalone =>
      ancestors.isEmpty && descendants.isEmpty && branchOptions.isEmpty;
}
