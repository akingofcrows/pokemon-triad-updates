import 'package:flutter/foundation.dart';

import '../models/battle_log_entry.dart';

/// Score/turn/log state that lives outside Flame's render loop, so the
/// Flutter header bar and battle log widgets around the [GameWidget] can
/// react to it without TriadGame reaching into the widget tree.
class BattleHud extends ChangeNotifier {
  int playerScore = 0;
  int opponentScore = 0;
  bool isPlayerTurn = true;

  final List<BattleLogEntry> _log = [];
  List<BattleLogEntry> get log => List.unmodifiable(_log);

  void updateScore({
    required int playerScore,
    required int opponentScore,
    required bool isPlayerTurn,
  }) {
    this.playerScore = playerScore;
    this.opponentScore = opponentScore;
    this.isPlayerTurn = isPlayerTurn;
    notifyListeners();
  }

  void addLog(BattleLogEntry entry) {
    _log.add(entry);
    notifyListeners();
  }
}
