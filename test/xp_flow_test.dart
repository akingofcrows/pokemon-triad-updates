import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_triad/models/card_growth.dart';
import 'package:pokemon_triad/models/card_owner.dart';
import 'package:pokemon_triad/models/deck.dart';
import 'package:pokemon_triad/models/match_state.dart';
import 'package:pokemon_triad/models/triad_card.dart';
import 'package:pokemon_triad/services/match_service.dart';
import 'package:pokemon_triad/services/card_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('XP flow: captureXpByInstanceId should be populated when deck has instance IDs', () async {
    await CardRepository.instance.load();

    // Simulate a player with a shiny Bulbasaur instance (id=42) and others
    final playerInstances = <CardGrowth>[
      const CardGrowth(cardId: 'card_bulbasaur_1', instanceId: 42, xp: 0, level: 1, shiny: true, bonusNorth: 0, bonusSouth: 0, bonusEast: 0, bonusWest: 0),
      const CardGrowth(cardId: 'card_charmander_1', instanceId: 43, xp: 0, level: 2, bonusNorth: 0, bonusSouth: 0, bonusEast: 0, bonusWest: 0),
      const CardGrowth(cardId: 'card_squirtle_1', instanceId: 44, xp: 5, level: 1, bonusNorth: 0, bonusSouth: 0, bonusEast: 0, bonusWest: 0),
      const CardGrowth(cardId: 'card_pikachu_1', instanceId: 45, xp: 0, level: 1, bonusNorth: 0, bonusSouth: 0, bonusEast: 0, bonusWest: 0),
      const CardGrowth(cardId: 'card_eevee_1', instanceId: 46, xp: 10, level: 3, bonusNorth: 0, bonusSouth: 0, bonusEast: 0, bonusWest: 0),
    ];

    // Deck WITH instance IDs (like the user has)
    final playerDeck = Deck(
      id: 'test_deck',
      name: 'Test Deck',
      cardIds: [
        'card_bulbasaur_1',
        'card_charmander_1',
        'card_squirtle_1',
        'card_pikachu_1',
        'card_eevee_1',
      ],
      instanceIds: [42, 43, 44, 45, 46],
    );

    final opponentDeck = Deck(
      id: 'opp_deck',
      name: 'Opponent',
      cardIds: [
        'card_bulbasaur_1',
        'card_charmander_1',
        'card_squirtle_1',
        'card_pikachu_1',
        'card_eevee_1',
      ],
    );

    final matchState = MatchService().createMatch(
      playerDeck: playerDeck,
      opponentDeck: opponentDeck,
      playerInstances: playerInstances,
      random: Random(42),
    );

    print('=== XP Flow Test ===');
    print('playerCardInstanceIds size: ${matchState.playerCardInstanceIds.length}');
    for (final entry in matchState.playerCardInstanceIds.entries) {
      print('  ${entry.key.name} (${entry.key.id}) → instanceId=${entry.value}');
    }
    print('');

    // Simulate a capture: Bulbasaur captures an opponent card
    final bulbasaur = matchState.playerHand.firstWhere((c) => c.id == 'card_bulbasaur_1');
    print('Bulbasaur object: ${bulbasaur.hashCode}, id=${bulbasaur.id}, owner=${bulbasaur.owner}');
    print('Bulbasaur in playerCardInstanceIds: ${matchState.playerCardInstanceIds.containsKey(bulbasaur)}');
    print('Bulbasaur == check: ${matchState.playerCardInstanceIds.keys.any((k) => k == bulbasaur)}');
    print('');

    // Record a capture with 9 XP
    matchState.recordCapture(bulbasaur, 1, 9);
    print('After recordCapture:');
    print('  captureXpByInstanceId: ${matchState.captureXpByInstanceId}');
    print('  captureCountByCardId: ${matchState.captureCountByCardId}');
    print('');

    // Also check what a copyWith does to identity
    final copied = bulbasaur.copyWith(owner: CardOwner.player);
    print('copyWith equality: ${bulbasaur == copied}');
    print('copyWith in map: ${matchState.playerCardInstanceIds.containsKey(copied)}');

    // Verify the XP was recorded correctly
    expect(matchState.captureXpByInstanceId.isNotEmpty, true,
        reason: 'captureXpByInstanceId should NOT be empty when deck has instance IDs');
    expect(matchState.captureXpByInstanceId[42], 9,
        reason: 'Instance 42 (shiny Bulbasaur) should have 9 XP');
  });

  test('XP flow: fallback works when deck has NO instance IDs', () async {
    await CardRepository.instance.load();

    final playerInstances = <CardGrowth>[
      const CardGrowth(cardId: 'card_bulbasaur_1', instanceId: 42, xp: 0, level: 1, shiny: true, bonusNorth: 0, bonusSouth: 0, bonusEast: 0, bonusWest: 0),
    ];

    // Deck WITHOUT instance IDs
    final playerDeck = Deck(
      id: 'test_deck2',
      name: 'Test Deck 2',
      cardIds: ['card_bulbasaur_1', 'card_bulbasaur_1', 'card_bulbasaur_1', 'card_bulbasaur_1', 'card_bulbasaur_1'],
      // NO instanceIds
    );

    final opponentDeck = Deck(
      id: 'opp_deck2',
      name: 'Opponent',
      cardIds: ['card_bulbasaur_1', 'card_bulbasaur_1', 'card_bulbasaur_1', 'card_bulbasaur_1', 'card_bulbasaur_1'],
    );

    final matchState = MatchService().createMatch(
      playerDeck: playerDeck,
      opponentDeck: opponentDeck,
      playerInstances: playerInstances,
      random: Random(42),
    );

    print('=== Fallback Test ===');
    print('playerCardInstanceIds after createMatch (no deck instanceIds): ${matchState.playerCardInstanceIds.length}');
    for (final entry in matchState.playerCardInstanceIds.entries) {
      print('  ${entry.key.name} → instanceId=${entry.value}');
    }

    // Simulate capture
    final bulbasaur = matchState.playerHand.first;
    matchState.recordCapture(bulbasaur, 1, 9);
    print('captureXpByInstanceId: ${matchState.captureXpByInstanceId}');
    print('captureCountByCardId: ${matchState.captureCountByCardId}');

    // With the v1.0.58 fix, should now have instanceId from fallback
    expect(matchState.playerCardInstanceIds.isNotEmpty, true,
        reason: 'playerCardInstanceIds should be populated from fallback');
  });
}
