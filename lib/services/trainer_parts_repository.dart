import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/trainer_parts.dart';

/// Loads and caches the static trainer-appearance option catalog from
/// assets/data/trainer_parts.json — the converted output of TTMMO's
/// `trainers/{male,female}/{base,hair,tops,bottoms,hats}` sprite folders.
class TrainerPartsRepository {
  TrainerPartsRepository._();
  static final TrainerPartsRepository instance = TrainerPartsRepository._();

  bool _loaded = false;
  bool get isLoaded => _loaded;

  late final TrainerGenderParts _male;
  late final TrainerGenderParts _female;

  Future<void> load() async {
    if (_loaded) return;
    final json = jsonDecode(await rootBundle.loadString('assets/data/trainer_parts.json')) as Map<String, dynamic>;
    _male = TrainerGenderParts.fromJson(json['male'] as Map<String, dynamic>);
    _female = TrainerGenderParts.fromJson(json['female'] as Map<String, dynamic>);
    _loaded = true;
  }

  /// [gender] is 'boy' or 'girl' (the DB/UI value), mapped to the
  /// corresponding male/female asset set.
  TrainerGenderParts forGender(String gender) => gender == 'boy' ? _male : _female;
}
