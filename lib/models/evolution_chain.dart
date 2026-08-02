/// One level-based evolution step (`assets/data/evolutions.json`, converted
/// from TTMMO's `data/evolutions.json` with item-gated evolutions dropped —
/// this app's growth system evolves purely by level).
class EvolutionChain {
  const EvolutionChain({required this.from, required this.to, required this.level});

  final String from;
  final String to;
  final int level;

  factory EvolutionChain.fromJson(Map<String, dynamic> json) {
    return EvolutionChain(
      from: json['from'] as String,
      to: json['to'] as String,
      level: json['level'] as int,
    );
  }
}
