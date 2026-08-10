import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/card_growth.dart';
import '../models/deck.dart';
import '../models/npc_trainer.dart';
import '../services/card_repository.dart';
import '../widgets/triad_card_view.dart';
import 'battle_screen.dart';
import 'wild_battle_screen.dart';
import '../widgets/pressable_button.dart';
import '../widgets/badge_icon.dart';

// ── Battle menu content (embedded in home screen, keeps bottom nav) ──

class BattleMenuContent extends StatefulWidget {
  const BattleMenuContent({
    super.key,
    required this.visible,
    this.onDismiss,
    this.soloVisible = false,
    this.onSoloStateChanged,
    this.onBackgroundTap,
  });

  final bool visible;
  final VoidCallback? onDismiss;
  final bool soloVisible;
  final ValueChanged<bool>? onSoloStateChanged;
  final VoidCallback? onBackgroundTap;

  @override
  State<BattleMenuContent> createState() => _BattleMenuContentState();
}

class _BattleMenuContentState extends State<BattleMenuContent> with TickerProviderStateMixin {
  static const _badgeIds = [
    'boulder_badge', 'cascade_badge', 'thunder_badge', 'rainbow_badge',
    'soul_badge', 'marsh_badge', 'volcano_badge', 'earth_badge',
  ];
  bool _soloOpen = false;
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final AnimationController _soloCtrl;
  late final Animation<Offset> _soloSlide;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _soloCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _soloSlide = Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero).animate(CurvedAnimation(parent: _soloCtrl, curve: Curves.easeOutCubic));
    _slideCtrl.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !widget.visible) {
        widget.onDismiss?.call();
      }
    });
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _slideCtrl.forward());
    }
  }

  @override
  void didUpdateWidget(covariant BattleMenuContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.soloVisible && !oldWidget.soloVisible) {
      // Parent requested Solo → animate in (no callback needed, parent already knows)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _slideCtrl.reverse().then((_) {
          if (!mounted) return;
          setState(() => _soloOpen = true);
          _soloCtrl.forward();
        });
      });
    } else if (!widget.soloVisible && oldWidget.soloVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _closeSoloToBattle();
      });
    }
    if (widget.visible && !oldWidget.visible) {
      _slideCtrl.forward();
    } else if (!widget.visible && oldWidget.visible) {
      if (_soloOpen) {
        _dismiss();
      } else {
        _slideCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _soloCtrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_soloOpen) {
      _soloCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _soloOpen = false);
        _slideCtrl.reverse().then((_) {
          if (!mounted) return;
          widget.onDismiss?.call();
        });
      });
    } else {
      _slideCtrl.reverse().then((_) {
        if (!mounted) return;
        widget.onDismiss?.call();
      });
    }
  }

  void _closeSoloToBattle() {
    if (!_soloOpen) return;
    _soloCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _soloOpen = false);
      _slideCtrl.forward();
    });
  }

  void _toggleSolo() {
    if (_soloOpen) {
      // Solo → Battle: slide Solo down, slide Battle up
      setState(() => _soloOpen = false);
      widget.onSoloStateChanged?.call(false);
      _soloCtrl.reverse();
      _slideCtrl.forward();
    } else {
      // Battle → Solo: slide Battle down, slide Solo up
      _slideCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _soloOpen = true);
        widget.onSoloStateChanged?.call(true);
        _soloCtrl.forward();
      });
    }
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon!'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Backdrop — fades in/out
        if (widget.visible || _slideCtrl.isAnimating)
          AnimatedBuilder(
            animation: _slideCtrl,
            builder: (_, child) {
              final opacity = _slideCtrl.value * 0.15;
              return Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.visible ? _dismiss : null,
                  child: Container(color: Colors.black.withValues(alpha: opacity)),
                ),
              );
            },
          ),

        // Battle panel — slides up
        if (widget.visible || _slideCtrl.isAnimating)
          Positioned(
            left: 0, right: 0, bottom: 47,
            child: SlideTransition(
              position: _slideAnim,
              child: _buildMainPanel(),
            ),
          ),

        // Solo panel — slides up over battle panel
        if (_soloOpen || _soloCtrl.isAnimating)
          Positioned(
            left: 0, right: 0, bottom: 47,
            child: SlideTransition(
              position: _soloSlide,
              child: _buildSoloPanel(),
            ),
          ),
      ],
    );
  }

  Widget _buildSoloPanel() {
    final pCtrl = context.watch<PlayerProfileController>();
    final badges = pCtrl.badges;
    final kantoDone = badges.contains('earth_badge');

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1E1E), Color(0xFF141414)],
          ),
          border: Border(top: BorderSide(color: Color(0xFF1A1C20))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: const Color(0xFF74777F), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              const Text('SOLO', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 6, decoration: TextDecoration.none)),
              const SizedBox(height: 24),
              _RegionTile(
                region: 'Kanto',
                subtitle: '${badges.length}/8 badges',
                color: const Color(0xFF4CAF50),
                locked: false,
                iconAsset: 'assets/images/Booster Pack/kantoicon.png',
                extra: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    for (int i = 0; i < 8; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: BadgeIcon(spriteIndex: i, size: 24, earned: badges.contains(_badgeIds[i]) || i < 2), // TODO: remove || i < 2
                      ),
                  ],
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WildBattleLocationScreen())),
              ),
              const SizedBox(height: 10),
              _RegionTile(
                region: 'Johto',
                subtitle: kantoDone ? 'New adventure awaits' : 'Complete Kanto first',
                color: const Color(0xFF42A5F5),
                locked: !kantoDone,
                iconAsset: 'assets/images/Booster Pack/johtoicon.png',
                onTap: kantoDone ? () {} : null,
              ),
              const SizedBox(height: 10),
              _RegionTile(
                region: 'Hoenn',
                subtitle: 'Coming later',
                color: const Color(0xFFFF7043),
                locked: true,
                onTap: null,
              ),
              const SizedBox(height: 10),
              _RegionTile(
                region: 'Sinnoh',
                subtitle: 'Coming later',
                color: const Color(0xFFAB47BC),
                locked: true,
                onTap: null,
              ),
        ],
      ),
    ),
  ),
);

  }
  // ── Main panel with Solo / Versus buttons ──

  Widget _buildMainPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E1E1E), Color(0xFF141414)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Color(0xFF1A1C20))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: const Color(0xFF74777F), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              const Text('BATTLE', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 6, decoration: TextDecoration.none)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: PressableButton(
                        onTap: _toggleSolo,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFF3A3C44),
                            border: Border.all(color: const Color(0xFF74777F)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset('assets/ui/solo.png', width: 24, height: 24),
                              const SizedBox(width: 10),
                              const Text('SOLO', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 6, decoration: TextDecoration.none)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: PressableButton(
                        onTap: () => _comingSoon(),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFF282A30),
                            border: Border.all(color: const Color(0xFF1A1C20)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ColorFiltered(
                                colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
                                child: Image.asset('assets/ui/versus.png', width: 24, height: 24),
                              ),
                              const SizedBox(width: 10),
                              Text('VERSUS', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 6, decoration: TextDecoration.none)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({super.key, required this.region, required this.subtitle, required this.color, required this.locked, this.onTap, this.iconAsset, this.extra});
  final String region, subtitle;
  final Color color;
  final bool locked;
  final VoidCallback? onTap;
  final String? iconAsset;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return PressableButton(
      onTap: onTap ?? () {},
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF3A3C44),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: locked ? Colors.white.withValues(alpha: 0.06) : const Color(0xFF74777F)),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: locked ? 0.04 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: iconAsset != null
                    ? Padding(padding: const EdgeInsets.all(10), child: Image.asset(iconAsset!, width: 24, height: 24))
                    : Icon(locked ? Icons.lock : Icons.map, color: locked ? Colors.white24 : Colors.white54, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(region, style: TextStyle(color: locked ? Colors.white38 : Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: locked ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                    if (extra != null) ...[const SizedBox(height: 6), extra!],
                  ],
                ),
              ),
              if (!locked) Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
            ],
          ),
        ),
    );
  }
}

class _SoloOption extends StatelessWidget {
  const _SoloOption({
    this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.onTap,
    this.imagePath,
  });

  final IconData? icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final iconWidget = imagePath != null
        ? Image.asset(imagePath!, width: 24, height: 24, color: color)
        : Icon(icon, color: color, size: 24);

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
          ),
        ),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

// ── Random Battle Ranks Screen ──

class RandomBattleRanksScreen extends StatelessWidget {
  const RandomBattleRanksScreen({super.key});

  static const _ranks = [
    _RankInfo(label: 'Beginner', difficulty: 'easy', color: Color(0xFF4CAF50), icon: Icons.eco),
    _RankInfo(label: 'Intermediate', difficulty: 'medium', color: Color(0xFFFFC107), icon: Icons.whatshot),
    _RankInfo(label: 'Expert', difficulty: 'hard', color: Color(0xFFFF5722), icon: Icons.local_fire_department),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Random Battle', style: TextStyle(letterSpacing: 3)),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/ui/card_back.png', width: 80, height: 112),
              const SizedBox(height: 24),
              ..._ranks.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _RankButton(
                      rank: r,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => RandomBattleDetailScreen(rank: r)),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankInfo {
  final String label;
  final String difficulty;
  final Color color;
  final IconData icon;
  const _RankInfo({required this.label, required this.difficulty, required this.color, required this.icon});
}

class _RankButton extends StatelessWidget {
  const _RankButton({required this.rank, required this.onTap});
  final _RankInfo rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        decoration: BoxDecoration(
          color: rank.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: rank.color.withValues(alpha: 0.35), width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(rank.icon, color: rank.color, size: 26),
            const SizedBox(width: 14),
            Text(
              rank.label.toUpperCase(),
              style: TextStyle(
                color: rank.color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Random Battle Detail Screen (Beginner / Intermediate / Expert) ──

class RandomBattleDetailScreen extends StatefulWidget {
  const RandomBattleDetailScreen({super.key, required this.rank});
  final _RankInfo rank;

  @override
  State<RandomBattleDetailScreen> createState() => _RandomBattleDetailScreenState();
}

class _RandomBattleDetailScreenState extends State<RandomBattleDetailScreen> {
  final List<String> _tasks = ['Flip 3 cards', 'Flip 2 cards', 'Win within 15 turns'];

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PlayerProfileController>();
    final profile = ctrl.profile;
    final deck = profile.defaultDeck;
    final validDecks = profile.decks.where((d) => d.isValid).toList();
    final hasDeck = deck != null && deck.isValid;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Random Battle (${widget.rank.label})', style: const TextStyle(fontSize: 16, letterSpacing: 2)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── First-time rewards box ──
            _InfoBox(
              icon: Icons.card_giftcard,
              iconColor: const Color(0xFFC9A44C),
              title: 'First Time Rewards',
              children: [
                _RewardRow(label: '100 ₽', detail: 'PokéDollars'),
                _RewardRow(label: '+500 XP', detail: 'Trainer XP'),
                _RewardRow(label: '1x Poké Ball', detail: 'Card Pack'),
              ],
            ),
            const SizedBox(height: 14),

            // ── Battle task box ──
            _InfoBox(
              icon: Icons.assignment,
              iconColor: const Color(0xFF4FC3F7),
              title: 'Battle Task',
              children: _tasks.map((t) => _RewardRow(label: t, icon: Icons.check_box_outline_blank)).toList(),
            ),
            const SizedBox(height: 20),

            // ── Card back + task boxes row ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset('assets/ui/card_back.png', width: 70, height: 98),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      _InfoBox(
                        icon: Icons.emoji_events,
                        iconColor: const Color(0xFFFFC107),
                        title: 'Win Reward',
                        children: [
                          _RewardRow(label: '200 ₽', detail: '+ Card Capture chance'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _InfoBox(
                        icon: Icons.trending_down,
                        iconColor: const Color(0xFFE57373),
                        title: 'Loss',
                        children: [
                          _RewardRow(label: '25 ₽', detail: 'Consolation'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Deck picker button (same style as home page) ──
            _buildDeckPicker(context, ctrl, deck, validDecks),
            const SizedBox(height: 24),

            // ── Battle button ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: hasDeck ? () => _startRandomBattle(context, ctrl, deck!) : null,
                icon: Icon(Icons.sports_esports, color: hasDeck ? Colors.black : Colors.grey),
                label: Text(
                  hasDeck ? 'BATTLE!' : 'Need a deck to battle',
                  style: TextStyle(
                    color: hasDeck ? Colors.black : Colors.grey,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    fontFamily: 'PowerGreen',
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: hasDeck ? widget.rank.color : Colors.grey.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Deck picker (matches home screen style) ──

  Widget _buildDeckPicker(BuildContext context, PlayerProfileController ctrl, Deck? deck, List<Deck> validDecks) {
    final growth = ctrl.cardGrowth;
    final cardWidgets = <Widget>[];

    if (deck != null) {
      for (var i = 0; i < deck.cardIds.length; i++) {
        final id = deck.cardIds[i];
        final card = CardRepository.instance.cardById(id);
        CardGrowth? g;
        final instId = deck.instanceIds != null && i < deck.instanceIds!.length
            ? deck.instanceIds![i]
            : null;
        if (instId != null && instId > 0) {
          g = ctrl.allCardInstances.where((inst) => inst.instanceId == instId).firstOrNull;
        }
        g ??= growth[id];
        cardWidgets.add(
          SizedBox(
            width: 52, height: 52,
            child: card != null ? TriadCardView(card: card, size: 52, growth: g) : const SizedBox.shrink(),
          ),
        );
      }
    }

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.deckBuilder),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            deck != null ? 'ACTIVE DECK' : 'No Active Deck',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              fontFamily: 'PowerGreen',
              shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 2))],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: cardWidgets.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: cardWidgets,
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                    child: Text('Tap to build a deck',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, fontFamily: 'PowerGreen')),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Start random battle ──

  void _startRandomBattle(BuildContext context, PlayerProfileController ctrl, Deck playerDeck) {
    final allNpcs = CardRepository.instance.npcs;
    final eligible = allNpcs.where((n) => n.difficulty == widget.rank.difficulty).toList();

    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No opponents available for this rank.')),
      );
      return;
    }

    final npc = eligible[Random().nextInt(eligible.length)];
    final opponentDeck = Deck(id: npc.id, name: npc.name, cardIds: npc.cardIds);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          playerDeck: playerDeck,
          opponentDeck: opponentDeck,
          opponentName: npc.name,
          opponentPortrait: npc.portraitAsset,
          opponentVictoryQuote: npc.victoryQuote,
          opponentDefeatQuote: npc.defeatQuote,
        ),
      ),
    );
  }
}

// ── Reusable info box ──

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: iconColor, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({required this.label, this.detail, this.icon});
  final String label;
  final String? detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white38, size: 16),
            const SizedBox(width: 8),
          ],
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Text(detail!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
