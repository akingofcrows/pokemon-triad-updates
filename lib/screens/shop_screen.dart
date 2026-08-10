import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/player_profile_controller.dart';
import '../models/card_values.dart';
import '../models/triad_card.dart';
import '../services/api_client.dart';
import '../services/card_repository.dart';
import '../widgets/pressable_button.dart';
import '../widgets/triad_card_view.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, this.locationName});
  final String? locationName;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  final _moneyKey = GlobalKey();

  // ── Slot-machine roll ──
  late final AnimationController _rollCtrl;
  late final Animation<double> _rollAnim;
  int _rollFrom = 0;
  int _rollTo = 0;

  // ── Floating damage number — rendered via the root Overlay so it always
  // paints above the AppBar/status bar instead of being clipped by the
  // AppBar's own toolbar bounds.
  final List<OverlayEntry> _damageOverlayEntries = [];

  // ── Purchase toasts ──
  final List<_ToastEntry> _toasts = [];
  int _toastId = 0;

  void _showToast({String? imagePath, Widget? imageWidget, required String text}) {
    final id = _toastId++;
    final entry = _ToastEntry(id: id, imagePath: imagePath, imageWidget: imageWidget, text: text);
    setState(() => _toasts.add(entry));
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() => _toasts.removeWhere((e) => e.id == id));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _rollCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _rollAnim = CurvedAnimation(parent: _rollCtrl, curve: Curves.easeOutCubic);

    // One-time: clear all shop purchased state
    _resetShopPurchases();
  }

  Future<void> _resetShopPurchases() async {
    final prefs = await SharedPreferences.getInstance();
    // Only run once
    if (prefs.getBool('shop_reset_v1') == true) return;
    final keys = prefs.getKeys().where((k) => k.startsWith('shop_purchased_'));
    for (final k in keys) {
      await prefs.remove(k);
    }
    await prefs.setBool('shop_reset_v1', true);
  }

  @override
  void dispose() {
    for (final entry in _damageOverlayEntries) {
      entry.remove();
    }
    _rollCtrl.dispose();
    super.dispose();
  }

  /// Triggers the slot-machine roll + floating "-X ₽" on the money badge.
  /// Call this BEFORE deducting money so the animation captures the old value.
  void animatePurchase(int amount) {
    final profileCtrl = context.read<PlayerProfileController>();
    final current = profileCtrl.profile.money;
    _rollFrom = current; // old value (before purchase)
    _rollTo = current - amount; // new value (after purchase)
    _rollCtrl.reset();
    _rollCtrl.forward();
    _showFloatingDamage(amount);
  }

  void _showFloatingDamage(int amount) {
    final box = _moneyKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset(box.size.width, 0));
    final stackIndex = _damageOverlayEntries.length;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _FloatingDamageOverlay(
        anchor: anchor,
        amount: amount,
        stackIndex: stackIndex,
        onDone: () {
          entry.remove();
          _damageOverlayEntries.remove(entry);
        },
      ),
    );
    _damageOverlayEntries.add(entry);
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final profileCtrl = context.watch<PlayerProfileController>();
    final money = profileCtrl.profile.money;

    // Mark shop as seen so NEW badge disappears on home
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final client = context.read<ApiClient>();
        final result = await client.getDailyShop();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('shop_last_seen_date', result['date'] as String);
      } catch (_) {}
    });

    return Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      appBar: AppBar(
        backgroundColor: const Color(0xFF282A30),
        title: Text(widget.locationName != null ? '${widget.locationName} Pok\u00e9 Mart' : 'Pok\u00e9 Mart'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              key: _moneyKey,
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF282A30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1A1C20), width: 1),
              ),
              alignment: Alignment.center,
              child: AnimatedBuilder(
                animation: _rollAnim,
                builder: (context, _) {
                  final display = _rollCtrl.isAnimating
                      ? (_rollFrom -
                                ((_rollFrom - _rollTo) * _rollAnim.value)
                                    .round())
                            .toString()
                      : money.toString();
                  return Text(
                    '₽ $display',
                    style: const TextStyle(
                      fontFamily: 'PowerGreen',
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Booster Packs ──
              _SectionHeader(title: 'Booster Packs'),
              const SizedBox(height: 4),
              Text(
                'Open a pack to get 5 random Pokémon cards!',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              _BoostersGrid(
                money: money,
                onPurchased: (amount) => animatePurchase(amount),
                onToast: _showToast,
              ),
              const SizedBox(height: 24),

              // ── Singles ──
              _SectionHeader(title: 'Singles'),
              const SizedBox(height: 4),
              Text(
                'Hand-picked Pokémon with random stat bonuses.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              _SinglesGrid(
                money: money,
                onPurchased: (amount) => animatePurchase(amount),
                onToast: _showToast,
              ),
            ],
          ),
          // Purchase toasts — bottom-right
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _toasts.reversed.map((t) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _PurchaseToast(entry: t),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// Rendered via Overlay.insert so it always paints above the AppBar/status
// bar rather than being clipped by the AppBar's own toolbar bounds.
class _FloatingDamageOverlay extends StatelessWidget {
  const _FloatingDamageOverlay({
    required this.anchor,
    required this.amount,
    required this.stackIndex,
    required this.onDone,
  });
  final Offset anchor;
  final int amount;
  final int stackIndex;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: anchor.dx - 60,
      top: anchor.dy - 12.0 - 18.0 * stackIndex,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1600),
          onEnd: onDone,
          builder: (context, t, _) {
            // Hold at full opacity for first 60%, then fade out.
            final fadeT = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
            return Opacity(
              opacity: 1.0 - fadeT,
              child: Transform.translate(
                offset: Offset(0, -18 * t),
                child: SizedBox(
                  width: 60,
                  // Overlay entries sit outside the Scaffold/Material
                  // ancestor chain, so Text needs its own Material here or
                  // it falls back to Flutter's "missing Material" debug
                  // style (red text, double yellow underline).
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      '-$amount ₽',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'PowerGreen',
                        color: Color(0xFFFF6B6B),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
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
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 16,
            fontWeight: FontWeight.w700,
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
    price: 800,
    description: '5 random Pokémon cards\nChance for rare & shiny!',
  ),
  _BoosterPackData(
    name: 'Kanto Collection',
    image: 'assets/images/Booster Pack/kanto.png',
    price: 1200,
    description: 'Kanto-region Pokémon\nHigher chance of starters!',
  ),
  // ...etc
];

// ── Booster grid ────────────────────────────────────────────────────────

class _BoostersGrid extends StatefulWidget {
  const _BoostersGrid({
    required this.money,
    required this.onPurchased,
    required this.onToast,
  });
  final int money;
  final void Function(int amount) onPurchased;
  final void Function({String? imagePath, Widget? imageWidget, required String text}) onToast;

  @override
  State<_BoostersGrid> createState() => _BoostersGridState();
}

class _BoostersGridState extends State<_BoostersGrid> {
  final Set<String> _buying = {};

  @override
  Widget build(BuildContext context) {
    final money = context.watch<PlayerProfileController>().profile.money;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: _boosterPacks.length,
      itemBuilder: (context, index) {
        final pack = _boosterPacks[index];
        final canAfford = money >= pack.price;
        final buying = _buying.contains(pack.name);
        final tile = _BoosterGridTile(
          pack: pack,
          canAfford: canAfford && !buying,
          buying: buying,
        );
        return (canAfford && !buying)
            ? PressableButton(
                onTap: () => _confirmAndBuy(pack),
                child: tile,
              )
            : tile;
      },
    );
  }

  Future<void> _confirmAndBuy(_BoosterPackData pack) async {
    final confirmed = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _BoosterConfirmDialog(pack: pack),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (confirmed == true && mounted) {
      _buy(pack);
    }
  }

  Future<void> _buy(_BoosterPackData pack) async {
    final profileCtrl = context.read<PlayerProfileController>();
    setState(() => _buying.add(pack.name));
    // Animate BEFORE deducting so the slot-machine roll captures the old value.
    widget.onPurchased(pack.price);
    try {
      await profileCtrl.buyBoosterPack(pack.name, pack.price);
    } catch (_) {
      setState(() => _buying.remove(pack.name));
      return;
    }
    if (mounted) {
      setState(() => _buying.remove(pack.name));
      widget.onToast(
        imagePath: pack.image,
        text: '${pack.name} added to your inventory',
      );
    }
  }
}

class _BoosterGridTile extends StatelessWidget {
  const _BoosterGridTile({
    required this.pack,
    required this.canAfford,
    required this.buying,
  });
  final _BoosterPackData pack;
  final bool canAfford;
  final bool buying;

  @override
  Widget build(BuildContext context) {
    return _shopCardFrame(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Booster art
            Expanded(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    pack.image,
                    fit: BoxFit.contain,
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
                        child: Text(
                          '?',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Name badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x60000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                pack.name,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'PowerGreen',
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 4),
            // Price badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0x60C9A44C),
                borderRadius: BorderRadius.circular(6),
              ),
              child: buying
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    )
                  : Text(
                      '₽ ${pack.price}',
                      style: TextStyle(
                        color: canAfford ? const Color(0xFFFFD700) : Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'PowerGreen',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Booster purchase confirmation dialog ────────────────────────────────

class _BoosterConfirmDialog extends StatelessWidget {
  const _BoosterConfirmDialog({required this.pack});
  final _BoosterPackData pack;

  @override
  Widget build(BuildContext context) {
    final tileWidth = (MediaQuery.of(context).size.width - 32 - 10) / 2;
    final tileHeight = tileWidth / 0.85;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: tileWidth,
            height: tileHeight,
            child: _shopCardFrame(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            pack.image,
                            fit: BoxFit.contain,
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
                                child: Text(
                                  '?',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pack.name,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pack.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₽ ${pack.price}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Are you sure?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PressableButton(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF74777F)),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              PressableButton(
                onTap: () => Navigator.pop(context, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9A44C),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Buy',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Booster pack definitions ─────────────────────────────────────────────

class _SinglesGrid extends StatefulWidget {
  const _SinglesGrid({
    required this.money,
    required this.onPurchased,
    required this.onToast,
  });
  final int money;
  final void Function(int amount) onPurchased;
  final void Function({String? imagePath, Widget? imageWidget, required String text}) onToast;

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
      final rawItems = (result['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
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
        items.add(
          _ShopSingle(
            card: card.copyWith(
              values: card.values.plusBonus(bonus),
              baseLevel: level,
            ),
            level: level,
            bonus: bonus,
            price: price,
          ),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final purchased =
          prefs.getStringList('shop_purchased_$date')?.toSet() ?? <String>{};

      if (mounted) {
        setState(() {
          _items = items;
          _shopDate = date;
          _purchasedIds = purchased;
        });
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _error = "Couldn't load today's shop. Please try again.",
        );
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
            Text(
              _error!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
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

        final tappable = canAfford && !purchased;
        final tile = _ShopSingleTile(
          item: item,
          purchased: purchased,
          canAfford: canAfford,
          onTap: null,
        );
        return tappable
            ? PressableButton(
                onTap: () => _confirmAndBuy(context, item),
                child: tile,
              )
            : tile;
      },
    );
  }

  Future<void> _confirmAndBuy(BuildContext context, _ShopSingle item) async {
    final ownedCount = context
        .read<PlayerProfileController>()
        .allCardInstances
        .where((inst) => inst.cardId == item.card.id)
        .length;
    // showDialog pushes a DialogRoute (a PopupRoute), and Hero flights only
    // trigger between PageRoutes — so a plain PageRouteBuilder is used here
    // instead to let the card Hero fly to/from its grid tile.
    final confirmed = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _PurchaseConfirmDialog(
              item: item,
              owned: ownedCount > 0,
              ownedCount: ownedCount,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (confirmed == true && mounted) {
      await _buySingle(context, item);
    }
  }

  Future<void> _buySingle(BuildContext context, _ShopSingle item) async {
    final profileCtrl = context.read<PlayerProfileController>();

    // Animate BEFORE deducting so the slot-machine roll captures the old value.
    widget.onPurchased(item.price);

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
      return;
    }

    await _markPurchased(item.card.id);

    if (mounted) {
      widget.onToast(
        imageWidget: TriadCardView(card: item.card, size: 40),
        text: '${item.card.name} added to your inventory',
      );
    }
  }
}

// ── Toast entry ───────────────────────────────────────────────────────────

class _ToastEntry {
  _ToastEntry({
    required this.id,
    this.imagePath,
    this.imageWidget,
    required this.text,
  });
  final int id;
  final String? imagePath;
  final Widget? imageWidget;
  final String text;
}

class _PurchaseToast extends StatelessWidget {
  const _PurchaseToast({required this.entry});
  final _ToastEntry entry;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, t, _) {
        return Transform.translate(
          offset: Offset(20 * (1 - t), 10 * (1 - t)),
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF282A30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: entry.imageWidget ??
                        (entry.imagePath != null
                            ? Image.asset(
                                entry.imagePath!,
                                width: 36,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 36,
                                  height: 48,
                                  color: const Color(0xFF3A3C44),
                                ),
                              )
                            : Container(
                                width: 36,
                                height: 48,
                                color: const Color(0xFF3A3C44),
                              )),
                  ),
                  const SizedBox(width: 10),
                  // Text
                  Flexible(
                    child: Text(
                      entry.text,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Returns a [bottomLeft, topRight] gradient pair — dark container on the
/// left blending into a vivid type accent color on the right.
List<Color> _gradientForType(String affinity) {
  const bg = Color(0xFF282A30);
  switch (affinity.toLowerCase()) {
    case 'fire':     return const [bg, Color(0xFFF44B1A)];
    case 'water':    return const [bg, Color(0xFF3DA5E0)];
    case 'grass':    return const [bg, Color(0xFF5CBF60)];
    case 'electric': return const [bg, Color(0xFFF0D830)];
    case 'psychic':  return const [bg, Color(0xFFE83A88)];
    case 'ice':      return const [bg, Color(0xFF5CE8F0)];
    case 'dragon':   return const [bg, Color(0xFF9050E0)];
    case 'dark':     return const [bg, Color(0xFF705080)];
    case 'fairy':    return const [bg, Color(0xFFF090D0)];
    case 'fighting': return const [bg, Color(0xFFE07030)];
    case 'flying':   return const [bg, Color(0xFFA0B8F0)];
    case 'ghost':    return const [bg, Color(0xFF9060C0)];
    case 'ground':   return const [bg, Color(0xFFE0A830)];
    case 'poison':   return const [bg, Color(0xFFC060E0)];
    case 'rock':     return const [bg, Color(0xFFC0A858)];
    case 'bug':      return const [bg, Color(0xFFA0D050)];
    case 'steel':    return const [bg, Color(0xFFB8B8C8)];
    case 'normal':   return const [bg, Color(0xFFC8C0A0)];
    default:         return const [bg, Color(0xFF526170)];
  }
}

// ── Shared shop card frame (used by the grid tile and purchase confirmation) ──

Widget _shopCardFrame({required Widget child, List<Color>? diagonalColors, String? affinity}) {
  final grad = diagonalColors ?? const [Color(0xFF636178), Color(0xFF526170)];
  final typeIconPath = affinity != null ? 'assets/ui/types/$affinity.png' : null;
  return Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned(
        left: -4,
        right: -4,
        top: -4,
        bottom: -4,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2D2E35), Color(0xFF1F2027)],
              ),
            ),
          ),
        ),
      ),
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF282A30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1A1C20), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipPath(
                clipper: _DiagonalTopClipper(),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.topRight,
                      colors: grad,
                    ),
                  ),
                ),
              ),
            ),
            // Type icon watermark in the diagonal cut
            if (typeIconPath != null)
              Positioned(
                top: 0,
                left: 4,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.22,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Color(0xFFB0B0B8),
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        typeIconPath,
                        width: 56,
                        height: 56,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            // Diagonal cut border — behind content so cards/images paint on top
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DiagonalShadowPainter(),
                ),
              ),
            ),
            child,
            // Inner shadow — 2px light edge on top/left + #B6A2A0 border
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _InnerShadowPainter(),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _shopCardContent(
  _ShopSingle item, {
  required bool purchased,
  required bool canAfford,
  required bool owned,
  int? ownedCount,
}) {
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // Card image
      if (purchased)
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.6),
            BlendMode.darken,
          ),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.grey,
              BlendMode.saturation,
            ),
            child: TriadCardView(card: item.card, size: 80),
          ),
        )
      else
        TriadCardView(card: item.card, size: 80),
      const SizedBox(height: 6),
      // Name + level badge
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x60000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (owned)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Image.asset('assets/ui/icon_own.png', width: 12, height: 12),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  '${item.card.name} Lv.${item.level}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: purchased ? Colors.white38 : Colors.white.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'PowerGreen',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 4),
      // Price badge
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0x60C9A44C),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '₽ ${item.price}',
            style: TextStyle(
              color: purchased ? Colors.white38 : const Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFamily: 'PowerGreen',
            ),
          ),
        ),
      ),
      if (ownedCount != null) ...[
        const SizedBox(height: 3),
        Text(
          '$ownedCount owned',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      ],
    ],
  );
}

// The purchase modal's card is taller than the grid tile (it adds an "owned"
// line under the price), so mid-flight the Hero would squeeze that taller
// content into the tile's shorter box and overflow. Always fly the compact,
// tile-style content instead — the real (possibly taller) card only
// reappears once each endpoint's own Hero settles.
// Hero flights re-parent this into the Navigator's Overlay, outside the
// Scaffold/Material ancestor the tile and modal normally sit under — without
// its own Material, every Text here would fall back to Flutter's "missing
// Material ancestor" style (red text, double yellow underline).
Widget _shopCardFlightShuttle(_ShopSingle item, bool owned) {
  return Material(
    type: MaterialType.transparency,
    child: _shopCardFrame(
      diagonalColors: _gradientForType(item.card.affinity),
      affinity: item.card.affinity,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: _shopCardContent(
          item,
          purchased: false,
          canAfford: true,
          owned: owned,
        ),
      ),
    ),
  );
}

// ── SOLD stamp ───────────────────────────────────────────────────────────

class _SoldStamp extends StatelessWidget {
  const _SoldStamp();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.32,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFC0392B), width: 2.5),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFC0392B), width: 1),
          ),
          child: const Text(
            'SOLD',
            style: TextStyle(
              color: Color(0xFFC0392B),
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
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

class _ShopSingleTileState extends State<_ShopSingleTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  late final Animation<double> _flip;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
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
    final canTap =
        widget.canAfford && !widget.purchased && widget.onTap != null;
    final owned = context
        .read<PlayerProfileController>()
        .everOwnedCardIds
        .contains(item.card.id);

    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final t = _flip.value;
        final showBack = t > 0.5;
        final angle = t * pi;
        return Hero(
          tag: 'shop_card_${item.card.id}',
          flightShuttleBuilder:
              (flightContext, animation, direction, fromCtx, toCtx) =>
                  _shopCardFlightShuttle(item, owned),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _shopCardFrame(
                diagonalColors: _gradientForType(item.card.affinity),
                affinity: item.card.affinity,
                child: Material(
                  color: showBack
                      ? Colors.black.withValues(alpha: 0.35)
                      : Colors.transparent,
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
                                child: _shopCardContent(
                                  item,
                                  purchased: true,
                                  canAfford: widget.canAfford,
                                  owned: owned,
                                ),
                              )
                            : _shopCardContent(
                                item,
                                purchased: false,
                                canAfford: widget.canAfford,
                                owned: owned,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.purchased)
                const Positioned(top: 6, left: 6, child: _SoldStamp()),
            ],
          ),
        );
      },
    );
  }
}

// ── Purchase confirmation modal ──────────────────────────────────────────

class _PurchaseConfirmDialog extends StatelessWidget {
  const _PurchaseConfirmDialog({
    required this.item,
    required this.owned,
    required this.ownedCount,
  });
  final _ShopSingle item;
  final bool owned;
  final int ownedCount;

  @override
  Widget build(BuildContext context) {
    // Match the Singles grid tile's size exactly (2-column GridView inside
    // a ListView with 16px padding, 10px cross-axis spacing, aspect ratio 0.85).
    final tileWidth = (MediaQuery.of(context).size.width - 32 - 10) / 2;
    final tileHeight = tileWidth / 0.85;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: tileWidth,
            height: tileHeight,
            child: Hero(
              tag: 'shop_card_${item.card.id}',
              flightShuttleBuilder:
                  (flightContext, animation, direction, fromCtx, toCtx) =>
                      _shopCardFlightShuttle(item, owned),
              child: _shopCardFrame(
                diagonalColors: _gradientForType(item.card.affinity),
                affinity: item.card.affinity,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _shopCardContent(
                    item,
                    purchased: false,
                    canAfford: true,
                    owned: owned,
                    ownedCount: ownedCount,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Are you sure?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PressableButton(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF74777F)),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              PressableButton(
                onTap: () => Navigator.pop(context, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9A44C),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Buy',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagonalTopClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.6);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.25);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Paints inner shadow (transparent white) + solid #B6A2A0 border on top/left/corner.
class _InnerShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = 12.0;

    // Transparent white glow shadow
    final glowPaint = Paint()
      ..color = const Color(0x20FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawLine(Offset(r, 0), Offset(size.width, 0), glowPaint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 1.5708, false, glowPaint);
    canvas.drawLine(Offset(0, r), Offset(0, size.height), glowPaint);

    // Solid #B6A2A0 border
    final borderPaint = Paint()
      ..color = const Color(0x99B6A2A0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(Offset(r, 0), Offset(size.width, 0), borderPaint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 1.5708, false, borderPaint);
    canvas.drawLine(Offset(0, r), Offset(0, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Draws a 1px border along the diagonal cut line.
class _DiagonalShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x801A1C20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height * 0.6),
      Offset(size.width, size.height * 0.25),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
