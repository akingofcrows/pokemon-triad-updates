import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/card_growth.dart';
import '../models/condition.dart';
import '../services/card_repository.dart';
import '../services/item_repository.dart';
import '../widgets/condition_badge.dart';
import '../widgets/item_card.dart';
import '../widgets/toast.dart';
import '../widgets/triad_card_view.dart';
import 'booster_pack_screen.dart';

const _potionItemIds = {'potion', 'super_potion', 'hyper_potion', 'max_potion', 'full_restore', 'antidote', 'burn_heal', 'ice_heal', 'awakening', 'paralyze_heal', 'full_heal'};
const _ballItemIds = {'pokeball', 'great_ball', 'ultra_ball', 'safari_ball', 'net_ball', 'premiere_ball', 'love_ball', 'master_ball'};
const _keyItemIds = {'oaks_parcel', 'old_rod', 'good_rod', 'super_rod', 'red_apricorn', 'yellow_apricorn', 'pink_apricorn', 'white_apricorn', 'black_apricorn'};

enum _SortMode { nameAsc, nameDesc, qtyDesc, qtyAsc }

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});
  @override State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  _SortMode _sort = _SortMode.qtyDesc;

  List<MapEntry<String, int>> _sortItems(List<MapEntry<String, int>> items) {
    final sorted = [...items];
    switch (_sort) {
      case _SortMode.nameAsc: sorted.sort((a, b) => a.key.compareTo(b.key));
      case _SortMode.nameDesc: sorted.sort((a, b) => b.key.compareTo(a.key));
      case _SortMode.qtyDesc: sorted.sort((a, b) => b.value.compareTo(a.value));
      case _SortMode.qtyAsc: sorted.sort((a, b) => a.value.compareTo(b.value));
    }
    return sorted;
  }

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
    'kanto': 'Kanto Collection',
    'Kanto Collection': 'Kanto Collection',
  };

  @override
  Widget build(BuildContext context) {
    final profileCtrl = context.watch<PlayerProfileController>();
    final inventory = profileCtrl.boosterInventory;
    final consumables = profileCtrl.consumableInventory;
    final money = profileCtrl.profile.money;

    final boosterCounts = <String, int>{};
    for (final name in inventory) {
      if (_ballItemIds.contains(name) || _potionItemIds.contains(name) || _keyItemIds.contains(name)) continue;
      boosterCounts[name] = (boosterCounts[name] ?? 0) + 1;
    }

    final balls = consumables.entries.where((e) => _ballItemIds.contains(e.key) && e.value > 0).toList();
    final potions = consumables.entries.where((e) => _potionItemIds.contains(e.key) && e.value > 0).toList();
    final keyItems = consumables.entries.where((e) => _keyItemIds.contains(e.key) && e.value > 0).toList();
    final boosterEntries = boosterCounts.entries.toList();

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1C20),
        appBar: AppBar(
          backgroundColor: const Color(0xFF282A30),
          elevation: 0,
          title: const Text('Items', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          actions: [
            PopupMenuButton<_SortMode>(
              icon: const Icon(Icons.sort, color: Colors.white54, size: 20),
              color: const Color(0xFF282A30),
              onSelected: (m) => setState(() => _sort = m),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _SortMode.qtyDesc, child: Text('Quantity ↓', style: TextStyle(color: Colors.white))),
                const PopupMenuItem(value: _SortMode.qtyAsc, child: Text('Quantity ↑', style: TextStyle(color: Colors.white))),
                const PopupMenuItem(value: _SortMode.nameAsc, child: Text('Name A-Z', style: TextStyle(color: Colors.white))),
                const PopupMenuItem(value: _SortMode.nameDesc, child: Text('Name Z-A', style: TextStyle(color: Colors.white))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('₽ $money', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: Container(
              color: const Color(0xFF282A30),
              child: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Color(0xFF666666),
                indicatorColor: Color(0xFF4CAF50),
                indicatorWeight: 3,
                labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: [Tab(text: 'Balls'), Tab(text: 'Boosters'), Tab(text: 'Battle'), Tab(text: 'Explore'), Tab(text: 'Key Items')],
              ),
            ),
          ),
        ),
        body: TabBarView(children: [
          _buildGrid(context, _sortItems(balls)),
          _buildBoosterGrid(context, _sortItems(boosterEntries)),
          _buildBattleGrid(context, _sortItems(potions)),
          _buildExploreGrid(context),
          _buildGrid(context, _sortItems(keyItems)),
        ]),
      ),
    );
  }

  void _showItemDetail(BuildContext context, String itemId, int count) {
    final item = ItemRepository().itemById(itemId);
    final name = item?.name ?? itemId;
    final desc = item?.description ?? '';
    final image = item?.imageAsset ?? 'assets/images/icons/items/item267.png';
    final isBattle = _potionItemIds.contains(itemId);
    _showItemModal(context, children: [
      Image.asset(image, height: 56, width: 56),
      const SizedBox(height: 10),
      Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
      if (desc.isNotEmpty) ...[const SizedBox(height: 6), Text(desc, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, decoration: TextDecoration.none))],
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFC9A44C).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)), child: Text('Owned: $count', style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 12, fontWeight: FontWeight.w600, decoration: TextDecoration.none))),
      if (isBattle) ...[const SizedBox(height: 12), _glassyButton(() { Navigator.pop(context); _usePotionFlow(context, itemId); }, 'Use', color: const Color(0xFF4CAF50))],
    ]);
  }

  void _showBoosterDetail(BuildContext context, String name, int count) {
    final normalized = _normalizeBoosterId(name);
    final label = _boosterNames[normalized] ?? _boosterNames[name] ?? name;
    final image = _boosterImages[normalized] ?? _boosterImages[name] ?? 'assets/images/Booster Pack/field.png';
    _showItemModal(context, children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(image, height: 64, fit: BoxFit.cover)),
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFC9A44C).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)), child: Text('Owned: $count', style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 12, fontWeight: FontWeight.w600, decoration: TextDecoration.none))),
      const SizedBox(height: 12),
      _glassyButton(() { Navigator.pop(context); _openBooster(context, name); }, 'Open', color: const Color(0xFF4CAF50)),
      if (count > 1) ...[const SizedBox(height: 8), _glassyButton(() { Navigator.pop(context); _openAllBoosters(context, name, normalized, count); }, 'Open All ($count)', color: const Color(0xFFFFCA28))],
    ]);
  }

  static const int _maxSlots = 24;

  /// Shared modal shell — dark glassy, uniform size, 1px border.
  void _showItemModal(BuildContext context, {required List<Widget> children}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xEE1F2027),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  /// Dark glassy button matching ParchmentDialog style.
  Widget _glassyButton(VoidCallback onTap, String label, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(
          fontFamily: 'PowerGreen',
          color: color ?? Colors.white,
          fontSize: 13, fontWeight: FontWeight.w700,
          decoration: TextDecoration.none,
        )),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<MapEntry<String, int>> items) {
    return _buildSlottedGrid(context, items.map((e) => ItemCard(
      imageAsset: _img(e.key), count: e.value, size: 90,
      onTap: () => _showItemDetail(context, e.key, e.value),
    )).toList());
  }

  Widget _buildBoosterGrid(BuildContext context, List<MapEntry<String, int>> items) {
    final cards = items.map((e) => _BoosterCard(
      name: e.key, count: e.value,
      onTap: () => _showBoosterDetail(context, e.key, e.value),
      onLongPress: e.value > 1 ? () => _showOpenAllDialog(context, e.key, e.value) : null,
    )).toList();
    return _buildSlottedGrid(context, cards);
  }

  Widget _buildBattleGrid(BuildContext context, List<MapEntry<String, int>> items) {
    final cards = items.map((e) => ItemCard(
      imageAsset: _img(e.key), count: e.value, size: 90,
      onTap: () => _showItemDetail(context, e.key, e.value),
    )).toList();
    return _buildSlottedGrid(context, cards);
  }

  Widget _buildExploreGrid(BuildContext context) {
    return _buildSlottedGrid(context, []);
  }

  Widget _buildSlottedGrid(BuildContext context, List<Widget> cards, {Widget Function()? emptyBuilder}) {
    final total = cards.length >= _maxSlots ? cards.length : _maxSlots;
    final tiles = <Widget>[...cards];
    for (var i = cards.length; i < total; i++) {
      tiles.add(emptyBuilder != null ? emptyBuilder() : _emptyItemSlot());
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.9),
      itemCount: tiles.length,
      itemBuilder: (_, i) => tiles[i],
    );
  }

  Widget _emptyItemSlot() {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF2A2B32).withValues(alpha: 0.4), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withValues(alpha: 0.04))),
    );
  }

  void _showOpenAllDialog(BuildContext context, String name, int count) {
    final normalized = _normalizeBoosterId(name);
    final label = _boosterNames[normalized] ?? _boosterNames[name] ?? name;
    _showItemModal(context, children: [
      const Icon(Icons.auto_awesome, color: Colors.amber, size: 36),
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
      const SizedBox(height: 4),
      Text('$count packs available', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, decoration: TextDecoration.none)),
      const SizedBox(height: 16),
      _glassyButton(() { Navigator.pop(context); _openAllBoosters(context, name, normalized, count); }, 'Open All ($count)', color: const Color(0xFFFFCA28)),
      const SizedBox(height: 8),
      _glassyButton(() { Navigator.pop(context); _openBooster(context, name); }, 'Open One', color: const Color(0xFF4CAF50)),
    ]);
  }

  void _openAllBoosters(BuildContext context, String rawName, String normalizedName, int count) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BoosterPackScreen(
          boosterName: normalizedName,
          inventoryName: rawName,
          packCount: count,
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

  String _img(String itemId) => ItemRepository().itemById(itemId)?.imageAsset ?? 'assets/images/icons/items/item267.png';

  /// Opens a card picker so the player can spend one [itemId] potion on a
  /// specific owned card instance (GDD §16).
  void _usePotionFlow(BuildContext context, String itemId) {
    final item = ItemRepository().itemById(itemId);
    final controller = context.read<PlayerProfileController>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xEE1F2027),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PotionCardPicker(
        itemId: itemId,
        itemName: item?.name ?? itemId,
        restoreAmount: item?.restoreAmount ?? 0,
        controller: controller,
      ),
    );
  }

  static String _normalizeBoosterId(String name) {
    final n = name.toLowerCase();
    if (n.contains('safari')) return 'safari';
    if (n.contains('urban')) return 'urban';
    if (n.contains('kanto')) return 'kanto';
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

class _BoosterCard extends StatelessWidget {
  const _BoosterCard({required this.name, required this.count, this.onTap, this.onLongPress});
  final String name;
  final int count;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  String get _image {
    switch (name) {
      case 'field_trip': case 'Field Trip Booster': return 'assets/images/Booster Pack/field.png';
      case 'safari': case 'Safari Tour Booster': case 'Safari Tour': return 'assets/images/Booster Pack/safari.png';
      case 'urban': case 'Urban Life Booster': case 'Urban Life': return 'assets/images/Booster Pack/urban.png';
      case 'kanto': case 'Kanto Collection': return 'assets/images/Booster Pack/kanto.png';
      default: return 'assets/images/Booster Pack/field.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(_image, fit: BoxFit.cover),
          ),
          Positioned(
              bottom: 4, right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Text('×$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet card picker for spending a potion on one owned card
/// instance (GDD §16).
class _PotionCardPicker extends StatefulWidget {
  const _PotionCardPicker({
    required this.itemId,
    required this.itemName,
    required this.restoreAmount,
    required this.controller,
  });

  final String itemId;
  final String itemName;
  final int restoreAmount;
  final PlayerProfileController controller;

  @override
  State<_PotionCardPicker> createState() => _PotionCardPickerState();
}

class _PotionCardPickerState extends State<_PotionCardPicker> {
  int? _applyingInstanceId;

  Future<void> _use(CardGrowth inst) async {
    if (inst.instanceId == null || _applyingInstanceId != null) return;
    setState(() => _applyingInstanceId = inst.instanceId);
    try {
      await widget.controller.usePotionOnCard(widget.itemId, inst.instanceId!);
      if (!mounted) return;
      final card = CardRepository.instance.cardById(inst.cardId);
      final name = card?.name ?? 'Card';
      // Read fresh condition after healing
      final healed = widget.controller.cardGrowthByInstance[inst.instanceId];
      final newCond = healed?.condition ?? inst.condition;
      final oldCond = inst.condition;
      Navigator.pop(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Toast.show(context, text: '$name restored to {}/$kMaxCondition!', imagePath: card?.image, counterFrom: oldCond, counterTo: newCond);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _applyingInstanceId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reach the server — try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final instances = [...widget.controller.allCardInstances]
      ..sort((a, b) => a.condition.compareTo(b.condition));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text('Use ${widget.itemName}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
            const SizedBox(height: 4),
            Text(
              widget.restoreAmount >= kMaxCondition
                  ? 'Restores a card to Mint Condition'
                  : 'Restores ${widget.restoreAmount} Condition',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12, decoration: TextDecoration.none),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: instances.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No cards yet.', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), decoration: TextDecoration.none)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: instances.length,
                      itemBuilder: (context, i) {
                        final inst = instances[i];
                        final card = CardRepository.instance.cardById(inst.cardId);
                        if (card == null) return const SizedBox.shrink();
                        final isFull = inst.condition >= kMaxCondition;
                        final isApplying = _applyingInstanceId == inst.instanceId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: GestureDetector(
                            onTap: (isFull || _applyingInstanceId != null) ? null : () => _use(inst),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(children: [
                                TriadCardView(card: card, size: 40, growth: inst, showCondition: false),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(card.name, style: TextStyle(color: isFull ? Colors.white38 : Colors.white, fontSize: 14, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                                  const SizedBox(height: 2),
                                  Text('${inst.condition} / $kMaxCondition — ${inst.conditionTier.label}', style: TextStyle(color: colorForConditionTier(inst.conditionTier), fontSize: 11, decoration: TextDecoration.none)),
                                ])),
                                if (isApplying)
                                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                                else if (isFull)
                                  const Text('FULL', style: TextStyle(color: Colors.white24, fontSize: 11, decoration: TextDecoration.none))
                                else
                                  const Icon(Icons.chevron_right, color: Colors.white38),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
