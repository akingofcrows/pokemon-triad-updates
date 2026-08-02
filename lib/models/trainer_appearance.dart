/// A trainer's chosen appearance + name — mirrors the columns TTMMO's
/// Discord `/intro` flow writes to `players` (trainer_name, gender,
/// skin_tone, hair_path, top_path, bottom_path, hat_path). Asset paths are
/// relative to `assets/` (e.g. `trainers/male/hair/hair_1__black.png`).
class TrainerAppearance {
  const TrainerAppearance({
    required this.gender,
    required this.skinTone,
    required this.hairPath,
    required this.topPath,
    required this.bottomPath,
    this.hatPath,
    this.trainerName,
  });

  /// 'boy' or 'girl' — matches TTMMO's `players.gender` values (not the
  /// 'male'/'female' asset-folder names).
  final String gender;
  final String skinTone;
  final String hairPath;
  final String topPath;
  final String bottomPath;
  final String? hatPath;
  final String? trainerName;

  String get assetGenderFolder => gender == 'boy' ? 'male' : 'female';

  TrainerAppearance copyWith({
    String? gender,
    String? skinTone,
    String? hairPath,
    String? topPath,
    String? bottomPath,
    Object? hatPath = _unset,
    String? trainerName,
  }) {
    return TrainerAppearance(
      gender: gender ?? this.gender,
      skinTone: skinTone ?? this.skinTone,
      hairPath: hairPath ?? this.hairPath,
      topPath: topPath ?? this.topPath,
      bottomPath: bottomPath ?? this.bottomPath,
      hatPath: identical(hatPath, _unset) ? this.hatPath : hatPath as String?,
      trainerName: trainerName ?? this.trainerName,
    );
  }

  Map<String, dynamic> toJson() => {
    'trainerName': trainerName,
    'gender': gender,
    'skinTone': skinTone,
    'hairPath': hairPath,
    'topPath': topPath,
    'bottomPath': bottomPath,
    'hatPath': hatPath,
  };

  static const _unset = Object();
}
