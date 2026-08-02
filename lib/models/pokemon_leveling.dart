/// Pokémon XP leveling based on the Triad GDD custom curve.
///
/// Growth rate groups scale the base curve:
///   Fast:        ×0.8 — bugs, birds, rodents
///   Medium-Fast: ×1.0 — most Pokémon (default)
///   Medium-Slow: ×1.2 — rare / pseudo-legendaries
///   Slow:        ×1.5 — legendaries, late-stage evos

enum XpGrowthRate { fast, mediumFast, mediumSlow, slow }

/// Cumulative XP thresholds for Medium-Fast (base curve).
const _baseCurve = [0, 40, 95, 170, 270, 405, 580, 805, 1090, 1445, 1880, 2405, 3030, 3770, 4640, 5655];

/// Multiplier per group: higher = more XP needed = slower.
const _rateMultipliers = {
  XpGrowthRate.fast: 0.8,
  XpGrowthRate.mediumFast: 1.0,
  XpGrowthRate.mediumSlow: 1.2,
  XpGrowthRate.slow: 1.5,
};

/// Cumulative XP required to reach [level] for the given growth rate.
int xpToReachLevel(int level, {XpGrowthRate rate = XpGrowthRate.mediumFast}) {
  if (level <= 1) return 0;
  final mult = _rateMultipliers[rate] ?? 1.0;
  if (level < _baseCurve.length) return (_baseCurve[level - 1] * mult).round();
  // Extrapolate beyond defined curve: last step + 120/level × multiplier
  final lastExtrapolated = 5655;
  var total = lastExtrapolated;
  for (var l = 16; l < level; l++) {
    total += 1015 + (l - 15) * 120;
  }
  return (total * mult).round();
}

/// XP needed to advance from [level] to [level]+1.
int xpForNextLevel(int level, {XpGrowthRate rate = XpGrowthRate.mediumFast}) {
  return xpToReachLevel(level + 1, rate: rate) - xpToReachLevel(level, rate: rate);
}

/// Returns (newLevel, leftoverXp) from cumulative [totalXp].
({int level, int leftover}) levelFromXp(int totalXp, {XpGrowthRate rate = XpGrowthRate.mediumFast}) {
  var cumulative = 0;
  for (var lv = 1; lv < 100; lv++) {
    final needed = xpForNextLevel(lv, rate: rate);
    cumulative += needed;
    if (totalXp < cumulative) return (level: lv, leftover: totalXp - (cumulative - needed));
  }
  return (level: 99, leftover: totalXp);
}

/// Species → growth rate. Defaults to mediumFast for unmapped species.
XpGrowthRate growthRateForSpecies(String speciesId) {
  return _speciesGrowth[speciesId] ?? XpGrowthRate.mediumFast;
}

// ── Species → growth rate mapping ───────────────────────────────────────

const _speciesGrowth = <String, XpGrowthRate>{
  // --- Fast: common bugs, birds, rodents ---
  'caterpie': XpGrowthRate.fast,
  'weedle': XpGrowthRate.fast,
  'pidgey': XpGrowthRate.fast,
  'rattata': XpGrowthRate.fast,
  'spearow': XpGrowthRate.fast,
  'sentret': XpGrowthRate.fast,
  'hoothoot': XpGrowthRate.fast,
  'zigzagoon': XpGrowthRate.fast,
  'ledyba': XpGrowthRate.fast,
  'spinarak': XpGrowthRate.fast,
  'wurmple': XpGrowthRate.fast,
  'poochyena': XpGrowthRate.fast,
  'zubat': XpGrowthRate.fast,
  'geodude': XpGrowthRate.fast,
  'magnemite': XpGrowthRate.fast,

  // --- Medium-Fast: most starters and common Pokémon ---
  'bulbasaur': XpGrowthRate.mediumFast,
  'charmander': XpGrowthRate.mediumFast,
  'squirtle': XpGrowthRate.mediumFast,
  'chikorita': XpGrowthRate.mediumFast,
  'cyndaquil': XpGrowthRate.mediumFast,
  'totodile': XpGrowthRate.mediumFast,
  'treecko': XpGrowthRate.mediumFast,
  'torchic': XpGrowthRate.mediumFast,
  'mudkip': XpGrowthRate.mediumFast,
  'pikachu': XpGrowthRate.mediumFast,
  'sandshrew': XpGrowthRate.mediumFast,
  'nidoran-f': XpGrowthRate.mediumFast,
  'nidoran-m': XpGrowthRate.mediumFast,
  'vulpix': XpGrowthRate.mediumFast,
  'oddish': XpGrowthRate.mediumFast,
  'paras': XpGrowthRate.mediumFast,
  'diglett': XpGrowthRate.mediumFast,
  'meowth': XpGrowthRate.mediumFast,
  'psyduck': XpGrowthRate.mediumFast,
  'mankey': XpGrowthRate.mediumFast,
  'growlithe': XpGrowthRate.mediumFast,
  'poliwag': XpGrowthRate.mediumFast,
  'abra': XpGrowthRate.mediumSlow,       // pseudo-legendary status
  'machop': XpGrowthRate.mediumSlow,
  'bellsprout': XpGrowthRate.mediumFast,
  'tentacool': XpGrowthRate.mediumFast,
  'ponyta': XpGrowthRate.mediumFast,
  'slowpoke': XpGrowthRate.mediumFast,
  'doduo': XpGrowthRate.mediumFast,
  'seel': XpGrowthRate.mediumFast,
  'grimer': XpGrowthRate.mediumFast,
  'shellder': XpGrowthRate.mediumFast,
  'gastly': XpGrowthRate.mediumSlow,
  'onix': XpGrowthRate.mediumFast,
  'drowzee': XpGrowthRate.mediumFast,
  'krabby': XpGrowthRate.mediumFast,
  'voltorb': XpGrowthRate.mediumFast,
  'exeggcute': XpGrowthRate.mediumFast,
  'cubone': XpGrowthRate.mediumFast,
  'koffing': XpGrowthRate.mediumFast,
  'rhyhorn': XpGrowthRate.mediumSlow,
  'chansey': XpGrowthRate.fast,
  'tangela': XpGrowthRate.mediumFast,
  'kangaskhan': XpGrowthRate.mediumFast,
  'horsea': XpGrowthRate.mediumFast,
  'goldeen': XpGrowthRate.mediumFast,
  'staryu': XpGrowthRate.mediumFast,
  'scyther': XpGrowthRate.mediumFast,
  'pinsir': XpGrowthRate.mediumFast,
  'tauros': XpGrowthRate.mediumFast,
  'magikarp': XpGrowthRate.slow,         // joke: slow to raise
  'eevee': XpGrowthRate.mediumFast,
  'porygon': XpGrowthRate.mediumFast,
  'omanyte': XpGrowthRate.mediumFast,
  'kabuto': XpGrowthRate.mediumFast,
  'aerodactyl': XpGrowthRate.slow,
  'snorlax': XpGrowthRate.slow,
  'dratini': XpGrowthRate.slow,

  // --- Medium-Slow: rare / legendary ---
  'articuno': XpGrowthRate.slow,
  'zapdos': XpGrowthRate.slow,
  'moltres': XpGrowthRate.slow,
  'mewtwo': XpGrowthRate.slow,
  'mew': XpGrowthRate.mediumSlow,
  'celebi': XpGrowthRate.mediumSlow,
  'jirachi': XpGrowthRate.mediumSlow,
  'deoxys': XpGrowthRate.mediumSlow,

  // --- Slow: pseudo-legendaries ---
  'dragonite': XpGrowthRate.slow,
  'tyranitar': XpGrowthRate.slow,
  'salamence': XpGrowthRate.slow,
  'metagross': XpGrowthRate.slow,
  'garchomp': XpGrowthRate.slow,
  'hydreigon': XpGrowthRate.slow,
  'goodra': XpGrowthRate.slow,
};
