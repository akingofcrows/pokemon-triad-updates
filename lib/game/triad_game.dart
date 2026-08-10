import 'dart:math';
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, TextDirection;

import '../models/battle_log_entry.dart';
import '../models/board_position.dart';
import '../models/card_growth.dart';
import '../models/card_owner.dart';
import '../models/condition.dart';
import '../models/consumable_item.dart';
import '../models/match_state.dart';
import '../models/triad_card.dart';
import '../services/audio_service.dart';
import 'ai/ai_controller.dart';
import 'battle_hud.dart';
import 'board/battlefield_layout.dart';
import 'board/board_component.dart';
import 'board/board_visuals.dart';
import 'cards/card_back_component.dart';
import 'cards/card_component.dart';
import 'cards/card_visuals.dart';
import 'cards/pokeball_throw_component.dart';
import 'systems/capture_system.dart';
import 'systems/turn_system.dart';

/// The interactive battle board: opponent hand, 3×3 board, and player hand,
/// all as one Flame canvas so drag-and-drop stays within a single component
/// tree. The header and battle log live outside this canvas as separate
/// Flutter widgets (see `BattleScreen`), driven by [hud].
class TriadGame extends FlameGame {
  TriadGame({
    required this.state,
    required this.onMatchComplete,
    required this.hud,
    this.playerName = 'You',
    this.opponentName = 'Opponent',
    this.isWildBattle = false,
    this.rules = RuleSet.basic,
    this.onItemCaptured,
    this.onItemConsumed,
    this.trainerLevel = 1,
    this.conditionCap,
  }) {
    images = Images(prefix: 'assets/');
  }

  final MatchState state;
  final void Function(MatchState state) onMatchComplete;
  final BattleHud hud;
  final String playerName;
  final String opponentName;
  final bool isWildBattle;
  final RuleSet rules;
  /// Called when a pokéball successfully captures a card mid-battle.
  final void Function(TriadCard capturedCard)? onItemCaptured;
  /// Called when a pokéball is actually used (consumed), regardless of outcome.
  final void Function(String itemId)? onItemConsumed;
  /// Trainer level for scaling capture odds.
  final int trainerLevel;
  /// Per-card Condition-loss cap for this match (GDD §12). Defaults to the
  /// wild-battle cap for wild encounters and the (higher) trainer-trial cap
  /// otherwise; pass explicitly for boss/dungeon fights.
  final int? conditionCap;
  int get _effectiveConditionCap =>
      conditionCap ?? (isWildBattle ? kConditionLossCapNormal : kConditionLossCapTrainer);

  // --- board panel background ---
  Image? _bgBlack;
  Image? _cardBack;
  Image? _pokeballImage;

  // --- board + hands ---
  late final BoardComponent board;
  late BattlefieldLayout _layout;
  final Map<int, CardComponent> _boardCards = {};
  final List<CardComponent> _playerHandComponents = [];
  final List<CardBackComponent> _opponentHandComponents = [];
  CardComponent? _selected;
  bool _inputLocked = false;
  bool _matchFinished = false;

  // --- placement preview ---
  BoardPosition? _previewPosition;

  // --- targeting mode (pokéball) ---
  ConsumableItem? _targetingBall;
  /// Positions flipped by the player's most recent placement — only these
  /// can be targeted with a pokéball.
  final Set<int> _recentlyFlipped = {};

  bool _ready = false;

  // ---- life-cycle ----

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      await _preloadImages();
    } catch (e) {
      debugPrint('TriadGame: image preload failed: $e');
      // Continue without preloaded images — individual components will
      // show fallback visuals rather than crashing.
    }

    // World-space components (board, hands, cards) are positioned assuming
    // (0,0) is the top-left of the screen. Flame's default camera anchors
    // the viewfinder at the center instead, which shifts every world
    // component by half the canvas size — pin it to top-left to match.
    camera.viewfinder.anchor = Anchor.topLeft;

    try {
      _bgBlack = images.fromCache(flameImageKey(
        isWildBattle ? kBgWildGrassAsset : kBgBlackAsset,
      ));
    } catch (_) {
      _bgBlack = null;
    }
    _cardBack = images.fromCache(flameImageKey('ui/card_back.png'));
    _pokeballImage = images.fromCache(flameImageKey('images/icons/items/item267.png'));

    _layout = BattlefieldLayout.compute(size);

    board = BoardComponent(
      topLeft: _layout.boardTopLeft,
      cellSize: _layout.boardCellSize,
      gap: _layout.boardGap,
      onCellTap: _onCellTapped,
      cardPlacer: images.fromCache(flameImageKey(kCardPlacerAsset)),
      cardPlacerSelect: images.fromCache(flameImageKey(kCardPlacerSelectAsset)),
    );
    world.add(board);

    _buildPlayerHand();
    _buildOpponentHand();
    _updateScoreDisplay();

    _ready = true;

    if (state.turn == CardOwner.opponent) {
      _runOpponentTurn();
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!_ready) return;
    _relayout(BattlefieldLayout.compute(size));
  }

  void _relayout(BattlefieldLayout layout) {
    _layout = layout;
    board.relayout(layout.boardTopLeft, layout.boardCellSize, layout.boardGap);

    for (final entry in _boardCards.entries) {
      final pos = BoardPosition.fromIndex(entry.key);
      entry.value
        ..resize(layout.boardCellSize)
        ..moveTo(board.worldCenterFor(pos));
    }
    for (final c in _playerHandComponents) c.resize(layout.handCardSize);
    for (final c in _opponentHandComponents) c.resize(layout.handCardSize);
    _reflowPlayerHand();
    _reflowOpponentHand();
  }

  Future<void> _preloadImages() async {
    final paths = <String>{kBgBlackAsset, kBgWildGrassAsset, kCardBgAsset, kNumbersAsset, kScoreAsset,
      kHoloFrameAsset, kShinyFrameAsset, kShinyBgAsset, kCardPlacerAsset,
      kCardPlacerSelectAsset, 'ui/card_back.png',
    };
    // Preload rarity frames for all 5 rarities so CardComponent can grab them
    for (final rarity in CardRarity.values) {
      paths.add(rarityFrameAsset(rarity));
    }
    paths.add(kSparkleAsset);
    paths.add('images/icons/items/item267.png');
    paths.add('ui/playerframe.png');
    paths.add('ui/opponentframe.png');
    // Preload trainer card backgrounds
    paths.add(kTrainerBgAsset);
    paths.add(kEliteBgAsset);
    paths.add(kGymLeaderBgAsset);
    paths.add(kOakBgAsset);
    for (final card in [...state.playerHand, ...state.opponentHand]) {
      paths.add(card.image);
      if (card.shiny) {
        paths.add(card.image.replaceFirst('assets/pokemon/', 'assets/pokemon_shiny/'));
      }
      paths.add(typeIconAsset(card.affinity));
    }
    await images.loadAll(paths.map(flameImageKey).toList());
  }

  // ---- custom render: board panel background + hand section labels ----

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;

    // Board panel background — draw the full battle_bg.png stretched
    // to fill the canvas behind the hands and board.
    final bg = _bgBlack;
    if (bg != null) {
      canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
        Rect.fromLTWH(0, 0, w, h),
        Paint(),
      );
    } else {
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF1B1B2E));
    }

    final handPad = _layout.handCardSize / 2;

    // Navy box behind opponent hand — tight to card edges, +5px bottom
    canvas.drawRect(
      Rect.fromLTWH(0, (_layout.opponentHandY - handPad).clamp(0, h), w, _layout.handCardSize + 5),
      Paint()..color = const Color(0xFF00001C),
    );
    // Solid navy from player hand area down to bottom, +5px top
    canvas.drawRect(
      Rect.fromLTWH(0, _layout.playerHandY - handPad - 5, w, h - _layout.playerHandY + handPad + 5),
      Paint()..color = const Color(0xFF00001C),
    );

    // Flame component tree (board cells, cards) on top
    super.render(canvas);
  }

  void _drawHandLabel(Canvas canvas, String label, double y) {
    final w = size.x;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13, fontFamily: 'PowerGreen'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textLeft = w / 2 - painter.width / 2;
    final textRight = w / 2 + painter.width / 2;
    final lineY = y;
    const margin = 24.0;
    const flourishGap = 8.0;
    final linePaint = Paint()..color = const Color(0x3DFFFFFF);
    canvas.drawLine(Offset(margin, lineY), Offset(textLeft - flourishGap, lineY), linePaint);
    canvas.drawLine(Offset(textRight + flourishGap, lineY), Offset(w - margin, lineY), linePaint);

    painter.paint(canvas, Offset(textLeft, y - painter.height / 2));
  }

  // ---- hand layout (horizontal rows) ----

  static const double _handGap = 6;

  Vector2 _playerHandSlot(int i) {
    final cardSize = _layout.handCardSize;
    final count = _playerHandComponents.length;
    final totalW = count * cardSize + (count - 1) * _handGap;
    final startX = _layout.canvasSize.x / 2 - totalW / 2 + cardSize / 2;
    return Vector2(startX + i * (cardSize + _handGap), _layout.playerHandY);
  }

  Vector2 _opponentHandSlot(int i) {
    final cardSize = _layout.handCardSize;
    final count = _opponentHandComponents.length;
    final totalW = count * cardSize + (count - 1) * _handGap;
    final startX = _layout.canvasSize.x / 2 - totalW / 2 + cardSize / 2;
    return Vector2(startX + i * (cardSize + _handGap), _layout.opponentHandY);
  }

  void _buildPlayerHand() {
    for (var i = 0; i < state.playerHand.length; i++) {
      final component = CardComponent(
        card: state.playerHand[i],
        images: images,
        position: _playerHandSlot(i),
        pixelSize: _layout.handCardSize,
        interactive: state.turn == CardOwner.player,
        onTapped: _onHandCardTapped,
        onDragStarted: _onHandCardTapped,
        onDropped: _onCardDropped,
      );
      _playerHandComponents.add(component);
      world.add(component);
    }
  }

  void _buildOpponentHand() {
    for (var i = 0; i < state.opponentHand.length; i++) {
      final component = CardBackComponent(
        position: _opponentHandSlot(i),
        size: Vector2.all(_layout.handCardSize),
        cardBackImage: _cardBack,
      );
      _opponentHandComponents.add(component);
      world.add(component);
    }
  }

  void _reflowPlayerHand() {
    for (var i = 0; i < _playerHandComponents.length; i++) {
      _playerHandComponents[i].moveTo(_playerHandSlot(i));
    }
  }

  void _reflowOpponentHand() {
    for (var i = 0; i < _opponentHandComponents.length; i++) {
      _opponentHandComponents[i].moveTo(_opponentHandSlot(i));
    }
  }

  // ---- player input ----

  void _onHandCardTapped(CardComponent card) {
    if (_inputLocked || state.turn != CardOwner.player) return;
    if (!_playerHandComponents.contains(card)) return;
    _selectCard(card);
  }

  void _selectCard(CardComponent card) {
    if (_selected == card) return;
    _selected?.setSelected(false);
    _selected = card;
    card.setSelected(true);
    _clearPreview();
    board.setHighlights(CaptureSystem.emptyPositions(state).toSet());
  }

  // ── Targeting mode (pokéball use) ──

  /// Enter targeting mode — only highlights cards the player just flipped.
  /// Returns true if targeting started, false if no recently flipped cards.
  bool enterTargetingMode(ConsumableItem ball) {
    if (_targetingBall != null || _matchFinished) return true;
    if (_recentlyFlipped.isEmpty) {
      hud.addLog(BattleLogEntry.simple('No recently flipped cards to target!'));
      _inputLocked = false;
      return false;
    }
    _targetingBall = ball;
    _inputLocked = true;
    _selected = null;
    for (final idx in _recentlyFlipped) {
      final comp = _boardCards[idx];
      if (comp != null) {
        comp.setTargetable(true);
        final pos = BoardPosition.fromIndex(idx);
        comp.onTargeted = (_) => _useItemOnTarget(pos);
      }
    }
    hud.addLog(BattleLogEntry.simple('Choose a target for ${ball.name}…'));
    return true;
  }

  void _exitTargetingMode() {
    _targetingBall = null;
    _inputLocked = false;
    _recentlyFlipped.clear();
    for (final entry in _boardCards.entries) {
      entry.value
        ..setTargetable(false)
        ..onTargeted = null;
    }
  }

  void _useItemOnTarget(BoardPosition position) {
    final ball = _targetingBall;
    if (ball == null) return;
    final cell = state.cellAt(position);
    final targetCard = cell.card;
    if (targetCard == null || !_recentlyFlipped.contains(position.index)) return;

    _exitTargetingMode();
    // Keep input locked during animation
    _inputLocked = true;

    // Ball is consumed regardless of outcome
    onItemConsumed?.call(ball.id);

    // Capture chance: (20% + 2%/trainerLv) × ball / (1 + 6%/pokemonLv)
    final pokemonLevel = targetCard.baseLevel ?? 1;
    final multiplier = ball.catchMultiplier;
    final rng = Random();
    final trainerBonus = (0.20 + trainerLevel * 0.02).clamp(0.0, 0.85);
    final levelPenalty = 1.0 + pokemonLevel * 0.06;
    final catchChance = (trainerBonus * multiplier / levelPenalty).clamp(0.0, 0.95);
    final caught = multiplier >= 999.0 || rng.nextDouble() < catchChance;

    // Play throw → bounce → absorb → shake → result animation
    final targetWorldPos = board.worldCenterFor(position);
    final targetComp = _boardCards[position.index];
    late final PokeballThrowComponent anim;
    anim = PokeballThrowComponent(
      targetPosition: targetWorldPos,
      ballImage: _pokeballImage!,
      targetCard: targetComp!,
      caught: caught,
      onComplete: () {
        anim.removeFromParent();
        _inputLocked = false;
        _recentlyFlipped.clear();
        if (caught) {
          // Card stays player-owned, marked as pokéball-captured (dark overlay, unflippable)
          cell.card = targetCard.copyWith(owner: CardOwner.player, pokeballCaptured: true);
          targetComp.pokeballCaptured = true;
          targetComp.setCard(cell.card!);
          AudioService().playSfx('sound/flip.ogg');
          hud.addLog(BattleLogEntry.capture(
            moverOwner: CardOwner.player,
            moverName: playerName,
            placedCardName: ball.name,
            capturedCardNames: [targetCard.name],
            capturedOwnerName: opponentName,
          ));
          onItemCaptured?.call(targetCard);
        } else {
          // Ball broke — revert card to opponent
          cell.card = targetCard.copyWith(owner: CardOwner.opponent);
          targetComp.setCard(cell.card!);
          AudioService().playSfx('sound/bump.mp3');
          hud.addLog(BattleLogEntry.simple('Oh no! ${targetCard.name} broke free from the ${ball.name}!'));
        }
        _updateScoreDisplay();
      },
    );
    world.add(anim);
  }

  void _onCellTapped(BoardPosition position) {
    // Targeting mode active — try to use item
    if (_targetingBall != null) {
      _useItemOnTarget(position);
      return;
    }
    if (_inputLocked || state.turn != CardOwner.player) return;
    final selected = _selected;
    if (selected == null) return;
    if (!state.cellAt(position).isEmpty) return;

    // First tap: show type effectiveness preview on the selected card
    if (_previewPosition != position) {
      _showPlacementPreview(selected, position);
      return;
    }

    // Second tap on same cell: confirm placement
    _clearPreview();
    _placePlayerCard(selected, position);
  }

  /// Highlights the cell where the player is about to place a card.
  void _showPlacementPreview(CardComponent card, BoardPosition position) {
    _previewPosition = position;
    board.setHighlights({position});
  }

  /// Clears the placement preview.
  void _clearPreview() {
    if (_previewPosition == null) return;
    _previewPosition = null;
    board.setHighlights(CaptureSystem.emptyPositions(state).toSet());
  }

  void _onCardDropped(CardComponent card, Vector2 dropWorldPosition) {
    if (_inputLocked || state.turn != CardOwner.player) {
      _snapBackToHand(card);
      return;
    }
    final position = board.positionAtWorldPoint(dropWorldPosition);
    if (position == null || !state.cellAt(position).isEmpty) {
      _snapBackToHand(card);
      return;
    }
    _placePlayerCard(card, position);
  }

  void _snapBackToHand(CardComponent card) {
    final index = _playerHandComponents.indexOf(card);
    if (index == -1) return;
    card.moveTo(_playerHandSlot(index));
    card.setSelected(_selected == card);
  }

  void _placePlayerCard(CardComponent component, BoardPosition position) {
    _playerHandComponents.remove(component);
    state.playerHand.removeWhere((c) => identical(c, component.card));
    _selected = null;
    _inputLocked = true;

    final captured = CaptureSystem.applyPlacement(state, position, component.card, rules: rules);
    // Award placement XP for the card being placed
    state.recordPlacement(component.card);
    AudioService().playSfx('sound/cardSlide.ogg');
    hud.addLog(BattleLogEntry.placement(
      moverOwner: CardOwner.player,
      moverName: playerName,
      cardName: component.card.name,
      positionName: position.positionName,
    ));
    if (captured.isNotEmpty) {
      // Play flip sound
      AudioService().playSfx('sound/flip.ogg');
      final capturedNames = <String>[];
      var totalXp = 0;
      for (final pos in captured) {
        final capturedCard = state.cellAt(pos).card!;
        capturedNames.add(capturedCard.name);
        totalXp += xpForCapture(capturedCard.values.total);
      }
      hud.addLog(BattleLogEntry.capture(
        moverOwner: CardOwner.player,
        moverName: playerName,
        placedCardName: component.card.name,
        capturedCardNames: capturedNames,
        capturedOwnerName: opponentName,
      ));
      state.recordCapture(component.card, captured.length, totalXp);
      hud.addLog(BattleLogEntry.xpGain(
        moverOwner: CardOwner.player,
        moverName: playerName,
        cardName: component.card.name,
        xp: totalXp,
      ));
    }
    component.interactive = false;
    component.setSelected(false);
    component.resize(_layout.boardCellSize);
    component.moveTo(board.worldCenterFor(position));
    _boardCards[position.index] = component;

    _applyCaptureVisuals(captured);
    // Track cards flipped by this placement for pokéball targeting
    if (captured.isNotEmpty) {
      _recentlyFlipped.clear();
      for (final pos in captured) {
        _recentlyFlipped.add(pos.index);
      }
    }
    board.clearHighlights();
    _previewPosition = null;
    _reflowPlayerHand();
    _updateScoreDisplay();

    _afterPlacement();
  }

  void _applyCaptureVisuals(List<BoardPosition> captured) {
    for (final pos in captured) {
      final component = _boardCards[pos.index];
      final newCard = state.cellAt(pos).card;
      if (component != null && newCard != null) {
        component.setCard(newCard);
      }
    }
  }

  void _afterPlacement() {
    if (state.isComplete) {
      _finishMatch();
      return;
    }
    TurnSystem.endTurn(state);
    _updateScoreDisplay();
    if (state.turn == CardOwner.opponent) {
      _runOpponentTurn();
    } else {
      _setPlayerInteractivity(true);
    }
  }

  void _setPlayerInteractivity(bool value) {
    for (final component in _playerHandComponents) {
      component.interactive = value;
    }
  }

  // ---- opponent / AI ----

  Future<void> _runOpponentTurn() async {
    _setPlayerInteractivity(false);
    _inputLocked = true;
    await AiController.takeTurn(state, onPlaced: _placeOpponentCardVisual, rules: rules);
    _inputLocked = false;
    if (state.isComplete) {
      _finishMatch();
    } else {
      _setPlayerInteractivity(state.turn == CardOwner.player);
      _updateScoreDisplay();
    }
  }

  Future<void> _placeOpponentCardVisual(
    BoardPosition position,
    TriadCard card,
    List<BoardPosition> captured,
  ) async {
    AudioService().playSfx('sound/cardSlide.ogg');
    hud.addLog(BattleLogEntry.placement(
      moverOwner: CardOwner.opponent,
      moverName: opponentName,
      cardName: card.name,
      positionName: position.positionName,
    ));
    if (captured.isNotEmpty) {
      // Play flip sound for any card capture
      AudioService().playSfx('sound/flip.ogg');
      final capturedNames = [for (final pos in captured) state.cellAt(pos).card!.name];
      hud.addLog(BattleLogEntry.capture(
        moverOwner: CardOwner.opponent,
        moverName: opponentName,
        placedCardName: card.name,
        capturedCardNames: capturedNames,
        capturedOwnerName: playerName,
      ));
    }

    // Grab the last card back from opponent hand for its position
    final backComponent = _opponentHandComponents.isNotEmpty
        ? _opponentHandComponents.removeLast()
        : null;
    final startPosition = backComponent?.position.clone() ?? _opponentHandSlot(0);

    // Remove the card back from the world
    backComponent?.removeFromParent();
    _reflowOpponentHand();

    // Create face-up card at hand size where the card back was
    final targetWorldPos = board.worldCenterFor(position);
    final component = CardComponent(
      card: card,
      images: images,
      position: startPosition,
      pixelSize: _layout.handCardSize,
    );
    world.add(component);
    _boardCards[position.index] = component;

    // Phase 1: flip reveal from card back to card face
    component.reveal();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Phase 2: slide to board cell
    component.moveTo(targetWorldPos);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Phase 3: settle at board size
    component.resize(_layout.boardCellSize);

    _applyCaptureVisuals(captured);
    _updateScoreDisplay();
  }

  // ---- score / turn ----

  void _updateScoreDisplay() {
    hud.updateScore(
      playerScore: state.scoreFor(CardOwner.player),
      opponentScore: state.scoreFor(CardOwner.opponent),
      isPlayerTurn: state.turn == CardOwner.player,
    );
  }

  void _finishMatch() {
    if (_matchFinished) return;
    _matchFinished = true;
    // Finalize XP: survival, victory/draw, MVP
    final playerScore = state.scoreFor(CardOwner.player);
    final opponentScore = state.scoreFor(CardOwner.opponent);
    final playerWon = playerScore > opponentScore;
    final isDraw = playerScore == opponentScore;
    state.finalizeMatch(playerWon: playerWon, isDraw: isDraw);
    state.finalizeConditionLoss(
      playerLost: !playerWon && !isDraw,
      cap: _effectiveConditionCap,
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      onMatchComplete(state);
    });
  }
}
