import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/player_profile_controller.dart';
import '../models/card_values.dart';
import '../models/triad_card.dart';
import '../services/api_client.dart';
import '../services/card_repository.dart';
import '../widgets/triad_card_view.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profileCtrl = context.watch<PlayerProfileController>();
    final money = profileCtrl.profile.money;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Poké Mart'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on, color: Color(0xFFC9A44C), size: 20),
                const SizedBox(width: 4),
                Text(
                  '₽ $money',
                  style: const TextStyle(
                    color: Color(0xFFC9A44C),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Booster Packs ──
          _SectionHeader(title: 'Booster Packs'),
          const SizedBox(height: 4),
          Text(
            'Open a pack to get 5 random Pokémon cards!',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          const SizedBox(height: 12),
          ..._boosterPacks.map((pack) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BoosterPackTile(pack: pack, money: money),
          )),
          const SizedBox(height: 24),

          // ── Singles ──
          _SectionHeader(title: 'Singles'),
          const SizedBox(height: 4),
          Text(
            'Hand-picked Pokémon with random stat bonuses.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          ),
          const SizedBox(height: 12),
          _SinglesGrid(money: money),
        ],
      ),
    );
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
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ── Booster pack definitions ─────────────────────────────────────────────

class _BoosterPackData {
  const _BoosterPackData({
    required this.name,
    required this.image,
    required this.price,
    required this.description,
  });
  final String name;
  final String image;
  final int price;
  final String description;
}

const _boosterPacks = [
  _BoosterPackData(
    name: 'Field Trip Booster',
    image: 'assets/images/Booster Pack/field.png',
    price: 500,
    description: '5 random Pokémon cards\nChance for rare & shiny!',
  ),
  // Additional boosters unlock as you progress through story mode.
  // _BoosterPackData(
  //   name: 'Kanto Collection',
  //   image: 'assets/images/Booster Pack/kanto.png',
  //   price: 600,
  //   description: 'Kanto-region Pokémon\nHigher chance of starters!',
  // ),
  // ...etc
];

// ── Booster pack tile ────────────────────────────────────────────────────

class _BoosterPackTile extends StatelessWidget {
  const _BoosterPackTile({required this.pack, required this.money});
  final _BoosterPackData pack;
  final int money;

  @override
  Widget build(BuildContext context) {
    final canAfford = money >= pack.price;
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canAfford
            ? () => _deductAndOpenBooster(context, pack.price)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Booster pack image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  pack.image,
                  width: 64,
                  height: 88,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 64,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('?', style: TextStyle(color: Colors.amber, fontSize: 26, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pack.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              // Price
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: canAfford
                      ? const Color(0xFFC9A44C).withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: canAfford
                        ? const Color(0xFFC9A44C).withValues(alpha: 0.4)
                        : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '₽ ${pack.price}',
                  style: TextStyle(
                    color: canAfford ? const Color(0xFFC9A44C) : Colors.grey,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deductAndOpenBooster(BuildContext context, int price) {
    final profileCtrl = context.read<PlayerProfileController>();
    if (profileCtrl.profile.money < price) return;
    profileCtrl.profile.money -= price;
    profileCtrl.addBoosterToInventory(pack.name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${pack.name} added to your Items!'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _SinglesGrid extends StatefulWidget {
  const _SinglesGrid({required this.money});
  final int money;

  @override
  State<_SinglesGrid> createState() => _SinglesGridState();
}

class _SinglesGridState extends State<_SinglesGrid> {
  List<_ShopSingle>? _items;
  String? _error;
  String? _shopDate;
  Set<String> _purchasedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _purchasedPrefsKey => 'shop_purchased_$_shopDate';

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final result = await context.read<ApiClient>().getDailyShop();
      final date = result['date'] as String;
      final rawItems = (result['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      final items = <_ShopSingle>[];
      for (final raw in rawItems) {
        final card = CardRepository.instance.cardById(raw['cardId'] as String);
        if (card == null) continue;
        final level = raw['level'] as int;
        final bonus = CardValues(
          north: raw['bonusNorth'] as int,
          south: raw['bonusSouth'] as int,
          east: raw['bonusEast'] as int,
          west: raw['bonusWest'] as int,
        );
        final price = raw['price'] as int;
        items.add(_ShopSingle(
          card: card.copyWith(
            values: card.values.plusBonus(bonus),
            baseLevel: level,
          ),
          level: level,
          bonus: bonus,
          price: price,
        ));
      }

      final prefs = await SharedPreferences.getInstance();
      final purchased = prefs.getStringList('shop_purchased_$date')?.toSet() ?? <String>{};

      if (mounted) {
        setState(() {
          _items = items;
          _shopDate = date;
          _purchasedIds = purchased;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load today's shop. Please try again.");
    }
  }

  Future<void> _markPurchased(String cardId) async {
    setState(() => _purchasedIds = {..._purchasedIds, cardId});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_purchasedPrefsKey, _purchasedIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    final money = context.watch<PlayerProfileController>().profile.money;

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_error!, style: TextStyle(color: Colors.white.withValues(alpha: 0.6)), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final items = _items;
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final canAfford = money >= item.price;
        final purchased = _purchasedIds.contains(item.card.id);

        return _ShopSingleTile(
          item: item,
          purchased: purchased,
          canAfford: canAfford,
          onTap: (canAfford && !purchased) ? () => _confirmAndBuy(context, item) : null,
        );
      },
    );
  }

  Future<void> _confirmAndBuy(BuildContext context, _ShopSingle item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => _PurchaseConfirmDialog(item: item),
    );
    if (confirmed != true || !mounted) return;
    await _buySingle(context, item);
  }

  Future<void> _buySingle(BuildContext context, _ShopSingle item) async {
    final profileCtrl = context.read<PlayerProfileController>();

    // Deduct money locally, then save to server
    profileCtrl.profile.money -= item.price;
    profileCtrl.notifyListeners();

    try {
      await profileCtrl.addBoosterCards([
        {
          'cardId': item.card.id,
          'level': item.level,
          'isShiny': false,
          'bonusNorth': item.bonus.north,
          'bonusSouth': item.bonus.south,
          'bonusEast': item.bonus.east,
          'bonusWest': item.bonus.west,
        },
      ]);
    } catch (_) {
      // Refund on failure
      profileCtrl.profile.money += item.price;
      profileCtrl.notifyListeners();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase failed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await _markPurchased(item.card.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Purchased ${item.card.name} Lv.${item.level}!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

// ── Shop grid tile with purchase flip animation ─────────────────────────

class _ShopSingleTile extends StatefulWidget {
  const _ShopSingleTile({
    required this.item,
    required this.purchased,
    required this.canAfford,
    required this.onTap,
  });

  final _ShopSingle item;
  final bool purchased;
  final bool canAfford;
  final VoidCallback? onTap;

  @override
  State<_ShopSingleTile> createState() => _ShopSingleTileState();
}

class _ShopSingleTileState extends State<_ShopSingleTile> with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  late final Animation<double> _flip;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _flip = CurvedAnimation(parent: _flipController, curve: Curves.easeInOut);
    if (widget.purchased) _flipController.value = 1;
  }

  @override
  void didUpdateWidget(covariant _ShopSingleTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.purchased && widget.purchased) {
      _flipController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final canTap = widget.canAfford && !widget.purchased && widget.onTap != null;

    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final t = _flip.value;
        final showBack = t > 0.5;
        final angle = t * pi;
        return Material(
          color: showBack
              ? Colors.green.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: canTap ? widget.onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(angle),
                child: showBack
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(pi),
                        child: _tileContent(item, purchased: true, canAfford: widget.canAfford),
                      )
                    : _tileContent(item, purchased: false, canAfford: widget.canAfford),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tileContent(_ShopSingle item, {required bool purchased, required bool canAfford}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Card image
        if (purchased)
          Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 0.4,
                child: TriadCardView(card: item.card, size: 80),
              ),
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
            ],
          )
        else
          TriadCardView(card: item.card, size: 80),
        const SizedBox(height: 6),
        // Name + level
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                item.card.name,
                style: TextStyle(
                  color: purchased ? Colors.white38 : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'Lv.${item.level}',
                style: TextStyle(
                  color: purchased ? Colors.white30 : Colors.white70,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Price or purchased
        if (purchased)
          const Text(
            'SOLD',
            style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
          )
        else
          Text(
            '₽ ${item.price}',
            style: TextStyle(
              color: canAfford ? const Color(0xFFC9A44C) : Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }
}

// ── Purchase confirmation modal ──────────────────────────────────────────

class _PurchaseConfirmDialog extends StatefulWidget {
  const _PurchaseConfirmDialog({required this.item});
  final _ShopSingle item;

  @override
  State<_PurchaseConfirmDialog> createState() => _PurchaseConfirmDialogState();
}

class _PurchaseConfirmDialogState extends State<_PurchaseConfirmDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _flyController;
  late final Animation<Offset> _flyOffset;
  late final Animation<double> _flyRotation;
  late final Animation<double> _flyFade;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _flyController = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _flyOffset = Tween<Offset>(begin: Offset.zero, end: const Offset(1.4, -1.6))
        .animate(CurvedAnimation(parent: _flyController, curve: Curves.easeInCubic));
    _flyRotation = Tween<double>(begin: 0, end: 0.7)
        .animate(CurvedAnimation(parent: _flyController, curve: Curves.easeIn));
    _flyFade = Tween<double>(begin: 1, end: 0)
        .animate(CurvedAnimation(parent: _flyController, curve: const Interval(0.4, 1.0)));
  }

  @override
  void dispose() {
    _flyController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    await _flyController.forward();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _flyController,
            builder: (context, child) {
              final offset = Offset(
                _flyOffset.value.dx * size.width * 0.6,
                _flyOffset.value.dy * size.height * 0.6,
              );
              return Opacity(
                opacity: _flyFade.value,
                child: Transform.translate(
                  offset: offset,
                  child: Transform.rotate(angle: _flyRotation.value, child: child),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TriadCardView(card: item.card, size: 140),
                  const SizedBox(height: 14),
                  Text(
                    '${item.card.name} Lv.${item.level}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₽ ${item.price}',
                    style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          if (!_confirming) ...[
            const SizedBox(height: 24),
            const Text(
              'Are you sure?',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 14),
                ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC9A44C),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Buy'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ShopSingle {
  final TriadCard card;
  final int level;
  final CardValues bonus;
  final int price;

  _ShopSingle({
    required this.card,
    required this.level,
    required this.bonus,
    required this.price,
  });
}
