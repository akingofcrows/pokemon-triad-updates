import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../app/story_progress_controller.dart';
import '../models/deck.dart';
import '../models/player_profile.dart';
import '../models/quest.dart';
import '../models/story_location.dart';
import '../models/trainer_appearance.dart';
import '../widgets/trainer_sprite_stack.dart';
import 'battle_screen.dart';
import 'route_battle_screen.dart';

class StoryModeScreen extends StatefulWidget {
  const StoryModeScreen({super.key});
  @override
  State<StoryModeScreen> createState() => _StoryModeScreenState();
}

class _NarrativeScene {
  final String text;
  final String? speakerName;
  final String? spriteAsset;
  final VoidCallback? onShow;
  const _NarrativeScene(this.text, {this.speakerName, this.spriteAsset, this.onShow});
}

class _StoryModeScreenState extends State<StoryModeScreen> with TickerProviderStateMixin {
  int _sceneIdx = -1;
  int _phase = 0;
  late final AnimationController _fadeCtrl;
  Completer<void>? _sceneDone;
  late final List<_NarrativeScene> _scenes;

  // Travel
  int _travelPhase = 0;
  AnimationController? _travelCtrl;
  Completer<void>? _travelDone;
  String _travelLoc = '';

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<StoryProgressController>().initialize();
      if (await _hasCheckpoint('post_tutorial')) {
        // Resume from after tutorial
        _startParcelNarrative();
      } else {
        _buildScenes();
        _nextScene();
      }
    });
  }

  void _buildScenes() {
    final p = context.read<PlayerProfileController>();
    final t = p.profile.trainerName ?? 'Trainer';
    _scenes = [
      _NarrativeScene('The world of Pokémon is vast and full of wonder.\n\nFrom the quiet hills of Pallet Town to the bustling\nstreets of Viridian City, every corner holds a new\nchallenge, a new friend, and a new adventure.\n\nYour journey begins now.'),
      _NarrativeScene('Pallet Town.\n\nA small, peaceful village nestled among rolling green hills.\nThe scent of fresh grass drifts through the air.\nThis is where every great Kanto journey begins.'),
      _NarrativeScene('$t stirs awake.\n\nSunlight streams through the bedroom window.\nA quick glance at the clock — oh no.\nLate. Again.\n\n$t scrambles out of bed, grabs a jacket,\nand rushes down the stairs.'),
      _NarrativeScene('"Oh, $t! There you are!"\n\nMom is waiting at the bottom of the stairs.\nShe looks at you with that familiar mix of\naffection and mild exasperation.\n\n"I packed your backpack with some clothes,\nsome food, and a little spending money."\n\nShe presses a small pouch into your hands.',
        speakerName: 'Mom', spriteAsset: 'assets/trainers/npc/MOM.png',
        onShow: () { p.profile.money += 500; p.notifyListeners(); }),
      _NarrativeScene('"Don\'t forget to visit Professor Oak when you can.\nHe\'s been asking about you."\n\nMom gives you a quick kiss on the forehead.\n\n"Now go on — the world isn\'t going to wait\nfor you forever!"',
        speakerName: 'Mom', spriteAsset: 'assets/trainers/npc/MOM.png'),
      _NarrativeScene('$t steps outside.\n\nPallet Town is bathed in soft morning light.\nA few neighbors wave as they go about their day.\n\nUp the hill, Professor Oak\'s lab door swings open.\nThe professor steps outside for a moment,\nthen turns and walks back in.\n\nLooks like he\'s in.'),
      _NarrativeScene('$t pushes open the heavy door of the lab.\n\nThe scent of old books and scientific equipment\nfills the air. Machines beep softly in the corner.\nPoké Balls line the shelves in neat rows.\n\nProfessor Oak looks up from his work and smiles.'),
      _NarrativeScene('"Ah, $t! Right on time!"\n\nProfessor Oak sets down a stack of papers and\nwalks over, adjusting his lab coat.\n\n"I\'ve been meaning to talk to you about something.\nYou see, the world of Pokémon Triple Triad\nis more than just a game. It\'s about strategy,\nbonds, and understanding your cards."',
        speakerName: 'Professor Oak', spriteAsset: 'assets/trainers/intro/introOak.png'),
      _NarrativeScene('"Each card has its own strengths.\nNumbers on each side represent its power\nin that direction. Place your cards wisely!\n\nBut before I go on... how about a quick\npractice match? Show me what you\'ve got!"',
        speakerName: 'Professor Oak', spriteAsset: 'assets/trainers/intro/introOak.png'),
    ];
  }

  Future<void> _nextScene() async {
    if (_sceneIdx + 1 >= _scenes.length) { _showVs(); return; }
    _sceneIdx++;
    _sceneDone = Completer<void>();
    setState(() => _phase = 1);
    _fadeCtrl.forward().then((_) {
      if (mounted) {
        _scenes[_sceneIdx].onShow?.call();
        setState(() => _phase = 2);
      }
    });
    return _sceneDone!.future;
  }

  void _advance() {
    if (_phase != 2) return;
    final c = _sceneDone; _sceneDone = null;
    setState(() => _phase = 3);
    _fadeCtrl.reverse().then((_) {
      if (mounted) { setState(() => _phase = 0); c?.complete(); _nextScene(); }
    });
  }

  void _showVs() {
    setState(() => _phase = 5);
  }

  void _startBattle() {
    final p = context.read<PlayerProfileController>();
    final deck = p.profile.decks.isNotEmpty ? p.profile.decks.first : null;
    if (deck == null) return;

    const oakDecks = <String, List<String>>{
      'card_bulbasaur_1': ['card_charmander_1','card_pidgey_1','card_rattata_1','card_spearow_1','trainer_oak'],
      'card_charmander_1': ['card_squirtle_1','card_pidgey_1','card_rattata_1','card_weedle_1','trainer_oak'],
      'card_squirtle_1': ['card_bulbasaur_1','card_pidgey_1','card_rattata_1','card_caterpie_1','trainer_oak'],
    };
    List<String> oakCards = ['card_rattata_1','card_rattata_1','card_rattata_1','card_pidgey_1','card_pidgey_1'];
    for (final cid in deck.cardIds) { if (oakDecks.containsKey(cid)) { oakCards = oakDecks[cid]!; break; } }

    Navigator.push(context, MaterialPageRoute(builder: (_) => BattleScreen(
      playerDeck: deck,
      opponentDeck: Deck(id: 'tutorial_oak', name: 'Practice Deck', cardIds: oakCards),
      opponentName: 'Professor Oak',
      opponentPortrait: 'assets/trainers/intro/introOak.png',
      opponentVictoryQuote: 'Excellent! You have real talent!',
      opponentDefeatQuote: 'Don\'t worry — that was just practice.',
      onMatchComplete: (won) {
        _tutorialWon = won;
      },
      onContinue: () {
        // Pop ResultsScreen to get back to StoryMode
        Navigator.of(context).pop();
        setState(() => _phase = 6);
      },
    )));
  }

  bool _tutorialWon = true;

  Future<void> _saveCheckpoint(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('story_$key', true);
  }

  Future<bool> _hasCheckpoint(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('story_$key') ?? false;
  }

  void _startParcelNarrative() {
    final p = context.read<PlayerProfileController>();
    final t = p.profile.trainerName ?? 'Trainer';
    _scenes = [
      _NarrativeScene('"Now then, $t..."\n\nProfessor Oak adjusts his glasses and\npulls out a small note from his desk.\n\n"I have a package waiting for you at the\nPokéMart in Viridian City. It\'s an important\ndelivery — some research materials I ordered."',
        speakerName: 'Professor Oak', spriteAsset: 'assets/trainers/intro/introOak.png'),
      _NarrativeScene('"The PokéMart is right in the center of town.\nYou can\'t miss it."\n\nOak hands you the pickup slip.\n\n"While you\'re on the road, you\'ll face wild\nPokémon. Use your Triad cards wisely —\neach one has strengths on different sides."',
        speakerName: 'Professor Oak', spriteAsset: 'assets/trainers/intro/introOak.png'),
      _NarrativeScene('"Route 1 lies just north of Pallet Town.\nIt\'s a simple path, but the wild Pokémon\nwon\'t make it easy for you."\n\nOak smiles warmly.\n\n"Good luck, $t. I\'m counting on you!"',
        speakerName: 'Professor Oak', spriteAsset: 'assets/trainers/intro/introOak.png'),
    ];
    _sceneIdx = -1;
    _nextScene();
  }

  @override
  void dispose() { _fadeCtrl.dispose(); _travelCtrl?.dispose(); super.dispose(); }

  // ── Travel ──

  Future<void> _onLocTap(String id, String name) async {
    final c = context.read<PlayerProfileController>();
    if (id == 'route_1') {
      final seen = await c.hasSeenParcelQuest();
      if (!seen && mounted) {
        final n = c.profile.trainerName ?? c.profile.playerName;
        await showDialog(context: context, builder: (_) => _OakDialog(name: n));
        if (mounted) await c.startParcelQuest();
      }
    }
    await _travel(name);
    if (!mounted) return;
    if (id == 'pallet_town') { Navigator.pushNamed(context, AppRoutes.palletTown); return; }
    Navigator.push(context, MaterialPageRoute(builder: (_) => RouteBattleScreen(locationId: id)));
  }

  Future<void> _travel(String loc) {
    _travelDone = Completer<void>(); _travelLoc = loc;
    _travelCtrl?.dispose();
    _travelCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    setState(() => _travelPhase = 1);
    _travelCtrl!.forward().then((_) { if (mounted) setState(() => _travelPhase = 2); });
    return _travelDone!.future;
  }

  void _dismissTravel() {
    if (_travelPhase != 2) return;
    final c = _travelDone; _travelDone = null;
    setState(() => _travelPhase = 3);
    _travelCtrl!.reverse().then((_) {
      _travelCtrl?.dispose(); _travelCtrl = null;
      if (mounted) setState(() => _travelPhase = 4);
      c?.complete();
    });
  }

  String _travelText() {
    final p = context.read<PlayerProfileController>();
    final t = p.profile.trainerName ?? 'Trainer';
    final d = {'Pallet Town':'The quiet village of Pallet Town.','Route 1':'A winding dirt path through tall grass.\nWild Pokémon rustle nearby.','Viridian City':'A welcoming city among deep green forests.','Viridian Forest':'Sunlight barely pierces the thick canopy.'};
    return '${d[_travelLoc] ?? 'Traveling to $_travelLoc...'}\n\n$t heads out.';
  }

  bool _hasObj(String name, Quest? q) {
    if (q == null) return false;
    for (final o in q.objectives) {
      if (o.completed) continue;
      final a = o.description.toLowerCase(), b = name.toLowerCase();
      if (a.contains(b)) return true;
      if (b == 'pallet town' && a.contains('return the parcel')) return true;
    }
    return false;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final showing = _sceneIdx >= 0 && _sceneIdx < _scenes.length;
    final scene = showing ? _scenes[_sceneIdx] : null;
    final sprite = scene?.spriteAsset != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        title: showing ? const SizedBox.shrink() : const Text('KANTO JOURNEY', style: TextStyle(letterSpacing: 3, fontSize: 16)),
        centerTitle: true,
        leading: showing ? const SizedBox.shrink() : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pushNamed(context, AppRoutes.home)),
      ),
      body: Stack(children: [
        // BG
        Positioned.fill(child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Image.asset('assets/locations/kanto.png', fit: BoxFit.cover, color: Colors.black.withValues(alpha: 0.45), colorBlendMode: BlendMode.darken))),

        // Narrative overlay
        if (showing && _phase > 0 && _phase != 5)
          AnimatedBuilder(animation: _fadeCtrl, builder: (_, __) {
            final op = _phase == 3 ? 1.0 - _fadeCtrl.value : _fadeCtrl.value;
            return Positioned.fill(child: GestureDetector(onTap: _phase == 2 ? _advance : null,
              child: Container(color: Colors.black, child: Center(child: Opacity(opacity: op.clamp(0.0, 1.0),
                child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (scene!.speakerName != null)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(scene.speakerName!, style: TextStyle(color: Colors.amber.shade300, fontSize: 16, fontWeight: FontWeight.bold))),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(scene!.text, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5, fontFamily: 'PowerGreen'), textAlign: sprite ? TextAlign.left : TextAlign.center)),
                    if (sprite) ...[const SizedBox(width: 16), Image.asset(scene.spriteAsset!, height: 100)],
                  ]),
                  if (_phase == 2) Padding(padding: const EdgeInsets.only(top: 28), child: Text('Tap to continue', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12, fontFamily: 'PowerGreen'))),
                ])))))));
          }),

        // VS screen — Janken-style layout, vertically centered
        if (_phase == 5)
          LayoutBuilder(builder: (_, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final bustH = w * 0.35;
            final ribbonH = w * 0.08;
            final topOffset = (h - bustH) / 2; // center vertically
            final p = context.read<PlayerProfileController>();
            final appearance = _buildAppearance(p.profile);
            return Positioned.fill(child: GestureDetector(onTap: _startBattle,
              child: Container(color: Colors.black, child: Stack(children: [
                // VS bars
                Positioned(left: 0, right: 0, top: topOffset + bustH / 2 - ribbonH / 2,
                  child: SizedBox(height: ribbonH, child: Row(children: [
                    Expanded(child: Image.asset('assets/ui/vsBar_blue.png', fit: BoxFit.fill, filterQuality: FilterQuality.none)),
                    Expanded(child: Image.asset('assets/ui/vsBar_red.png', fit: BoxFit.fill, filterQuality: FilterQuality.none)),
                  ]))),
                // Player sprite (left)
                Positioned(left: w * 0.18 - bustH / 2, top: topOffset,
                  child: TrainerSpriteStack(appearance: appearance, size: bustH)),
                // Oak sprite (right)
                Positioned(right: w * 0.18 - bustH / 2, top: topOffset,
                  child: SizedBox(width: bustH, height: bustH,
                    child: Image.asset('assets/trainers/intro/introOak.png', width: bustH, height: bustH, filterQuality: FilterQuality.none))),
                // VS logo
                Positioned(left: w / 2 - w * 0.15, top: topOffset + bustH / 2 - w * 0.15,
                  child: Image.asset('assets/ui/hgss_vs1.png', width: w * 0.30, height: w * 0.30, filterQuality: FilterQuality.none)),
                // Tap prompt
                Positioned(left: 0, right: 0, bottom: 40,
                  child: Text('Tap to battle!', textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14, fontFamily: 'PowerGreen'))),
              ]))));
          }),

        // Phase 6: Post-battle Oak dialogue
        if (_phase == 6)
          Positioned.fill(child: GestureDetector(onTap: () => setState(() => _phase = 7),
            child: Container(color: Colors.black, child: SafeArea(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                  child: Column(children: [
                    Image.asset('assets/trainers/intro/introOak.png', height: 64),
                    const SizedBox(height: 12),
                    Text(_tutorialWon ? 'Excellent! You have real talent!' : "Don't worry — that was just practice.",
                      style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5, fontFamily: 'PowerGreen'), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Text('Tap to continue', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12, fontFamily: 'PowerGreen')),
                  ]),
                ),
              ]),
            )))),

        // Phase 7: Chapter title
        if (_phase == 7)
          Positioned.fill(child: GestureDetector(
            onTap: () {
              setState(() => _phase = 0);
              _saveCheckpoint('post_tutorial');
              _startParcelNarrative();
            },
            child: Container(color: Colors.black, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Chapter 1', style: TextStyle(color: Color(0xFFC9A44C), fontSize: 18, fontFamily: 'PowerGreen')),
              const SizedBox(height: 8),
              const Text("OAK'S PARCEL", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
              const SizedBox(height: 24),
              Text('Tap to continue', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12, fontFamily: 'PowerGreen')),
            ]))),
          )),

        // Location list
        if (!showing)
          SafeArea(child: Consumer2<StoryProgressController, PlayerProfileController>(builder: (_, ctrl, pCtrl, __) {
            if (ctrl.locations.isEmpty) return const Center(child: CircularProgressIndicator(color: Colors.white));
            final q = pCtrl.activeQuest; final cur = pCtrl.profile.location ?? 'Pallet Town';
            final done = ctrl.locations.where((l) => ctrl.isLocationComplete(l.id)).length;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 32), children: [
              _chapterHeader(q, done, ctrl.locations.length), const SizedBox(height: 20),
              _LocCard(name: 'PALLET TOWN', sub: 'Your hometown', unlocked: true, complete: false,
                hasObj: _hasObj('Pallet Town', q), isCur: ['Pallet Town',"Player's House",'Your Bedroom',"Oak's Lab"].contains(cur),
                onTap: () => _onLocTap('pallet_town', 'Pallet Town')),
              for (final loc in ctrl.locations)
                _LocCard(name: loc.name.toUpperCase(), sub: loc.nodes.isEmpty ? 'City' : '${loc.nodes.length} encounters',
                  unlocked: ctrl.isLocationUnlocked(loc.id), complete: ctrl.isLocationComplete(loc.id),
                  completionPct: ctrl.completionFor(loc.id), hasObj: _hasObj(loc.name, q), isCur: cur == loc.name,
                  unlockReq: ctrl.isLocationUnlocked(loc.id) ? null : 'Complete ${_prev(ctrl, loc)}',
                  onTap: ctrl.isLocationUnlocked(loc.id) ? () => _onLocTap(loc.id, loc.name) : null),
            ]);
          })),

        // Travel overlay
        if (_travelPhase > 0 && _travelPhase < 4 && _travelCtrl != null)
          AnimatedBuilder(animation: _travelCtrl!, builder: (_, __) {
            return Positioned.fill(child: GestureDetector(onTap: _travelPhase == 2 ? _dismissTravel : null,
              child: Container(color: Colors.black, child: Center(child: _travelPhase >= 2
                ? Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_travelText(), style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.6, fontFamily: 'PowerGreen'), textAlign: TextAlign.center),
                    const SizedBox(height: 32), Text('Tap to continue', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, fontFamily: 'PowerGreen')),
                  ]))
                : const SizedBox.shrink()))));
          }),
      ]),
    );
  }

  Widget _chapterHeader(Quest? q, int done, int total) {
    final pct = total > 0 ? (done / total * 100).round() : 0;
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.explore, color: Color(0xFFC9A44C), size: 20), const SizedBox(width: 8),
          Text(done == 0 ? "Chapter 1: Oak's Parcel" : done >= total ? 'Journey Complete' : 'Chapter 1: Oak\'s Parcel', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))]),
        const SizedBox(height: 10),
        if (q != null) ...[Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFC9A44C).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFC9A44C).withValues(alpha: 0.2))),
            child: Row(children: [const Icon(Icons.assignment, color: Color(0xFFC9A44C), size: 16), const SizedBox(width: 8), Expanded(child: Text(q.name, style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 13, fontWeight: FontWeight.w600))), Text('${q.doneCount}/${q.objectives.length}', style: const TextStyle(color: Colors.white54, fontSize: 12))])),
          const SizedBox(height: 10)],
        Row(children: [Text('Region Progress: $pct%', style: const TextStyle(color: Colors.white38, fontSize: 11)), const Spacer(), Text('Badges: 0 / 8', style: const TextStyle(color: Colors.white38, fontSize: 11))]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct / 100, backgroundColor: Colors.white.withValues(alpha: 0.08), color: const Color(0xFF4CAF50), minHeight: 4)),
      ]));
  }

  String _prev(StoryProgressController c, StoryLocation l) { final i = c.locations.indexOf(l); return i > 0 ? c.locations[i-1].name : 'previous area'; }

  TrainerAppearance _buildAppearance(PlayerProfile profile) {
    return TrainerAppearance(
      trainerName: profile.trainerName ?? profile.playerName,
      gender: profile.gender ?? 'boy',
      skinTone: profile.skinTone ?? '',
      hairPath: profile.hairPath ?? '',
      topPath: profile.topPath ?? '',
      bottomPath: profile.bottomPath ?? '',
      hatPath: profile.hatPath,
    );
  }
}

// ── Location card ──

class _LocCard extends StatefulWidget {
  const _LocCard({required this.name, this.sub = '', required this.unlocked, required this.complete, this.completionPct = 0, this.onTap, this.hasObj = false, this.isCur = false, this.unlockReq});
  final String name, sub; final bool unlocked, complete; final double completionPct; final VoidCallback? onTap; final bool hasObj, isCur; final String? unlockReq;
  @override State<_LocCard> createState() => _LocCardState();
}

class _LocCardState extends State<_LocCard> with SingleTickerProviderStateMixin {
  late final AnimationController _p = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  @override void initState() { super.initState(); if (widget.hasObj) _p.repeat(reverse: true); }
  @override void didUpdateWidget(covariant _LocCard o) { super.didUpdateWidget(o); if (widget.hasObj && !_p.isAnimating) _p.repeat(reverse: true); if (!widget.hasObj && _p.isAnimating) _p.stop(); }
  @override void dispose() { _p.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final c = widget.unlocked ? Colors.white : Colors.grey;
    final bg = Colors.black.withValues(alpha: widget.unlocked ? 0.45 : 0.25);
    final border = widget.isCur ? const Color(0xFF4CAF50).withValues(alpha: 0.5) : widget.unlocked ? Colors.white.withValues(alpha: 0.10) : Colors.grey.withValues(alpha: 0.08);
    final h = DateTime.now().hour; final emoji = h<6?'🌙':h<12?'☀️':h<17?'🌤️':h<20?'🌅':'🌙'; final time = h<6?'Night':h<12?'Morning':h<17?'Afternoon':h<20?'Evening':'Night';
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Stack(clipBehavior: Clip.none, children: [
      Material(color: bg, borderRadius: BorderRadius.circular(12), child: InkWell(borderRadius: BorderRadius.circular(12), onTap: widget.onTap,
        child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: widget.unlocked ? Colors.greenAccent.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(widget.complete ? Icons.check_circle : widget.unlocked ? Icons.map : Icons.lock, color: widget.complete ? Colors.greenAccent : widget.unlocked ? Colors.greenAccent : Colors.grey, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(widget.name, style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w700))),
                if (widget.isCur) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF4CAF50).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(5)), child: const Text('HERE', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 9, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 3),
              Text('$emoji $time • ${['Clear','Breezy','Mild','Pleasant'][h%4]}', style: TextStyle(color: c.withValues(alpha: 0.45), fontSize: 11)),
              if (!widget.unlocked && widget.unlockReq != null) Text('Requires: ${widget.unlockReq}', style: const TextStyle(color: Colors.orange, fontSize: 10)),
            ])),
            if (widget.complete) const Icon(Icons.check_circle, color: Colors.greenAccent, size: 24)
            else if (widget.unlocked) Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.4)),
          ])))),
      if (widget.hasObj) Positioned(top: -6, left: -6,
        child: AnimatedBuilder(animation: _p, builder: (_, child) => Transform.scale(scale: 1.0 + _p.value * 0.15, child: child),
          child: Container(width: 20, height: 20, decoration: BoxDecoration(color: const Color(0xFFFFD54A), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)), child: const Center(child: Text('!', style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900)))))),
    ]));
  }
}

// ── Oak dialog ──

class _OakDialog extends StatelessWidget {
  const _OakDialog({required this.name}); final String name;
  @override Widget build(BuildContext c) => AlertDialog(backgroundColor: const Color(0xFF1A1A2E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/trainers/intro/introOak.png', height: 80), const SizedBox(height: 12),
      Text('Professor Oak', style: TextStyle(color: Colors.amber.shade300, fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
      Text("Oh hey, $name, before you head out — I have a parcel that needs to be picked up in Viridian City.", style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
      const SizedBox(height: 16), FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Got it!')),
    ]));
}
