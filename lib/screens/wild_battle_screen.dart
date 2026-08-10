import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/player_profile_controller.dart';
import '../app/story_progress_controller.dart';
import '../models/card_growth.dart';
import '../models/card_values.dart';
import '../models/condition.dart';
import '../models/deck.dart';
import '../models/story_location.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../services/dialogue_repository.dart';
import '../services/item_repository.dart';
import '../widgets/obtained_banner.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/pressable_button.dart';
import '../widgets/toast.dart';
import '../widgets/triad_card_view.dart';
import 'battle_screen.dart';
import 'coin_flip_screen.dart';
import 'location_missions_screen.dart';
import 'oaks_lab_screen.dart';
import 'poke_mart_screen.dart';
import 'pokemon_center_screen.dart';
import 'route_battle_screen.dart';
import 'shop_screen.dart';
import '../widgets/pressable_button.dart';
import '../models/quest.dart';

class WildBattleLocationScreen extends StatefulWidget {
  const WildBattleLocationScreen({super.key});

  @override
  State<WildBattleLocationScreen> createState() => _WildBattleLocationScreenState();
}

class _WildBattleLocationScreenState extends State<WildBattleLocationScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _questPanelCtrl;
  late final Animation<Offset> _questSlide;
  bool _questPanelOpen = false;

  @override
  void initState() {
    super.initState();
    _questPanelCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _questSlide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: _questPanelCtrl, curve: Curves.easeOutCubic));
    // Fire-and-forget: notifyListeners() fires after _loadRoutes() within initialize(),
    // which triggers context.watch<> rebuild. Don't await — _syncProgress() may hang.
    context.read<StoryProgressController>().initialize();
  }

  @override
  void dispose() {
    _questPanelCtrl.dispose();
    super.dispose();
  }

  void _toggleQuestPanel() {
    if (_questPanelOpen) {
      _questPanelCtrl.reverse().then((_) => setState(() => _questPanelOpen = false));
    } else {
      setState(() => _questPanelOpen = true);
      _questPanelCtrl.forward(from: 0);
    }
  }

  static const _imageMap = {
    'pallet_town': 'assets/locations/pallet.png',
    'route_1': 'assets/locations/route1.png',
    'viridian_city': 'assets/locations/viridian.png',
    'route_22': 'assets/locations/route22.png',
    'route_2': 'assets/locations/route2.png',
    'viridian_forest': 'assets/locations/viridianforest.png',
    'pewter_city': 'assets/locations/pewter.png',
    'route_3': 'assets/locations/route3.png',
    'mt_moon': 'assets/locations/mtmoon.png',
    'route_4': 'assets/locations/route4.png',
    'cerulean_city': 'assets/locations/oakslab.png',
    'route_24': 'assets/locations/kanto.png',
    'route_25': 'assets/locations/kanto.png',
    'route_5': 'assets/locations/kanto.png',
    'route_6': 'assets/locations/kanto.png',
    'vermilion_city': 'assets/locations/oakslab.png',
    'route_11': 'assets/locations/kanto.png',
    'route_9': 'assets/locations/kanto.png',
    'route_10': 'assets/locations/kanto.png',
    'rock_tunnel': 'assets/locations/kanto.png',
    'lavender_town': 'assets/locations/oakslab.png',
    'route_8': 'assets/locations/kanto.png',
    'route_7': 'assets/locations/kanto.png',
    'celadon_city': 'assets/locations/oakslab.png',
    'route_16': 'assets/locations/kanto.png',
    'route_17': 'assets/locations/kanto.png',
    'route_18': 'assets/locations/kanto.png',
    'fuchsia_city': 'assets/locations/oakslab.png',
    'route_15': 'assets/locations/kanto.png',
    'route_14': 'assets/locations/kanto.png',
    'route_13': 'assets/locations/kanto.png',
    'route_12': 'assets/locations/kanto.png',
    'saffron_city': 'assets/locations/oakslab.png',
    'route_19': 'assets/locations/kanto.png',
    'route_20': 'assets/locations/kanto.png',
    'seafoam_islands': 'assets/locations/kanto.png',
    'cinnabar_island': 'assets/locations/oakslab.png',
    'pokemon_mansion': 'assets/locations/kanto.png',
    'route_21': 'assets/locations/kanto.png',
    'route_23': 'assets/locations/kanto.png',
    'victory_road': 'assets/locations/kanto.png',
    'indigo_plateau': 'assets/locations/oakslab.png',
  };

  static const _todLocations = {
    'pallet_town', 'route_1', 'viridian_city', 'route_22', 'route_2',
    'viridian_forest', 'pewter_city', 'route_3', 'mt_moon', 'route_4',
  };

  String _imageFor(String id) {
    final base = _imageMap[id] ?? 'assets/locations/kanto.png';
    if (!_todLocations.contains(id)) return base;
    final tod = currentTimeOfDay;
    if (tod == EncounterTimeOfDay.day) return base;
    final suffix = tod == EncounterTimeOfDay.morning ? '-morning' : '-night';
    final dot = base.lastIndexOf('.');
    return '${base.substring(0, dot)}$suffix${base.substring(dot)}';
  }

  bool _hasWildEncounters(StoryLocation loc) {
    for (final node in loc.nodes) {
      if ((node.type == StoryNodeType.wild || node.type == StoryNodeType.wildBoss) &&
          node.encounterTable != null && node.encounterTable!.isNotEmpty) return true;
    }
    return false;
  }

  List<String> _speciesFrom(StoryLocation loc) {
    final cardIds = <String>{};
    for (final node in loc.nodes) {
      if (node.encounterTable != null) {
        for (final entry in node.encounterTable!) { cardIds.add(entry.cardId); }
      }
    }
    return _cardIdsToNames(cardIds);
  }

  List<String> _cardIdsToNames(Set<String> cardIds) => cardIds.map((cid) {
    final card = CardRepository.instance.cardById(cid);
    return card?.name ?? cid.replaceAll('card_', '').replaceAll('_1', '');
  }).toList();

  int _dayCount(StoryLocation loc) {
    final s = <String>{};
    for (final n in loc.nodes) {
      if (n.encounterTable == null) continue;
      for (final e in n.encounterTable!) {
        if (e.timeOfDay == EncounterTimeOfDay.both || e.timeOfDay == EncounterTimeOfDay.day) s.add(e.cardId);
      }
    }
    return s.length;
  }

  List<String> _exclusiveFor(StoryLocation loc, EncounterTimeOfDay tod) {
    final s = <String>{};
    for (final n in loc.nodes) {
      if (n.encounterTable == null) continue;
      for (final e in n.encounterTable!) { if (e.timeOfDay == tod) s.add(e.cardId); }
    }
    return _cardIdsToNames(s);
  }

  bool _isRoute(StoryLocation loc) => _hasWildEncounters(loc) && loc.wildLevelRange.max > 0;

  void _travelTo(String locationId, String name, String imageAsset, List<String> species, String? levelRange, bool hasGym, bool hasMart, bool hasCenter, bool hasLab, String? gymNpcId) {
    final pCtrl = context.read<PlayerProfileController>();
    pCtrl.profile.location = name;
    pCtrl.notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString('playerLocation', name));
    // Auto-complete quest objectives for traveling
    if (name == 'Viridian City') pCtrl.completeObjective('Travel to Viridian City');
    setState(() {});
    _openDetail(locationId, name, imageAsset, species, levelRange, hasGym, hasMart, hasCenter, hasLab, gymNpcId);
  }

  void _goToLocation(String locationId, String name, String imageAsset, List<String> species, String? levelRange, bool hasGym, bool hasMart, bool hasCenter, bool hasLab, String? gymNpcId) {
    _openDetail(locationId, name, imageAsset, species, levelRange, hasGym, hasMart, hasCenter, hasLab, gymNpcId);
  }

  void _openDetail(String locationId, String name, String imageAsset, List<String> species, String? levelRange, bool hasGym, bool hasMart, bool hasCenter, bool hasLab, String? gymNpcId) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => WildBattleDetailScreen(
      locationId: locationId, locationName: name, imageAsset: imageAsset, species: species, levelRange: levelRange,
      hasGym: hasGym, hasMart: hasMart, hasCenter: hasCenter, hasLab: hasLab, gymNpcId: gymNpcId)));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<StoryProgressController>();
    final pCtrl = context.watch<PlayerProfileController>();
    final trainerLevel = pCtrl.trainerLevel;
    final all = ctrl.locations;
    final unlocked = ctrl.unlockedLocations;

    // Parse gate strings: "trainerLevel:N", "badge:ID", "any:A|B"
    ({int? level, String? badge}) parseGate(String? req) {
      if (req == null) return (level: null, badge: null);
      if (req.startsWith('any:')) {
        final parts = req.substring(4).split('|');
        int? lv; String? bg;
        for (final p in parts) {
          if (p.startsWith('trainerLevel:')) lv = int.tryParse(p.substring(13));
          if (p.startsWith('badge:')) bg = p.substring(6);
        }
        return (level: lv, badge: bg);
      }
      if (req.startsWith('trainerLevel:')) return (level: int.tryParse(req.substring(13)), badge: null);
      if (req.startsWith('badge:')) return (level: null, badge: req.substring(6));
      return (level: null, badge: null);
    }
    String badgeName(String b) => b.replaceAll('_',' ').split(' ').map((w)=>w.isNotEmpty?'${w[0].toUpperCase()}${w.substring(1)}':'').join(' ');

    if (all.isEmpty) {
      return Scaffold(backgroundColor: const Color(0xFF2D2E35), appBar: AppBar(backgroundColor: const Color(0xFF282A30), elevation: 0, title: const Text('KANTO', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 3)), centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context))), body: const Center(child: CircularProgressIndicator(color: Colors.white24)));
    }

    return Stack(children: [
      Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      appBar: AppBar(backgroundColor: const Color(0xFF33343C), elevation: 0, title: const Text('KANTO', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 3)), centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context)), actions: [IconButton(icon: const Icon(Icons.restart_alt, color: Colors.white24, size: 20), tooltip: 'Reset progression', onPressed: () async {
        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF282A30), title: const Text('Reset Progression?', style: TextStyle(color: Colors.white)), content: const Text('Return to Pallet Town and start over.', style: TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset', style: TextStyle(color: Colors.redAccent)))],));
        if (ok == true && context.mounted) { final sp = await SharedPreferences.getInstance(); await sp.remove('unlockedLocations'); await sp.remove('story_progress'); await sp.remove('activeQuests'); await sp.remove('completedQuests'); await sp.setString('playerLocation', 'Pallet Town'); context.read<StoryProgressController>().resetProgression(); final pc = context.read<PlayerProfileController>(); pc.profile.location = 'Pallet Town'; pc.clearQuests(); pc.notifyListeners(); if (context.mounted) setState(() {}); }
      })]),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), itemCount: all.length,
        itemBuilder: (ctx, i) {
          final loc = all[i];
          final gate = parseGate(loc.unlockRequirement);
          final badgeLocked = gate.badge != null && !pCtrl.badges.contains(gate.badge);
          final lvLocked = gate.level != null && trainerLevel < gate.level!;
          final isAny = loc.unlockRequirement?.startsWith('any:') == true;
          final gated = isAny ? (badgeLocked && lvLocked) : (badgeLocked || lvLocked);
          final locked = !unlocked.contains(loc.id) || gated;
          final isRoute = _isRoute(loc);
          final species = _speciesFrom(loc);
          final dayCnt = _dayCount(loc);
          final morningOnly = _exclusiveFor(loc, EncounterTimeOfDay.morning);
          final nightOnly = _exclusiveFor(loc, EncounterTimeOfDay.night);
          final lv = loc.wildLevelRange.max > 0 ? '${loc.wildLevelRange.min}–${loc.wildLevelRange.max}' : null;
          bool hasGym = false, hasMart = false, hasCenter = false, hasLab = false; String? gymNpcId;
          for (final n in loc.nodes) {
            if (n.npcId != null) { hasGym = true; gymNpcId = n.npcId; }
            if (n.id.contains('pokemart') || n.id.contains('mart')) hasMart = true;
            if (n.id.contains('center')) hasCenter = true;
            if (n.id.contains('oaks_lab') || n.id.contains('lab')) hasLab = true;
          }
          String? lockReason;
          if (gated) {
            if (isAny) lockReason = 'Requires ${gate.badge != null ? badgeName(gate.badge!) + (gate.level != null ? ' or ' : '') : ''}${gate.level != null ? 'TL ${gate.level}' : ''}';
            else if (badgeLocked) lockReason = 'Requires ${badgeName(gate.badge!)}';
            else lockReason = 'Requires Trainer Level ${gate.level}';
          }
          final isCurrent = pCtrl.profile.location == loc.name || pCtrl.profile.location == loc.id;
          final completionTxt = (loc.completionRule.type != CompletionRuleType.defeatAll)
              ? ctrl.completionProgressText(loc.id)
              : null;
          return _LocationCard(id: loc.id, name: loc.name, imageAsset: _imageFor(loc.id),
            species: species, dayCount: dayCnt, morningOnly: morningOnly, nightOnly: nightOnly, levelRange: lv, locked: locked, isRoute: isRoute,
            hasGym: hasGym, hasMart: hasMart, hasCenter: hasCenter, hasLab: hasLab, gymNpcId: gymNpcId,
            lockReason: lockReason, reqLevel: gate.level, completionText: completionTxt, isCurrent: isCurrent, isBoy: pCtrl.profile.gender == 'boy',
            onTap: isCurrent
                ? () => _goToLocation(loc.id, loc.name, _imageFor(loc.id), species, lv, hasGym, hasMart, hasCenter, hasLab, gymNpcId)
                : () => _travelTo(loc.id, loc.name, _imageFor(loc.id), species, lv, hasGym, hasMart, hasCenter, hasLab, gymNpcId));
        },
      ),
    ),
    // Quest panel — slides in from right
    if (_questPanelOpen || _questPanelCtrl.isAnimating)
      Positioned(
        top: kToolbarHeight + MediaQuery.of(context).padding.top + 8,
        right: 0, bottom: 0,
        width: 280,
        child: SlideTransition(
          position: _questSlide,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF282A30),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              border: Border(left: BorderSide(color: const Color(0xFF4CAF50).withValues(alpha: 0.3), width: 2)),
            ),
            child: SafeArea(
              top: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    const Icon(Icons.assignment, color: Colors.white54, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Quests', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, decoration: TextDecoration.none))),
                    GestureDetector(
                      onTap: _toggleQuestPanel,
                      child: const Icon(Icons.close, color: Colors.white38, size: 20),
                    ),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(children: [
                      if (pCtrl.activeQuests.where((q) => !q.completed).isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text('No Quests', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14, decoration: TextDecoration.none)),
                        )
                      else
                        for (final q in pCtrl.activeQuests.where((q) => !q.completed))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildQuestSlideCard(q),
                          ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    // Floating quest button — bottom right
    Positioned(
      bottom: 16, right: 16,
      child: PressableButton(
        onTap: _toggleQuestPanel,
        child: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF3A3C44),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
          ),
          child: const Icon(Icons.assignment, color: Colors.white, size: 24),
        ),
      ),
    ),
  ]);
  }


  Widget _buildQuestSlideCard(Quest quest) {
    final progress = quest.objectives.isNotEmpty ? quest.doneCount / quest.objectives.length : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(quest.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.white.withValues(alpha: 0.08), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50))),
      ),
      const SizedBox(height: 4),
      Text('${quest.doneCount}/${quest.objectives.length} objectives', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, decoration: TextDecoration.none)),
      const SizedBox(height: 12),
      for (final obj in quest.objectives)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(obj.completed ? Icons.check_circle : Icons.radio_button_unchecked, color: obj.completed ? const Color(0xFF4CAF50) : Colors.white30, size: 16),
            const SizedBox(width: 10),
            Flexible(child: Text(obj.description, style: TextStyle(color: obj.completed ? Colors.white38 : Colors.white70, fontSize: 13, decoration: TextDecoration.none))),
          ]),
        ),
      if (quest.rewardMoney > 0 || quest.id == 'oaks_parcel') ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF282A30),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.card_giftcard, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Text('₽${quest.rewardMoney}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
            ]),
            _buildQuestRewardItems(quest.id),
          ]),
        ),
      ],
    ]),
    );
  }
  Widget _buildQuestRewardItems(String questId) {
    final detail = QuestData.questDetail(questId);
    if (detail == null) return const SizedBox.shrink();
    final items = detail['rewardItems'] as List? ?? [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final item in items) _buildRewardRow(item as Map<String, dynamic>),
      ]),
    );
  }

  Widget _buildRewardRow(Map<String, dynamic> itemMap) {
    final itemId = itemMap['id'] as String? ?? '';
    final qty = itemMap['quantity'] as int? ?? 1;
    if (itemId.startsWith('card_')) {
      final card = CardRepository.instance.cardById(itemId);
      if (card == null) return const SizedBox.shrink();
      final level = itemMap['level'] as int? ?? card.baseLevel ?? 1;
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          SizedBox(width: 24, height: 24, child: TriadCardView(card: card, size: 24, showCondition: false)),
          const SizedBox(width: 6),
          Text('${card.name} Lv.$level - x $qty', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
        ]),
      );
    }
    final imgPath = ItemRepository().itemById(itemId)?.imageAsset ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        if (imgPath.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 6), child: Image.asset(imgPath, width: 16, height: 16)),
        Text('x $qty', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
      ]),
    );
  }}

// ── Location card ──

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.id, required this.name, required this.imageAsset, required this.species, required this.dayCount, required this.morningOnly, required this.nightOnly, required this.levelRange, required this.locked, required this.isRoute, this.hasGym = false, this.hasMart = false, this.hasCenter = false, this.hasLab = false, this.gymNpcId, this.lockReason, this.reqLevel, this.completionText, this.isCurrent = false, this.isBoy = true, this.onTap});
  final String id, name, imageAsset;
  final List<String> species;
  final int dayCount;
  final List<String> morningOnly;
  final List<String> nightOnly;
  final String? levelRange, lockReason, completionText;
  final int? reqLevel;
  final bool locked, isRoute, hasGym, hasMart, hasCenter, hasLab;
  final String? gymNpcId;
  final bool isCurrent, isBoy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableButton(
        onTap: locked
            ? () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lockReason ?? 'Locked — complete the previous location first.'), duration: const Duration(seconds: 1)))
            : (onTap ?? () {}),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E1E1E), Color(0xFF181818)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: locked ? const Color(0xFF333333) : const Color(0xFF444444)),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
              child: Stack(children: [
                ColorFiltered(
                  colorFilter: locked ? const ColorFilter.mode(Colors.grey, BlendMode.saturation) : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                  child: Image.asset(imageAsset, width: 100, height: 90, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(width: 100, height: 90, color: Colors.white.withValues(alpha: 0.05), child: const Icon(Icons.landscape, color: Colors.white24))),
                ),
                if (isCurrent && !locked)
                  Positioned(top: 4, left: 4, child: Image.asset('assets/ui/Town Map/player_POKEMONTRAINER_${isBoy ? 'Red' : 'Leaf'}.png', width: 28, height: 28)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(name, style: TextStyle(color: locked ? Colors.white38 : Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                    child: Text(isRoute ? 'ROUTE' : 'TOWN', style: TextStyle(color: locked ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.5), fontSize: 9, fontWeight: FontWeight.w700))),
                  if (locked) ...[const SizedBox(width: 8), const Icon(Icons.lock, color: Colors.white24, size: 16)],
                ]),
                const SizedBox(height: 6),
                if (locked && lockReason != null)
                  Text(lockReason!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600))
                else if (locked)
                  Text('Complete previous location to unlock', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12))
                else if (species.isNotEmpty)
                  _buildTimeBadge(dayCount, morningOnly, nightOnly)
                else if (!isRoute)
                  Text('Pok\u00e9 Mart \u2022 Pok\u00e9mon Center', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                if (completionText != null && !locked) ...[
                  const SizedBox(height: 2),
                  Text(completionText!, style: TextStyle(color: const Color(0xFF66BB6A).withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600)),
                ],
                if (reqLevel != null && !locked) ...[
                  const SizedBox(height: 2),
                  Text('Required: TL $reqLevel', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
                ],
              ]),
            )),
            Padding(padding: const EdgeInsets.only(right: 12), child: Icon(locked ? Icons.lock : Icons.chevron_right, color: locked ? Colors.white12 : Colors.white38)),
          ]),
        ),
      ),
    );
  }

  static Widget _buildTimeBadge(int dayCnt, List<String> morningOnly, List<String> nightOnly) {
    final w = <Widget>[];
    w.add(Text('\u2600 $dayCnt', style: TextStyle(color: const Color(0xFFFFCA28).withValues(alpha: 0.7), fontSize: 12)));
    if (morningOnly.isNotEmpty) { w.add(const SizedBox(width: 8)); w.add(Text('\uD83C\uDF05 ${morningOnly.length}', style: TextStyle(color: const Color(0xFFFFCA28).withValues(alpha: 0.7), fontSize: 12))); }
    if (nightOnly.isNotEmpty) { w.add(const SizedBox(width: 8)); w.add(Text('\uD83C\uDF19 ${nightOnly.length}', style: TextStyle(color: const Color(0xFF7C8DFF).withValues(alpha: 0.7), fontSize: 12))); }
    return Row(children: w);
  }
}

// ── Location detail screen ──

Future<void> _openPokeMart(BuildContext context, String locationId, String locationName) async {
  final pc = context.read<PlayerProfileController>();
  if (locationId == 'viridian_city' && pc.isQuestActive('oaks_parcel')) {
    final alreadyPickedUp = pc.activeQuests
        .firstWhere((q) => q.id == 'oaks_parcel')
        .objectives
        .any((o) => o.description == 'Pick up the parcel at Viridian PokéMart' && o.completed);
    if (!alreadyPickedUp) {
      final d = DialogueRepository.instance.npcScene('pokemart_clerk', 'oaks_parcel_delivery');
      final portraitPath = d['portrait'] as String? ?? 'SHOPKEEPER.png';
      await showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        builder: (ctx) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ParchmentDialog(
              portrait: Image.asset('assets/trainers/npc/$portraitPath', height: 180, fit: BoxFit.contain),
              dialogue: d['dialogue'] as String? ?? '',
              pages: d['pages'] as List<String>?,
              speaker: d['speaker'] as String? ?? 'Store Clerk',
              actionLabel: d['actionLabel'] as String? ?? 'Take Parcel',
              actionColor: d['actionColor'] as Color? ?? const Color(0xFF4CAF50),
              onAction: () {
                pc.addConsumable('oaks_parcel');
                pc.completeObjective('Pick up the parcel at Viridian PokéMart');
                pc.completeObjective('Travel to Viridian City');
                Navigator.pop(ctx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    ObtainedBanner.showObtained(context, itemName: "Oak's Parcel");
                  }
                });
              },
            ),
          ),
        ),
      );
      return;
    }
  }
  if (context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PokeMartScreen(locationName: locationName)));
  }
}

class WildBattleDetailScreen extends StatelessWidget {
  const WildBattleDetailScreen({super.key, required this.locationId, required this.locationName, required this.imageAsset, required this.species, required this.levelRange, this.hasGym = false, this.hasMart = false, this.hasCenter = false, this.hasLab = false, this.gymNpcId});
  final String locationId, locationName, imageAsset;
  final List<String> species;
  final String? levelRange;
  final bool hasGym, hasMart, hasCenter, hasLab;
  final String? gymNpcId;

  @override
  Widget build(BuildContext context) {
    final storyCtrl = context.watch<StoryProgressController>();
    final loc = storyCtrl.locations.where((l) => l.id == locationId).firstOrNull;
    final hasRule = loc != null && loc.completionRule.type != CompletionRuleType.defeatAll;
    final profileCtrl = context.read<PlayerProfileController>();
    final parcelDone = profileCtrl.isQuestCompleted('oaks_parcel');
    final progText = hasRule ? storyCtrl.completionProgressText(locationId) : null;
    final progFrac = hasRule ? storyCtrl.completionFor(locationId) : 0.0;
    final showProgress = hasRule && !(locationId == 'route_1' && parcelDone);
    final total = species.length;
    return Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      appBar: AppBar(backgroundColor: const Color(0xFF33343C), elevation: 0, title: Text(locationName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 4)), centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context))),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset(imageAsset, width: double.infinity, height: 140, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(height: 140, color: Colors.white.withValues(alpha: 0.05), child: const Icon(Icons.landscape, color: Colors.white24, size: 48)))),
          const SizedBox(height: 16),
          if (showProgress) ...[
            _buildProgressBar(progText!, progFrac),
            const SizedBox(height: 12),
          ],
          if (species.isNotEmpty) ...[
            // Species Found
            _buildSpeciesFound(context, locationId),
            const SizedBox(height: 20),
            _BattleModeButton(
              icon: Icons.grass,
              imageIcon: Image.asset('assets/ui/grass.png', width: 36, height: 36),
              label: 'Search Nearby Grass',
              subtitle: 'Look for wild $locationName Pokémon.',
              color: const Color(0xFF4CAF50),
              onTap: () {
                final deck = profileCtrl.profile.defaultDeck ?? profileCtrl.profile.decks.where((d) => d.isValid).firstOrNull;
                if (deck == null) return;
                final growth = profileCtrl.cardGrowth;
                final byInstance = profileCtrl.cardGrowthByInstance;
                final repo = CardRepository.instance;
                final unusableCards = <TriadCard>[];
                final unusableGrowths = <CardGrowth>[];
                final unusable = <String>[];
                for (var i = 0; i < deck.cardIds.length; i++) {
                  final cardId = deck.cardIds[i];
                  final instId = deck.instanceIds != null && i < deck.instanceIds!.length ? deck.instanceIds![i] : null;
                  int? cond;
                  CardGrowth? instGrowth;
                  if (instId != null) {
                    instGrowth = byInstance[instId];
                    cond = instGrowth?.condition;
                  }
                  cond ??= growth[cardId]?.condition;
                  if (cond != null && cond <= 0) {
                    final c = repo.cardById(cardId);
                    if (c != null) {
                      unusableCards.add(c);
                      unusableGrowths.add(instGrowth ?? growth[cardId]!);
                      unusable.add(c.name);
                    }
                  }
                }
                if (unusable.isNotEmpty) {
                  showDialog(
                    context: context,
                    barrierColor: Colors.black.withValues(alpha: 0.85),
                    builder: (ctx) => Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                        decoration: BoxDecoration(
                          color: const Color(0xDD1F2027),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.25)),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9800), size: 40),
                          const SizedBox(height: 12),
                          const Text('UNUSABLE POKÉMON', style: TextStyle(
                            fontFamily: 'PowerGreen',
                            color: Color(0xFFFF9800),
                            fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2,
                            decoration: TextDecoration.none,
                          )),
                          const SizedBox(height: 16),
                          // Show damaged cards
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(unusableCards.length, (i) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: TriadCardView(card: unusableCards[i], size: 64, showCondition: true, growth: unusableGrowths[i]),
                            )),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            unusable.length == 1
                                ? '${unusable.first} is too damaged to battle.'
                                : '${unusable.length} cards are too damaged to battle.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Visit a Pokémon Center, use healing items, or replace them in your deck to proceed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54, fontSize: 12, decoration: TextDecoration.none),
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                              ),
                              child: const Text('OK', textAlign: TextAlign.center, style: TextStyle(
                                fontFamily: 'PowerGreen',
                                color: Colors.white,
                                fontSize: 14, fontWeight: FontWeight.w700, decoration: TextDecoration.none,
                              )),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                  return;
                }
                _searchGrass(context, locationId, locationName);
              },
            ),
            const Spacer(),
          ] else ...[
            const SizedBox(height: 8),
            if (hasGym) ...[
              _BattleModeButton(icon: Icons.emoji_events, label: 'Gym Leader', subtitle: gymNpcId != null ? 'Challenge ${gymNpcId![0].toUpperCase()}${gymNpcId!.substring(1)} to earn a badge.' : 'Challenge the Gym Leader.', color: const Color(0xFFFFCA28), onTap: () => _snack(context, 'Gym Battle — Coming soon!')),
              const SizedBox(height: 10),
            ],
            if (hasLab) ...[
              _BattleModeButton(icon: Icons.science, label: "Oak's Lab", subtitle: 'Visit Professor Oak for research and quests.', color: const Color(0xFF66BB6A), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OaksLabScreen()))),
              const SizedBox(height: 10),
            ],
            if (hasCenter) ...[
              _BattleModeButton(icon: Icons.local_hospital, label: 'Pokémon Center', subtitle: 'Heal your Pokémon and rest.', color: const Color(0xFFEF5350), onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PokemonCenterScreen()));
              }),
              const SizedBox(height: 10),
            ],
            if (hasMart) ...[
              _BattleModeButton(icon: Icons.store, label: 'Poké Mart', subtitle: 'Browse cards, boosters, and consumables.', color: const Color(0xFF42A5F5), onTap: () {
                _openPokeMart(context, locationId, locationName);
              }),
              const SizedBox(height: 10),
            ],
            _BattleModeButton(icon: Icons.assignment, label: 'Quests', subtitle: 'Available quests and objectives.', color: const Color(0xFFAB47BC),
              badge: _questBadge(context, locationId),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => LocationMissionsScreen(locationId: locationId)));
              },
              onLongPress: () => _resetParcelQuest(context),
            ),
            // Fishing button — only in fishing locations when player has a rod
            if (_canFishHere(locationId, context)) ...[
              const SizedBox(height: 10),
              _BattleModeButton(icon: Icons.water, label: 'Cast a Line', subtitle: _rodName(context), color: const Color(0xFF42A5F5), onTap: () {
                final deck = profileCtrl.profile.defaultDeck ?? profileCtrl.profile.decks.where((d) => d.isValid).firstOrNull;
                if (deck == null) return;
                final instances = profileCtrl.allCardInstances;
                final unusable = <String>[];
                for (final cardId in deck.cardIds) {
                  final mine = instances.where((i) => i.cardId == cardId).toList();
                  if (mine.isNotEmpty && mine.every((i) => i.conditionTier == ConditionTier.unusable)) {
                    final c = CardRepository.instance.cardById(cardId);
                    unusable.add(c?.name ?? cardId);
                  }
                }
                if (unusable.isNotEmpty) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF282A30),
                      title: const Text('Unusable Cards', style: TextStyle(color: Colors.white)),
                      content: Text('${unusable.length} card(s) cannot battle:\n${unusable.join(", ")}', style: const TextStyle(color: Colors.white70)),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                    ),
                  );
                  return;
                }
                _startFishingEncounter(context, locationId, locationName);
              }),
            ],
            const Spacer(),
          ],
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  static void _startRandomWildBattle(BuildContext context, String locationId, String locationName) {
    final storyCtrl = context.read<StoryProgressController>();
    final profileCtrl = context.read<PlayerProfileController>();
    final location = storyCtrl.locations.firstWhere((l) => l.id == locationId);

    // Find the first wild node with an encounter table
    StoryNode? wildNode;
    for (final node in location.nodes) {
      if (node.encounterTable != null && node.encounterTable!.isNotEmpty) {
        wildNode = node;
        break;
      }
    }

    if (wildNode == null) {
      _snack(context, 'No wild encounters at this location.');
      return;
    }

    // Get player deck
    final profile = profileCtrl.profile;
    Deck? playerDeck = profile.defaultDeck;
    playerDeck ??= profile.decks.where((d) => d.isValid).firstOrNull;
    if (playerDeck == null) {
      _snack(context, 'You need a 5-card deck before battling.');
      return;
    }

    // Check for unusable cards
    if (_checkUnusableDeck(context, profileCtrl, playerDeck)) return;

    // Roll a random encounter (weighted)
    final card = _rollEncounter(wildNode.encounterTable!);
    final lvRange = location.wildLevelRange;
    final rng = Random();

    // Mark this card as seen in the Pokédex
    profileCtrl.markCardSeen(card.id);

    // Build 5 wild cards with random levels and shiny chance
    final wildCards = <TriadCard>[];
    for (var i = 0; i < 5; i++) {
      final level = lvRange.min + rng.nextInt(lvRange.max - lvRange.min + 1);
      final isShiny = rng.nextInt(16) == 0;

      // Base stats: same as the card (no bonus for levels <= 5).
      // Level > 5: 10% chance per extra level of +1 to a random direction.
      var bonusN = 0, bonusS = 0, bonusE = 0, bonusW = 0;
      final extraLevels = level - 5;
      for (var j = 0; j < extraLevels; j++) {
        if (rng.nextInt(10) == 0) {
          switch (rng.nextInt(4)) {
            case 0: bonusN++; break;
            case 1: bonusS++; break;
            case 2: bonusE++; break;
            case 3: bonusW++; break;
          }
        }
      }
      final bonus = CardValues(north: bonusN, south: bonusS, east: bonusE, west: bonusW);

      wildCards.add(card.copyWith(
        values: card.values.plusBonus(bonus),
        shiny: isShiny || card.shiny,
        baseLevel: level,
        condition: rollWildCondition(rng), // GDD §19 — not every encounter is Mint
      ));
    }

    final wildDeck = Deck(
      id: 'wild_${locationId}_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Wild ${card.name}',
      cardIds: List.filled(5, card.id),
      opponentCards: wildCards,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoinFlipScreen(
          opponentName: 'Wild ${card.name}',
          opponentPortrait: card.image,
          onComplete: ({required playerGoesFirst}) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => BattleScreen(
                  playerDeck: playerDeck!,
                  opponentDeck: wildDeck,
                  opponentName: 'Wild ${card.name}',
                  opponentPortrait: null,
                  opponentVictoryQuote: null,
                  opponentDefeatQuote: null,
                  playerGoesFirst: playerGoesFirst,
                  opponentCards: wildCards,
                  onMatchComplete: (won, {capturedCardIds}) {
                    if (won) {
                      final storyCtrl = context.read<StoryProgressController>();
                      storyCtrl.recordBattleWin(locationId);
                      final loc = storyCtrl.locations.firstWhere((l) => l.id == locationId);
                      for (final node in loc.nodes) {
                        if (node.type == StoryNodeType.wild && !node.isCompleted) {
                          storyCtrl.completeNode(locationId, node.id);
                          break;
                        }
                      }
                    }
                  },
                  onContinue: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static TriadCard _rollEncounter(List<WildEncounterEntry> table) {
    final totalWeight = table.fold<int>(0, (sum, e) => sum + e.weight);
    var roll = Random().nextInt(totalWeight);
    for (final entry in table) {
      roll -= entry.weight;
      if (roll < 0) {
        return CardRepository.instance.cardById(entry.cardId) ??
            TriadCard.fallback();
      }
    }
    return CardRepository.instance.cardById(table.first.cardId) ??
        TriadCard.fallback();
  }

  static void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));

  static Widget _buildSpeciesFound(BuildContext context, String locationId) {
    final profileCtrl = context.watch<PlayerProfileController>();
    final storyCtrl = context.watch<StoryProgressController>();
    final loc = storyCtrl.locations.where((l) => l.id == locationId).firstOrNull;
    final owned = profileCtrl.profile.ownedCardIds;
    final seen = profileCtrl.seenCardIds;
    final repo = CardRepository.instance;
    final tod = currentTimeOfDay;

    final active = <String>{};
    if (loc != null) {
      for (final node in loc.nodes) {
        if (node.encounterTable == null) continue;
        for (final e in node.encounterTable!) {
          if (e.timeOfDay == EncounterTimeOfDay.both || e.timeOfDay == tod) {
            active.add((repo.cardById(e.cardId)?.name ?? e.cardId).toUpperCase());
          }
        }
      }
    }
    if (active.isEmpty) return const SizedBox.shrink();

    final (icon, color, label) = switch (tod) {
      EncounterTimeOfDay.morning => (Icons.wb_twilight, const Color(0xFFFFCA28), 'Active Now (Morning)'),
      EncounterTimeOfDay.day => (Icons.wb_sunny, const Color(0xFF66BB6A), 'Active Now (Day)'),
      EncounterTimeOfDay.night => (Icons.nightlight_round, const Color(0xFF7C8DFF), 'Active Now (Night)'),
      EncounterTimeOfDay.both => (Icons.public, Colors.white54, 'Active Now'),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [Icon(icon, color: color, size: 14), const SizedBox(width: 6), Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w700))]),
      const SizedBox(height: 6),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: active.map((name) {
        final cardId = 'card_${name.toLowerCase()}_1';
        final card = repo.cardById(cardId);
        final captured = card != null && owned.contains(cardId);
        final s = card != null && seen.contains(cardId);
        final iconPath = 'assets/sprites/front/$name.png';
        final c = captured ? Colors.white : s ? Colors.white54 : Colors.white24;
        return Padding(padding: const EdgeInsets.only(right: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: captured ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: captured ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08))),
            child: ClipRRect(borderRadius: BorderRadius.circular(9), child: ColorFiltered(colorFilter: captured ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : s ? const ColorFilter.mode(Colors.grey, BlendMode.saturation) : const ColorFilter.matrix(<double>[0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,1,0]), child: Image.asset(iconPath, width: 48, height: 48, fit: BoxFit.cover, alignment: Alignment.topLeft, errorBuilder: (_, __, ___) => const Icon(Icons.help_outline, color: Colors.white12, size: 20))))),
          const SizedBox(height: 4), Text(s ? name : '???', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
        ]));
      }).toList())),
    ]);
  }

  static Widget _buildProgressBar(String text, double fraction) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFF282A30), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1A1C20))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: SizedBox(height: 6, child: Stack(children: [
          Container(color: Colors.white.withValues(alpha: 0.08)),
          FractionallySizedBox(widthFactor: fraction, child: Container(color: const Color(0xFF4CAF50))),
        ]))),
      ]),
    );
  }

  static void _speciesPicker(BuildContext context, List<String> species) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1A1A2E), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (_) {
      return Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CHOOSE SPECIES', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 3)),
        const SizedBox(height: 16),
        ...species.map((s) => ListTile(leading: const Icon(Icons.catching_pokemon, color: Colors.white54), title: Text(s, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), trailing: const Icon(Icons.chevron_right, color: Colors.white24), onTap: () { Navigator.pop(context); _snack(context, '$s hunt \u2014 Coming soon!'); })),
      ]));
    });
  }

  /// Returns true if the deck has unusable cards and the warning was shown.
  static bool _checkUnusableDeck(BuildContext context, PlayerProfileController pCtrl, Deck deck) {
    final instances = pCtrl.allCardInstances;
    final repo = CardRepository.instance;
    final unusable = <String>[];
    for (final cardId in deck.cardIds) {
      // Find all instances of this card in the player's collection
      final cardInstances = instances.where((i) => i.cardId == cardId).toList();
      // If ALL instances are unusable, the deck slot can't battle
      final hasUsable = cardInstances.any((i) => i.conditionTier != ConditionTier.unusable);
      if (cardInstances.isNotEmpty && !hasUsable) {
        final card = repo.cardById(cardId);
        unusable.add(card?.name ?? cardId);
      }
    }
    if (unusable.isEmpty) return false;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282A30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF1A1C20))),
        title: Row(children: [
          const Icon(Icons.warning_amber, color: Color(0xFFFF9800), size: 24),
          const SizedBox(width: 8),
          const Text('Unusable Cards', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${unusable.length} card${unusable.length > 1 ? 's' : ''} in your deck cannot battle:', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          ...unusable.map((n) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Icon(Icons.close, color: Color(0xFF757575), size: 14),
              const SizedBox(width: 6),
              Text(n, style: const TextStyle(color: Color(0xFF757575), fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          )),
          const SizedBox(height: 12),
          const Text('Visit a Pokémon Center to restore your cards, or use healing items from your bag.', style: TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
    return true;
  }

  // ── Item discovery via Search Nearby Grass ──

  /// Items that can be found per location. Once found, they're consumed.
  static const Map<String, List<String>> _locationItems = {
    'route_1': ['potion', 'potion', 'persim_berry', 'black_apricorn', 'razz_berry'],
  };

  static const Map<String, String> _itemDisplayNames = {
    'potion': 'Potion',
    'persim_berry': 'Persim Berry',
    'black_apricorn': 'Black Apricorn',
    'razz_berry': 'Razz Berry',
  };

  static const Map<String, String> _itemIcons = {
    'potion': 'assets/images/icons/items/item217.png',
    'persim_berry': 'assets/images/icons/items/item396.png',
    'black_apricorn': 'assets/images/icons/items/item027.png',
    'razz_berry': 'assets/images/icons/items/item404.png',
  };

  static Future<String?> _checkGrassItem(String locationId) async {
    final items = _locationItems[locationId];
    if (items == null || items.isEmpty) return null;
    // Low chance to find an item (~10%)
    if (Random().nextDouble() > 0.10) return null;
    final prefs = await SharedPreferences.getInstance();
    final foundKey = 'grass_items_$locationId';
    final found = prefs.getStringList(foundKey) ?? [];
    // Find first unfound item
    for (final item in items) {
      if (!found.contains(item)) {
        found.add(item);
        await prefs.setStringList(foundKey, found);
        return item;
      }
    }
    return null;
  }

  static void _searchGrass(BuildContext context, String locationId, String locationName) async {
    // Quick unusable check before anything else
    final pc = context.read<PlayerProfileController>();
    final profile = pc.profile;
    Deck? playerDeck = profile.defaultDeck;
    playerDeck ??= profile.decks.where((d) => d.isValid).firstOrNull;
    if (playerDeck != null && _checkUnusableDeck(context, pc, playerDeck)) return;

    final item = await _checkGrassItem(locationId);
    if (item != null) {
      final pc = context.read<PlayerProfileController>();
      pc.addConsumable(item);
      final name = _itemDisplayNames[item] ?? item;
      final icon = _itemIcons[item] ?? 'assets/images/icons/items/potion.png';
      if (context.mounted) {
        Toast.show(context, text: 'Found $name!', imagePath: icon);
      }
    } else {
      if (context.mounted) {
        _startRandomWildBattle(context, locationId, locationName);
      }
    }
  }
}

// ── Helpers ──

bool _hasParcelForTurnIn(BuildContext context, String locationId) {
  if (locationId != 'pallet_town') return false;
  final pc = context.read<PlayerProfileController>();
  return pc.itemCount('oaks_parcel') > 0;
}

bool _hasAvailableQuest(BuildContext context, String locationId) {
  if (locationId != 'pallet_town') return false;
  final pc = context.read<PlayerProfileController>();
  return !pc.isQuestActive('oaks_parcel') && !pc.isQuestCompleted('oaks_parcel');
}

Widget? _questBadge(BuildContext context, String locationId) {
  if (_hasParcelForTurnIn(context, locationId)) {
    return Image.asset('assets/ui/exclaim.png', width: 24, height: 24);
  }
  if (_hasAvailableQuest(context, locationId)) {
    return Image.asset('assets/ui/question.png', width: 24, height: 24);
  }
  return null;
}

Future<void> _resetParcelQuest(BuildContext context) async {
  final pc = context.read<PlayerProfileController>();
  pc.uncompleteQuest('oaks_parcel');
  // Ensure quest is active
  if (!pc.isQuestActive('oaks_parcel')) {
    pc.startQuest(QuestData.oaksParcel);
  }
  // Reset objectives
  final activeQuest = pc.activeQuests.firstWhere((q) => q.id == 'oaks_parcel');
  activeQuest.completed = false;
  for (final obj in activeQuest.objectives) {
    if (obj.description == 'Return the parcel to Professor Oak') {
      obj.completed = false;
    }
  }
  // Persist active quests
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('activeQuests', jsonEncode(pc.activeQuests.map((q) => q.toJson()).toList()));
  // Add parcel back
  pc.addConsumable('oaks_parcel');
  pc.notifyListeners();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Parcel quest reset — ready to turn in!'), backgroundColor: Color(0xFF4CAF50)));
  }
}



class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
      child: Column(children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
      ]),
    ));
  }
}


// ── Fishing ──

const _fishingLocations = {'viridian_city'};

bool _canFishHere(String locationId, BuildContext context) {
  if (!_fishingLocations.contains(locationId)) return false;
  final pc = context.read<PlayerProfileController>();
  return pc.itemCount('old_rod') > 0 || pc.itemCount('good_rod') > 0 || pc.itemCount('super_rod') > 0;
}

String _rodName(BuildContext context) {
  final pc = context.read<PlayerProfileController>();
  if (pc.itemCount('super_rod') > 0) return 'Using Super Rod';
  if (pc.itemCount('good_rod') > 0) return 'Using Good Rod';
  return 'Using Old Rod';
}

String _bestRod(BuildContext context) {
  final pc = context.read<PlayerProfileController>();
  if (pc.itemCount('super_rod') > 0) return 'super_rod';
  if (pc.itemCount('good_rod') > 0) return 'good_rod';
  return 'old_rod';
}

void _startFishingEncounter(BuildContext context, String locationId, String locationName) {
  final rod = _bestRod(context);
  final rng = Random();
  String speciesId;
  int level;
  switch (rod) {
    case 'super_rod':
      if (rng.nextDouble() < 0.8) { speciesId = 'poliwag'; level = 40; }
      else { speciesId = 'magikarp'; level = 40; }
      break;
    case 'good_rod':
      if (rng.nextDouble() < 0.6) { speciesId = 'poliwag'; level = 20; }
      else { speciesId = 'magikarp'; level = 20; }
      break;
    default:
      if (rng.nextDouble() < 0.15) { speciesId = 'poliwag'; level = 10; }
      else { speciesId = 'magikarp'; level = 10; }
      break;
  }
  final cards = CardRepository.instance.allCards.where((c) => c.speciesId == speciesId).toList();
  if (cards.isEmpty) return;
  final card = cards.first;
  final wildCard = card.copyWith(baseLevel: level, condition: rollWildCondition(rng));
  final wildDeck = Deck(id: 'fish_$speciesId', name: 'Wild ${card.name}', cardIds: List.filled(5, card.id), opponentCards: List.filled(5, wildCard));
  final profile = context.read<PlayerProfileController>().profile;
  Deck? playerDeck = profile.defaultDeck;
  playerDeck ??= profile.decks.where((d) => d.isValid).firstOrNull;
  if (playerDeck == null) return;
  // Check for unusable cards
  if (WildBattleDetailScreen._checkUnusableDeck(context, context.read<PlayerProfileController>(), playerDeck)) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => CoinFlipScreen(
    opponentName: 'Wild ${card.name}',
    opponentPortrait: card.image,
    background: 'assets/ui/bg_wildgrass.png',
    onComplete: ({required playerGoesFirst}) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BattleScreen(
        playerDeck: playerDeck!,
        opponentDeck: wildDeck,
        opponentName: 'Wild ${card.name}',
        opponentPortrait: null,
        playerGoesFirst: playerGoesFirst,
        onMatchComplete: (won, {capturedCardIds}) {},
        onContinue: () => Navigator.of(context).popUntil((route) => route.isFirst),
      )));
    },
  )));
}



class _BattleModeButton extends StatelessWidget {
  const _BattleModeButton({required this.icon, this.imageIcon, required this.label, required this.subtitle, required this.color, this.locked = false, this.lockLabel, this.badge, this.onTap, this.onLongPress});
  final IconData icon;
  final Widget? imageIcon;
  final String label, subtitle;
  final Color color;
  final bool locked;
  final String? lockLabel;
  final Widget? badge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final disabled = locked;
    final child = PressableButton(
      onTap: disabled ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Locked — complete location objectives to unlock.'), duration: Duration(seconds: 1))) : (onTap ?? () {}),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF282A30), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF1A1C20))),
          child: Row(children: [
            if (imageIcon != null)
              imageIcon!
            else
              Container(width: 36, height: 36, decoration: BoxDecoration(color: disabled ? Colors.white.withValues(alpha: 0.04) : color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: disabled ? Colors.white24 : color, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: disabled ? Colors.white38 : Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: disabled ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.4), fontSize: 11)),
            ])),
            if (!disabled) Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.25), size: 20),
          ]),
        ),
        if (badge != null) Positioned(top: -6, left: -6, child: badge!),
      ]),
    );
    if (onLongPress != null) {
      return GestureDetector(onLongPress: onLongPress, child: child);
    }
    return child;
  }
}
