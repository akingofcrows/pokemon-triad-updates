import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import 'booster_pack_screen.dart';

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key});

  static const _boosterImages = {
    'Field Trip Booster': 'assets/images/Booster Pack/field.png',
    'Kanto Collection': 'assets/images/Booster Pack/kanto.png',
    'Johto Collection': 'assets/images/Booster Pack/johto.png',
    'Safari Tour': 'assets/images/Booster Pack/safari.png',
    'Golden Swarm': 'assets/images/Booster Pack/gold.png',
    'Urban Life': 'assets/images/Booster Pack/urban.png',
  };

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<PlayerProfileController>().boosterInventory;

    // Group boosters by name with counts
    final counts = <String, int>{};
    for (final name in inventory) {
      counts[name] = (counts[name] ?? 0) + 1;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(title: const Text('Items')),
      body: counts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.backpack, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text(
                    'No items yet.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Visit the shop to buy booster packs!',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.68,
              ),
              itemCount: counts.length,
              itemBuilder: (context, index) {
                final name = counts.keys.elementAt(index);
                final count = counts[name]!;
                final imagePath = _boosterImages[name];

                return Material(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openBooster(context, name),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Booster image
                          Expanded(
                            child: imagePath != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.asset(
                                      imagePath,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => _fallbackIcon(),
                                    ),
                                  )
                                : _fallbackIcon(),
                          ),
                          const SizedBox(height: 6),
                          // Name
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          // Count
                          if (count > 1)
                            Text(
                              '×$count',
                              style: TextStyle(
                                color: Colors.amber.withValues(alpha: 0.8),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          else
                            Text(
                              'Tap to open',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 9,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
    final ctrl = context.read<PlayerProfileController>();
    ctrl.openBoosterFromInventory(name);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BoosterPackScreen()),
    );
  }
}
