import 'dart:ui';

/// TTMMO's battle-header chrome — `header_color.png` (name strip tints),
/// `score.png` (card-count pips), `bg_black.png` (board background with
/// baked-in 3×3 grid), and `bg_overlay.png` (chrome overlay).
const String kHeaderColorAsset = 'assets/ui/header_color.png';
const String kScoreAsset = 'assets/ui/score.png';
const String kBgBlackAsset = 'assets/ui/battle_bg.png';
const String kBgWildGrassAsset = 'assets/ui/bg_wildgrass.png';
const String kBgOverlayAsset = 'assets/ui/bg_overlay.png';
const String kCardPlacerAsset = 'assets/ui/cardplacer.png';
const String kCardPlacerSelectAsset = 'assets/ui/cardplacerselect.png';
const String kCardPlacerWildAsset = 'assets/ui/cardplacerwild.png';

// --- TTMMO fixed canvas dimensions (bg_black.png) ---
const double kCanvasW = 736;
const double kCanvasH = 480;

// 3×3 cell centres from TTMMO boardRenderer.ts
const List<double> kBoardCols = [175, 305, 435];
const List<double> kBoardRows = [58, 188, 318];
const double kBoardCell = 128;

// Hand card positioning
const double kHandCardW = 128;
const double kHandCardH = 128;
const double kHandPanelX = 12;
const double kHandPanelY = 58;
const double kHandOverlap = 65;
const double kOpponentPanelX = kCanvasW - 12 - kHandCardW; // 596

// Header
const double kHeaderStripH = 36;
const double kNameW = 368;

// --- header_color.png spritesheet rows ---
const double kHeaderStripCellW = 226;
const double kHeaderStripCellH = 36;
const int kHeaderRowOpponent = 3;
const int kHeaderRowPlayer = 4;

// --- score.png spritesheet columns ---
const double kScorePipW = 22;
const double kScorePipH = 24;
const int kScorePipRed = 3;
const int kScorePipBlue = 4;
const int kScorePipEmpty = 0;

Rect headerStripSourceRect(int row) {
  return Rect.fromLTWH(0, row * kHeaderStripCellH, kHeaderStripCellW, kHeaderStripCellH);
}

Rect scorePipSourceRect(int column) {
  return Rect.fromLTWH(column * kScorePipW, 0, kScorePipW, kScorePipH);
}
