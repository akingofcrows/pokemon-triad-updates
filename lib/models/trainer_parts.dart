/// One selectable option within a category — e.g. a specific hair color, or
/// a skin tone. [file] is an asset path relative to `assets/` (e.g.
/// `trainers/male/hair/hair_1__black.png`), or null for the synthetic "no
/// hat" option.
class TrainerPartOption {
  const TrainerPartOption({required this.id, required this.label, this.file});

  final String id;
  final String label;
  final String? file;

  factory TrainerPartOption.fromJson(Map<String, dynamic> json) {
    return TrainerPartOption(
      id: json['id'] as String,
      label: json['label'] as String,
      file: json['file'] as String?,
    );
  }
}

/// A style category (e.g. "Hoodie", "Hair 1") and its color variants.
class TrainerPartCategory {
  const TrainerPartCategory({required this.id, required this.label, required this.colors});

  final String id;
  final String label;
  final List<TrainerPartOption> colors;

  factory TrainerPartCategory.fromJson(Map<String, dynamic> json) {
    return TrainerPartCategory(
      id: json['id'] as String,
      label: json['label'] as String,
      colors: (json['colors'] as List<dynamic>)
          .map((c) => TrainerPartOption.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// All selectable trainer-appearance parts for one gender (male or female
/// asset set — the DB/UI gender values are 'boy'/'girl', see
/// TrainerPartsRepository.forGender).
class TrainerGenderParts {
  const TrainerGenderParts({
    required this.skinTones,
    required this.hair,
    required this.tops,
    required this.bottoms,
    required this.hats,
  });

  final List<TrainerPartOption> skinTones;
  final List<TrainerPartCategory> hair;
  final List<TrainerPartCategory> tops;
  final List<TrainerPartCategory> bottoms;
  final List<TrainerPartCategory> hats;

  factory TrainerGenderParts.fromJson(Map<String, dynamic> json) {
    List<TrainerPartCategory> cats(String key) => (json[key] as List<dynamic>)
        .map((c) => TrainerPartCategory.fromJson(c as Map<String, dynamic>))
        .toList();
    return TrainerGenderParts(
      skinTones: (json['skinTones'] as List<dynamic>)
          .map((c) => TrainerPartOption.fromJson(c as Map<String, dynamic>))
          .toList(),
      hair: cats('hair'),
      tops: cats('tops'),
      bottoms: cats('bottoms'),
      hats: cats('hats'),
    );
  }
}
