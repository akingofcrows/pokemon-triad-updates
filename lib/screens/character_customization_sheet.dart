import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/trainer_appearance.dart';
import '../widgets/trainer_sprite_stack.dart';

class CharacterCustomizationSheet extends StatefulWidget {
  const CharacterCustomizationSheet({super.key, required this.appearance});
  final TrainerAppearance appearance;

  @override
  State<CharacterCustomizationSheet> createState() =>
      _CharacterCustomizationSheetState();
}

class _CharacterCustomizationSheetState
    extends State<CharacterCustomizationSheet> {
  late TrainerAppearance _current;
  Map<String, dynamic>? _partsData;
  String _tab = 'tops'; // tops, bottoms, hats
  // Track selected style id per category, and color index
  String? _selectedHairId;
  String? _selectedTopId;
  String? _selectedBottomId;
  String? _selectedHatId;

  @override
  void initState() {
    super.initState();
    _current = widget.appearance;
    _loadParts();
  }

  Future<void> _loadParts() async {
    final json = await rootBundle.loadString('assets/data/trainer_parts.json');
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (!mounted) return;
    setState(() {
      _partsData = data;
      // Extract current style ids from paths
      final path = _current.topPath ?? '';
      if (path.contains('tops/')) {
        final parts = path.split('/');
        if (parts.length >= 3) {
          final file = parts.last.replaceAll('.png', '');
          final segs = file.split('__');
          _selectedTopId = segs.first;
        }
      }
      final bPath = _current.bottomPath ?? '';
      if (bPath.contains('bottoms/')) {
        final parts = bPath.split('/');
        if (parts.length >= 3) {
          final file = parts.last.replaceAll('.png', '');
          final segs = file.split('__');
          _selectedBottomId = segs.first;
        }
      }
      final hPath = _current.hairPath ?? '';
      if (hPath.contains('hair/')) {
        final parts = hPath.split('/');
        if (parts.length >= 3) {
          final file = parts.last.replaceAll('.png', '');
          final segs = file.split('__');
          _selectedHairId = segs.first;
        }
      }
      final hatPath = _current.hatPath ?? '';
      if (hatPath.contains('hats/')) {
        final parts = hatPath.split('/');
        if (parts.length >= 3) {
          final file = parts.last.replaceAll('.png', '');
          final segs = file.split('__');
          _selectedHatId = segs.first;
        }
      }
    });
  }

  String get _gender => _current.gender ?? 'boy';

  List<Map<String, dynamic>> _items(String category) {
    final genderData = _partsData?[_gender == 'girl' ? 'female' : 'male'];
    if (genderData == null) return [];
    final list = (genderData[category] as List?)?.cast<Map<String, dynamic>>();
    return list ?? [];
  }

  void _pickSkin(String file, String id) {
    setState(() => _current = _current.copyWith(skinTone: file, gender: _gender));
  }

  void _pickHair(String id) {
    setState(() => _selectedHairId = id);
  }

  void _pickHairColor(String colorId, String file) {
    setState(() {
      _selectedHairId = null; // force select first
      _current = _current.copyWith(hairPath: file, gender: _gender);
    });
  }

  void _pickTop(String id) {
    setState(() => _selectedTopId = id);
  }

  void _pickTopColor(String colorId, String file) {
    setState(() {
      _selectedTopId = null;
      _current = _current.copyWith(topPath: file, gender: _gender);
    });
  }

  void _pickBottom(String id) {
    setState(() => _selectedBottomId = id);
  }

  void _pickBottomColor(String colorId, String file) {
    setState(() {
      _selectedBottomId = null;
      _current = _current.copyWith(bottomPath: file, gender: _gender);
    });
  }

  void _pickHat(String id) {
    setState(() => _selectedHatId = id);
  }

  void _pickHatColor(String colorId, String? file) {
    setState(() {
      _selectedHatId = null;
      _current = _current.copyWith(hatPath: file, gender: _gender);
    });
  }

  void _showVariantPicker(String styleId, String label, List<Map<String, dynamic>> colors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9,
            ),
            itemCount: colors.length,
            itemBuilder: (_, i) {
              final c = colors[i];
              final cFile = c['file'] as String?;
              final cId = c['id'] as String;
              final active = switch (_tab) {
                'tops' => _current.topPath == cFile,
                'bottoms' => _current.bottomPath == cFile,
                'hats' => _current.hatPath == cFile || (_current.hatPath == null && cFile == null),
                _ => false,
              };
              return GestureDetector(
                onTap: () {
                  switch (_tab) {
                    case 'tops': _pickTopColor(cId, cFile ?? '');
                    case 'bottoms': _pickBottomColor(cId, cFile ?? '');
                    case 'hats': _pickHatColor(cId, cFile);
                  }
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: active ? const Color(0xFF4FC3F7) : Colors.white.withValues(alpha: 0.1), width: active ? 2 : 1),
                    color: const Color(0xFF2A2A2A),
                  ),
                  child: cFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.asset('assets/$cFile', fit: BoxFit.contain),
                        )
                      : const Center(child: Text('None', style: TextStyle(color: Colors.white38, fontSize: 10))),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    await context.read<PlayerProfileController>().saveCharacter(_current);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Customize', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: _save,
                  child: const Text('Save', style: TextStyle(color: Color(0xFF4FC3F7), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          // Preview
          SizedBox(
            height: 130,
            child: Center(
              child: TrainerSpriteStack(appearance: _current, size: 120),
            ),
          ),
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: ['tops', 'bottoms', 'hats'].map((cat) {
                final active = _tab == cat;
                final label = {'tops': 'Top', 'bottoms': 'Bottom', 'hats': 'Hat'}[cat]!;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tab = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: active ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(label, textAlign: TextAlign.center,
                        style: TextStyle(color: active ? Colors.white : Colors.white54, fontSize: 13)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Content
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    final items = _items(_tab == 'skin' ? 'skinTones' : _tab);
    if (items.isEmpty) return const Center(child: CircularProgressIndicator());

    if (_tab == 'skin') {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1,
        ),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final item = items[i];
          final file = item['file'] as String;
          final active = _current.skinTone == file;
          return GestureDetector(
            onTap: () => _pickSkin(file, item['id'] as String),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: active ? const Color(0xFF4FC3F7) : Colors.white.withValues(alpha: 0.1), width: active ? 2 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset('assets/$file', fit: BoxFit.contain),
              ),
            ),
          );
        },
      );
    }

    // Show all styles — tap directly applies first color
    bool isActive(String? file) {
      if (file == null) return false;
      return switch (_tab) {
        'tops' => _current.topPath == file,
        'bottoms' => _current.bottomPath == file,
        'hats' => _current.hatPath == file || (_current.hatPath == null && file == ''),
        _ => false,
      };
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.9,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        final id = item['id'] as String;
        final colors = (item['colors'] as List).cast<Map<String, dynamic>>();
        final firstColor = colors.first;
        final file = firstColor['file'] as String?;
        final active = isActive(file);
        return GestureDetector(
          onTap: () => _showVariantPicker(id, item['label'] as String? ?? id, colors),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: active ? const Color(0xFF4FC3F7) : Colors.white.withValues(alpha: 0.1), width: active ? 2 : 1),
              color: const Color(0xFF2A2A2A),
            ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (file != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset('assets/$file', width: 80, height: 80, fit: BoxFit.contain),
                    )
                  else
                    const Icon(Icons.block, color: Colors.white24, size: 32),
                  Transform.translate(
                    offset: const Offset(0, -6),
                    child: Text(item['label'] as String? ?? id, style: const TextStyle(color: Colors.white54, fontSize: 10), textAlign: TextAlign.center),
                  ),
                ],
              ),
            ),
          );
        },
      );
  }
}
