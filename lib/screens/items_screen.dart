import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import 'booster_pack_screen.dart';

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key});

  static const _boosterImages = {
    'field_trip': 'assets/images/Booster Pack/field.png',
    'Field Trip Booster': 'assets/images/Booster Pack/field.png',
    'Kanto Collection': 'assets/images/Booster Pack/kanto.png',
    'Johto Collection': 'assets/images/Booster Pack/johto.png',
    'safari': 'assets/images/Booster Pack/safari.png',
    'Safari Tour': 'assets/images/Booster Pack/safari.png',
    'Safari Tour Booster': 'assets/images/Booster Pack/safari.png',
    'Golden Swarm': 'assets/images/Booster Pack/gold.png',
    'urban': 'assets/images/Booster Pack/urban.png',
    'Urban Life': 'assets/images/Booster Pack/urban.png',
    'Urban Life Booster': 'assets/images/Booster Pack/urban.png',
  };

  static const _boosterNames = {
    'field_trip': 'Field Trip Booster',
    'safari': 'Safari Tour Booster',
    'Safari Tour': 'Safari Tour Booster',
    'urban': 'Urban Life Booster',
    'Urban Life': 'Urban Life Booster',
  };

  @override
  Widget build(BuildContext context) {
    final profileCtrl = context.watch<PlayerProfileController>();
    final inventory = profileCtrl.boosterInventory;
    final money = profileCtrl.profile.money;

    final counts = <String, int>{};
    for (final name in inventory) {
      counts[name] = (counts[name] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: const Text('Items'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on, color: Color(0xFFC9A44C), size: 20),
                const SizedBox(width: 4),
                Text('₽ $money', style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: counts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.backpack, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text('No items yet.', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Visit the shop to buy booster packs!', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader(title: 'Booster Packs'),
                const SizedBox(height: 12),
                ...counts.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ItemTile(
                    name: e.key,
                    count: e.value,
                    onTap: () => _openBooster(context, e.key),
                    onLongPress: e.value > 1
                        ? () => _showOpenAllDialog(context, e.key, e.value)
                        : null,
                  ),
                )),
              ],
            ),
    );
  }

  void _showOpenAllDialog(BuildContext context, String name, int count) {
    final normalized = _normalizeBoosterId(name);
    final label = _boosterNames[normalized] ?? _boosterNames[name] ?? name;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('$count packs available', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: Colors.amber),
                title: Text('Open All ($count)', style: const TextStyle(color: Colors.white)),
                subtitle: Text('Open all $count packs one after another', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAllBoosters(context, name, normalized, count);
                },
              ),
              ListTile(
                leading: const Icon(Icons.touch_app, color: Colors.white70),
                title: const Text('Open One', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBooster(context, name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAllBoosters(BuildContext context, String rawName, String normalizedName, int count) {
    // Don't consume from inventory here — BoosterPackScreen will consume one
    // when the player taps "Add to Collection".
    _pushBoosterWithChain(context, rawName, normalizedName, count);
  }

  void _pushBoosterWithChain(BuildContext context, String rawName, String boosterName, int remaining) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BoosterPackScreen(
          boosterName: boosterName,
          inventoryName: rawName,
          onDone: () {
            if (remaining > 1) {
              _pushBoosterWithChain(context, rawName, boosterName, remaining - 1);
            }
          },
        ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Center(
        child: Text(
          '?',
          style: TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _openBooster(BuildContext context, String name) {
    final normalized = _normalizeBoosterId(name);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BoosterPackScreen(
        boosterName: normalized,
        inventoryName: name,
      )),
    );
  }

  static String _normalizeBoosterId(String name) {
    final n = name.toLowerCase();
    if (n.contains('safari')) return 'safari';
    if (n.contains('urban')) return 'urban';
    if (n.contains('field')) return 'field_trip';
    return name;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 16, color: Colors.amber),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.name, required this.count, required this.onTap, this.onLongPress});
  final String name;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const _images = {
    'field_trip': 'assets/images/Booster Pack/field.png',
    'Field Trip Booster': 'assets/images/Booster Pack/field.png',
    'safari': 'assets/images/Booster Pack/safari.png',
    'Safari Tour': 'assets/images/Booster Pack/safari.png',
    'Safari Tour Booster': 'assets/images/Booster Pack/safari.png',
    'urban': 'assets/images/Booster Pack/urban.png',
    'Urban Life': 'assets/images/Booster Pack/urban.png',
    'Urban Life Booster': 'assets/images/Booster Pack/urban.png',
  };
  static const _names = {
    'field_trip': 'Field Trip Booster',
    'safari': 'Safari Tour Booster',
    'Safari Tour': 'Safari Tour Booster',
    'urban': 'Urban Life Booster',
    'Urban Life': 'Urban Life Booster',
  };

  @override
  Widget build(BuildContext context) {
    final img = _images[name];
    final label = _names[name] ?? name;
    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (img != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(img, width: 56, height: 78, fit: BoxFit.cover),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(count == 1 ? 'Tap to open' : '×$count packs',
                      style: TextStyle(color: count > 1 ? Colors.amber.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}
