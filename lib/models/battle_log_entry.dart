import 'card_owner.dart';

/// One line of the battle log: a mover's name (colored per team in the UI)
/// followed by a plain-English description of what happened.
class BattleLogEntry {
  const BattleLogEntry({
    required this.moverOwner,
    required this.moverName,
    required this.message,
    this.capturedOwner,
  });

  final CardOwner moverOwner;
  final String moverName;
  final String message;
  /// Non-null for capture entries — the owner of the card(s) that were captured.
  final CardOwner? capturedOwner;

  factory BattleLogEntry.placement({
    required CardOwner moverOwner,
    required String moverName,
    required String cardName,
    required String positionName,
  }) {
    return BattleLogEntry(
      moverOwner: moverOwner,
      moverName: moverName,
      message: 'placed $cardName on $positionName.',
    );
  }

  factory BattleLogEntry.capture({
    required CardOwner moverOwner,
    required String moverName,
    required String placedCardName,
    required List<String> capturedCardNames,
    required String capturedOwnerName,
  }) {
    final possessive = capturedOwnerName.endsWith('s') ? "$capturedOwnerName'" : "$capturedOwnerName's";
    return BattleLogEntry(
      moverOwner: moverOwner,
      moverName: moverName,
      capturedOwner: moverOwner == CardOwner.player ? CardOwner.opponent : CardOwner.player,
      message: capturedCardNames.length == 1
          ? 'captured $possessive ${capturedCardNames.first}!'
          : 'captured $possessive ${capturedCardNames.join(', ')}!',
    );
  }

  /// Local, immediate feedback for a capture's growth XP — the real XP is
  /// only applied server-side once the match ends (see
  /// PlayerProfileController.recordMatchResult), but showing it live in the
  /// log keeps the reward feeling connected to the capture that earned it.
  factory BattleLogEntry.xpGain({
    required CardOwner moverOwner,
    required String moverName,
    required String cardName,
    required int xp,
  }) {
    return BattleLogEntry(
      moverOwner: moverOwner,
      moverName: moverName,
      message: '$cardName gained +$xp XP!',
    );
  }
}
