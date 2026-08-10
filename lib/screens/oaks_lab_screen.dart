import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/player_profile_controller.dart';
import '../app/story_progress_controller.dart';
import '../models/quest.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../services/dialogue_repository.dart';
import '../widgets/obtained_banner.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/quest_rewards_dialog.dart';
import '../widgets/toast.dart';
import '../widgets/triad_card_view.dart';

class OaksLabScreen extends StatefulWidget {
  const OaksLabScreen({super.key});
  @override
  State<OaksLabScreen> createState() => _OaksLabScreenState();
}

class _OaksLabScreenState extends State<OaksLabScreen> {
  bool _claimed = false;
  int _tab = 0;
  bool _parcelTurnInStarted = false;

  @override
  void initState() {
    super.initState();
    _checkDaily();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkParcelTurnIn());
  }

  Future<void> _checkDaily() async {
    final p = await SharedPreferences.getInstance();
    final last = p.getString('daily_gift');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (mounted) setState(() => _claimed = last == today);
  }

  Future<void> _claim() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('daily_gift', DateTime.now().toIso8601String().substring(0, 10));
    setState(() => _claimed = true);
    final ctrl = context.read<PlayerProfileController>();
    final r = Random().nextInt(100);
    final amt = r < 10 ? 1000 : r < 40 ? 300 : 100;
    ctrl.profile.money += amt;
    ctrl.notifyListeners();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Received $amt PokéDollars!'), backgroundColor: const Color(0xFF4CAF50)));
  }

  void _checkParcelTurnIn() {
    if (_parcelTurnInStarted || !mounted) return;
    final pc = context.read<PlayerProfileController>();
    if (!pc.isQuestActive('oaks_parcel')) return;
    if (pc.itemCount('oaks_parcel') <= 0) return;
    if (pc.isQuestCompleted('oaks_parcel')) return;
    _parcelTurnInStarted = true;
    _showProgressCompleteDialog();
  }

  Future<void> _showProgressCompleteDialog() async {
    final d = DialogueRepository.instance.npcVariant('professor_oak', 'oaks_parcel', 'progress_complete');
    final pages = d['pages'] as List<String>?;
    final dialogue = d['dialogue'] as String? ?? '';
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ParchmentDialog(
            portrait: Image.asset('assets/trainers/npc/professor_oak.png', height: 180, fit: BoxFit.contain),
            dialogue: pages == null ? dialogue : '',
            pages: pages,
            speaker: d['speaker'] as String? ?? 'Professor Oak',
            actionLabel: d['actionLabel'] as String? ?? 'Got it!',
            actionColor: d['actionColor'] as Color? ?? const Color(0xFF4CAF50),
            onAction: () {
              Navigator.pop(ctx);
              final pc = context.read<PlayerProfileController>();
              pc.useConsumable('oaks_parcel');
              // Mark objective locally but defer full completion + rewards to Claim Rewards
              final quest = pc.activeQuests.firstWhere((q) => q.id == 'oaks_parcel');
              for (final obj in quest.objectives) {
                if (obj.description == 'Return the parcel to Professor Oak') {
                  obj.completed = true;
                }
              }
              pc.notifyListeners();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Toast.show(context, text: "Oak's Parcel removed!", imagePath: 'assets/images/icons/items/item527.png', duration: const Duration(milliseconds: 3000));
                }
              });
              _showCompletionDialogue();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showCompletionDialogue() async {
    final cd = QuestData.completionDialogue('oaks_parcel');
    if (cd == null || !mounted) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ParchmentDialog(
            portrait: Image.asset('assets/trainers/npc/${cd.portrait}', height: 180, fit: BoxFit.contain),
            pages: cd.pages,
            speaker: cd.speaker,
            actionLabel: 'Finish',
            actionColor: const Color(0xFFFFCA28),
            onAction: () {
              Navigator.pop(ctx);
              _showRewardsAndDeliver();
            },
          ),
        ),
      ),
    );
  }

  void _showRewardsAndDeliver() {
    final pc = context.read<PlayerProfileController>();
    final detail = QuestData.questDetail('oaks_parcel');
    final items = detail?['rewardItems'] as List? ?? [];

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => QuestRewardsDialog(
        questId: 'oaks_parcel',
        onClaim: () => _deliverCardRewards(pc, items),
      ),
    );
  }

  void _deliverCardRewards(PlayerProfileController pc, List items) {
    // Complete the quest — gives money + pokeballs
    pc.forceCompleteQuest('oaks_parcel');
    // Deliver card rewards from quests.json
    for (final item in items) {
      final itemMap = item as Map<String, dynamic>;
      final id = itemMap['id'] as String? ?? '';
      if (!id.startsWith('card_')) continue;
      final qty = itemMap['quantity'] as int? ?? 1;
      for (var i = 0; i < qty; i++) {
        pc.profile.ownedCardIds.add(id);
        pc.profile.seenCardIds.add(id);
        pc.profile.everOwnedCardIds.add(id);
      }
    }
    pc.notifyListeners();
    if (mounted) {
      // Build stacked toast items
      final detail = QuestData.questDetail('oaks_parcel');
      final toastItems = <Map<String, dynamic>>[];
      final money = detail?['rewardMoney'] as int? ?? 0;
      if (money > 0) {
        toastItems.add({'text': '₽$money Obtained!', 'imagePath': '__money__'});
      }
      final rewardItems = detail?['rewardItems'] as List? ?? [];
      for (final r in rewardItems) {
        final rm = r as Map<String, dynamic>;
        final rid = rm['id'] as String? ?? '';
        final rqty = rm['quantity'] as int? ?? 1;
        if (rid.startsWith('card_')) {
          final card = CardRepository.instance.cardById(rid);
          toastItems.add({
            'text': '${rqty}× ${card?.name ?? rid} Card Obtained!',
            'icon': card != null ? TriadCardView(card: card, size: 44, showCondition: false) : null,
          });
        } else {
          switch (rid) {
            case 'pokeball': toastItems.add({'text': '$rqty× Poké Ball Obtained!', 'imagePath': 'assets/images/icons/items/item267.png'}); break;
            case 'great_ball': toastItems.add({'text': '$rqty× Great Ball Obtained!', 'imagePath': 'assets/images/icons/items/item266.png'}); break;
            default: toastItems.add({'text': '$rqty× $rid Obtained!', 'imagePath': null}); break;
          }
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Toast.showStacked(context, items: toastItems);
        Future.delayed(const Duration(milliseconds: 800), () {
          _showRewardDialogue();
        });
      });
    }
  }

  Future<void> _showRewardDialogue() async {
    final d = DialogueRepository.instance.npcVariant('professor_oak', 'oaks_parcel', 'reward_received');
    final pages = d['pages'] as List<String>?;
    final dialogue = d['dialogue'] as String? ?? '';
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ParchmentDialog(
            portrait: Image.asset('assets/trainers/npc/professor_oak.png', height: 180, fit: BoxFit.contain),
            dialogue: pages == null ? dialogue : '',
            pages: pages,
            speaker: d['speaker'] as String? ?? 'Professor Oak',
            actionLabel: d['actionLabel'] as String? ?? 'I won\'t let you down!',
            actionColor: d['actionColor'] as Color? ?? const Color(0xFF4CAF50),
            onAction: () {
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: const Color(0xFF0D0D1A),
    body: Stack(children: [
      Positioned.fill(child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Image.asset('assets/locations/oakslab.png', fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.40), colorBlendMode: BlendMode.darken))),
      SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(c)),
          const SizedBox(width: 8),
          const Text("OAK'S LAB", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 3)),
        ])),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(color: Colors.black.withValues(alpha: 0.25), padding: const EdgeInsets.all(12),
            child: Row(children: [
              Image.asset('assets/trainers/npc/PROFESSOR.png', width: 56, height: 56),
              const SizedBox(width: 12),
              const Expanded(child: Text('"Welcome! What can I help you with today?"',
                  style: TextStyle(color: Colors.white70, fontSize: 13))),
            ])))),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
          _tabBtn('Daily Gift', 0), const SizedBox(width: 8),
          _tabBtn('Quests', 1), const SizedBox(width: 8),
          _tabBtn('Scanner', 2),
        ])),
        const SizedBox(height: 12),
        Expanded(child: IndexedStack(index: _tab, children: [_dailyTab(), _questsTab(), _scannerTab(c)])),
      ])),
    ]),
  );

  Widget _tabBtn(String l, int i) {
    final a = _tab == i;
    return Expanded(child: GestureDetector(onTap: () => setState(() => _tab = i), child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: a ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: a ? const Color(0xFFC9A44C).withValues(alpha: 0.5) : const Color(0xFF333333))),
      child: Text(l, textAlign: TextAlign.center,
        style: TextStyle(color: a ? Colors.white : Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w600)))));
  }

  Widget _dailyTab() => Center(child: Padding(padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.card_giftcard, color: Colors.amber.withValues(alpha: 0.8), size: 56), const SizedBox(height: 16),
      Text(_claimed ? 'Come back tomorrow!' : 'Daily Gift Available!',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(_claimed ? "Already claimed today." : 'Claim free PokéDollars once per day.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
      const SizedBox(height: 24),
      SizedBox(width: 200, height: 48, child: FilledButton(
        onPressed: _claimed ? null : _claim,
        style: FilledButton.styleFrom(backgroundColor: _claimed ? Colors.grey : const Color(0xFF4CAF50)),
        child: Text(_claimed ? 'CLAIMED' : 'CLAIM GIFT', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
    ])));

  Widget _questsTab() => ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
    _q('Beginner Researcher', 'Capture 3 species from Route 1', '200 PokéDollars', '1/3', const Color(0xFF4CAF50)),
    const SizedBox(height: 10),
    _q('Bug Collector', 'Catch a Caterpie or Weedle', '100 Pd + Booster', '0/1', const Color(0xFF66BB6A)),
    const SizedBox(height: 10),
    _q('Evolution Student', 'Evolve any Pokémon', '500 PokéDollars', '0/1', const Color(0xFFFFCA28)),
    const SizedBox(height: 20),
    Text('More quests unlock as you explore!', textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
    const SizedBox(height: 40),
  ]);

  Widget _q(String t, String d, String r, String p, Color col) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF333333))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(p, style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 6),
      Text(d, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
      const SizedBox(height: 4),
      Text(r, style: TextStyle(color: Colors.amber.withValues(alpha: 0.8), fontSize: 12)),
    ]),
  );

  Widget _scannerTab(BuildContext c) {
    final ctrl = c.watch<PlayerProfileController>();
    final own = ctrl.profile.ownedCardIds.toSet();
    final seen = ctrl.seenCardIds;
    final all = CardRepository.instance.allCards;
    final disp = <String, bool>{};
    for (final x in all) { if (own.contains(x.id)) disp[x.id] = true; }
    for (final x in all) { if (!disp.containsKey(x.id) && seen.contains(x.id)) disp[x.id] = false; }
    if (disp.isEmpty) return Center(child: Text("No cards scanned yet!",
        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14)));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1),
      itemCount: disp.length,
      itemBuilder: (_, i) {
        final id = disp.keys.elementAt(i);
        final owned = disp[id]!;
        final card = CardRepository.instance.cardById(id);
        if (card == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _detail(card, owned),
          child: Opacity(opacity: owned ? 1.0 : 0.5, child: TriadCardView(card: card, size: 80)),
        );
      },
    );
  }

  void _detail(TriadCard card, bool owned) => showDialog(
    context: context,
    builder: (ctx) => Dialog(backgroundColor: Colors.transparent, child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(16),
          border: Border.all(color: owned ? const Color(0xFFC9A44C).withValues(alpha: 0.3) : const Color(0xFF333333))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TriadCardView(card: card, size: 140), const SizedBox(height: 12),
        Text(card.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${card.affinity} • ${card.rarity.name}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _s('N', card.values.north), const SizedBox(width: 8),
          _s('S', card.values.south), const SizedBox(width: 8),
          _s('E', card.values.east), const SizedBox(width: 8),
          _s('W', card.values.west),
        ]),
        if (card.evolvesTo != null) ...[
          const SizedBox(height: 12),
          Text('Evolves to: ${card.evolvesTo}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
        ],
        const SizedBox(height: 16),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ]),
    )),
  );

  Widget _s(String l, int v) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(l, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
      Text('$v', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
    ]),
  );
}
