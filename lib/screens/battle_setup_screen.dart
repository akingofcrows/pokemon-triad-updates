import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/deck.dart';
import '../models/npc_trainer.dart';
import '../services/card_repository.dart';
import 'battle_screen.dart';
import 'janken_screen.dart';

class BattleSetupScreen extends StatefulWidget {
  const BattleSetupScreen({super.key});

  @override
  State<BattleSetupScreen> createState() => _BattleSetupScreenState();
}

class _BattleSetupScreenState extends State<BattleSetupScreen> {
  Deck? _selectedPlayerDeck;
  NpcTrainer? _selectedNpc;

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<PlayerProfileController>().profile;
    final validDecks = profile.decks.where((d) => d.isValid).toList();
    _selectedPlayerDeck ??=
        profile.defaultDeck ?? (validDecks.isNotEmpty ? validDecks.first : null);

    final npcs = CardRepository.instance.npcs;
    _selectedNpc ??= npcs.isNotEmpty ? npcs.first : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Battle Setup')),
      body: validDecks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('You need a 5-card deck before battling.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.deckBuilder),
                    child: const Text('Build a Deck'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Your deck', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                RadioGroup<Deck>(
                  groupValue: _selectedPlayerDeck,
                  onChanged: (d) => setState(() => _selectedPlayerDeck = d),
                  child: Column(
                    children: [
                      for (final deck in validDecks)
                        RadioListTile<Deck>(value: deck, title: Text(deck.name)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Opponent', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                RadioGroup<NpcTrainer>(
                  groupValue: _selectedNpc,
                  onChanged: (npc) => setState(() => _selectedNpc = npc),
                  child: Column(
                    children: [
                      for (final npc in npcs) _NpcTile(npc: npc),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: (_selectedPlayerDeck != null && _selectedNpc != null)
                      ? () => _startMatch(context)
                      : null,
                  child: const Text('Start Match'),
                ),
              ],
            ),
    );
  }

  void _startMatch(BuildContext context) {
    final npc = _selectedNpc!;
    final opponentDeck = Deck(id: npc.id, name: npc.name, cardIds: npc.cardIds);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JankenScreen(
          opponentName: npc.name,
          opponentPortrait: npc.portraitAsset,
          rules: const ['Synergy', 'Winner picks first move'],
          onComplete: ({required player, required opponent, required playerGoesFirst}) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => BattleScreen(
                  playerDeck: _selectedPlayerDeck!,
                  opponentDeck: opponentDeck,
                  opponentName: npc.name,
                  opponentPortrait: npc.portraitAsset,
                  opponentVictoryQuote: npc.victoryQuote,
                  opponentDefeatQuote: npc.defeatQuote,
                  playerGoesFirst: playerGoesFirst,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NpcTile extends StatelessWidget {
  const _NpcTile({required this.npc});

  final NpcTrainer npc;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<NpcTrainer>(
      value: npc,
      title: Row(
        children: [
          Expanded(child: Text(npc.name)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(npc.difficulty, style: Theme.of(context).textTheme.labelSmall),
          ),
        ],
      ),
      subtitle: Text(npc.flavor, maxLines: 1, overflow: TextOverflow.ellipsis),
      secondary: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          npc.portraitAsset,
          width: 44,
          height: 44,
          filterQuality: FilterQuality.none,
        ),
      ),
    );
  }
}
