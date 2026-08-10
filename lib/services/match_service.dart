import 'dart:math';

import '../models/card_growth.dart';
import '../models/card_owner.dart';
import '../models/condition.dart';
import '../models/deck.dart';
import '../models/match_state.dart';
import '../models/triad_card.dart';
import 'card_repository.dart';

/// Builds a new [MatchState] from a player deck and an opponent deck.
class MatchService {
  MatchState createMatch({
    required Deck playerDeck,
    required Deck opponentDeck,
    List<CardGrowth> playerInstances = const [],
    bool? playerGoesFirst,
    Random? random,
  }) {
    final rng = random ?? Random();
    final repository = CardRepository.instance;

    final playerHand = <TriadCard>[];
    final playerInstIds = <TriadCard, int>{};
    final instIds = playerDeck.instanceIds;
    for (var i = 0; i < playerDeck.cardIds.length; i++) {
      final card = repository.cardById(playerDeck.cardIds[i]);
      if (card == null) continue;
      // Look up the specific instance from the deck's instanceIds
      CardGrowth? growth;
      final targetInstId = instIds != null && i < instIds.length ? instIds[i] : null;
      if (targetInstId != null) {
        growth = playerInstances.where((inst) => inst.instanceId == targetInstId).firstOrNull;
      }
      // Fall back to best instance by card ID
      if (growth == null) {
        final matches = playerInstances
            .where((inst) => inst.cardId == card.id)
            .toList()
          ..sort((a, b) => b.level.compareTo(a.level));
        growth = matches.isNotEmpty ? matches.first : null;
      }
      final baseValues = growth == null ? card.values : card.values.plusBonus(growth.bonusValues);
      // Condition penalty is fixed for the whole battle at placement time
      // (GDD §3 "Selecting the affected side"), so it's applied once here
      // rather than recomputed live during the match.
      final values = growth == null ? baseValues : applyConditionPenalty(baseValues, growth.condition);
      final tc = card.copyWith(
        owner: CardOwner.player,
        values: values,
        shiny: growth?.shiny == true,
        condition: growth?.condition,
        // Kept alongside the already-penalized `values` so the battle
        // board can still highlight which sides took the hit.
        conditionPenaltyNorth: baseValues.north - values.north,
        conditionPenaltySouth: baseValues.south - values.south,
        conditionPenaltyEast: baseValues.east - values.east,
        conditionPenaltyWest: baseValues.west - values.west,
      );
      playerHand.add(tc);
      // Track the resolved instance ID so capture XP routes to the right instance,
      // regardless of whether the deck had explicit instanceIds.
      final resolvedId = targetInstId ?? growth?.instanceId;
      if (resolvedId != null) {
        playerInstIds[tc] = resolvedId;
      }
    }
    final rawOpponentCards = opponentDeck.opponentCards != null
        ? opponentDeck.opponentCards!
        : repository.cardsForIds(opponentDeck.cardIds);
    final shinySet = opponentDeck.shinyIndices ?? const {};
    final opponentHand = <TriadCard>[];
    for (var i = 0; i < rawOpponentCards.length; i++) {
      opponentHand.add(rawOpponentCards[i].copyWith(
        owner: CardOwner.opponent,
        shiny: shinySet.contains(i) || rawOpponentCards[i].shiny,
      ));
    }

    final firstTurn = playerGoesFirst != null
        ? (playerGoesFirst ? CardOwner.player : CardOwner.opponent)
        : (rng.nextBool() ? CardOwner.player : CardOwner.opponent);

    return MatchState(
      playerHand: playerHand,
      opponentHand: opponentHand,
      firstTurn: firstTurn,
      playerCardInstanceIds: playerInstIds,
    );
  }
}
