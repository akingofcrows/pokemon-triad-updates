# Pokémon Triple Triad Android Game
## Flutter + Flame Project Design Document

---

## 1. Project Overview

This project is an Android version of **Triple Triad redesigned around Pokémon**.

Players collect Pokémon cards, build five-card decks, and battle opponents on a 3×3 board. Each Pokémon card has four fixed directional values:

- North
- South
- East
- West

When a card is placed next to an opposing card, the touching values are compared. If the newly placed card has the higher value, the adjacent card changes ownership.

The game will begin as a small offline Android prototype and expand into a larger Pokémon card-collection RPG with:

- Deck building
- Card variants
- Pokémon evolution
- Type weaknesses and resistances
- Moves
- Terrain
- Weather
- Wild encounters
- Poké Ball capture mechanics
- Booster packs
- Trainers
- Gym Leaders
- Kanto exploration
- Online multiplayer

---

## 2. Development Stack

### Application Framework

- **Flutter**
- **Dart**
- Android-first development
- Landscape orientation initially
- Portrait layout may be added later

### Game Engine

- **Flame**
- Flame Components
- Flame Effects
- Flame input handling
- Flame overlays
- Flame collision detection where useful

### Local Data

Initial development will use:

- JSON files for static game data
- SharedPreferences for basic settings
- Isar, Hive, or Drift for player save data later

### Future Online Services

Possible backend options:

- Node.js with TypeScript
- Supabase
- Firebase
- PostgreSQL
- WebSockets for live multiplayer

The first version should remain fully offline.

---

## 3. Why Flutter and Flame

Flutter is responsible for the application-style portions of the game:

- Main menus
- Player profile
- Card collection
- Deck builder
- Booster packs
- Inventory
- Settings
- Adventure menus
- Shops
- Trainer lists

Flame is responsible for the active battle experience:

- 3×3 game board
- Card placement
- Drag-and-drop controls
- Card flipping
- Capture animations
- Move effects
- Weather effects
- Terrain effects
- Turn flow
- Opponent AI

This separation allows the game to feel like a polished mobile application while still having a proper animated game board.

---

## 4. Core Gameplay

### Match Setup

Each player brings a deck of five Pokémon cards.

At the beginning of a match:

1. The player receives five cards.
2. The opponent receives five cards.
3. The board begins empty.
4. One side is selected to go first.
5. Players alternate placing one card per turn.
6. The match ends when all nine board spaces are filled.

Because each player begins with five cards, the first player places five cards and the second player places four.

---

## 5. Board Layout

The battlefield is a 3×3 grid.

```text
┌───────┬───────┬───────┐
│  0,0  │  0,1  │  0,2  │
├───────┼───────┼───────┤
│  1,0  │  1,1  │  1,2  │
├───────┼───────┼───────┤
│  2,0  │  2,1  │  2,2  │
└───────┴───────┴───────┘
```

A card can only be placed in an empty space.

Cards may not be moved after being placed unless a move or special rule explicitly allows it.

---

## 6. Card Directional Values

Each Pokémon card has four fixed side values.

```text
          North
             3

West  2   Bulbasaur   4  East

             3
          South
```

Example data:

```text
North: 3
South: 3
East: 4
West: 2
```

The values do not rotate when the card is placed.

The values also do not rotate or reverse when ownership changes.

---

## 7. Standard Capture Rules

When a card is placed, the game checks each adjacent enemy card.

The values touching each other are compared.

### Example

Bulbasaur is placed west of Rattata.

```text
Bulbasaur East: 4
Rattata West: 3
```

Because 4 is greater than 3, Rattata is captured.

Rattata changes to the player’s ownership color, but its directional values remain unchanged.

### Equal Values

Under the standard rule:

```text
4 vs 4
```

No capture occurs.

Special rules may later allow equal-value interactions.

---

## 8. Ownership

Each card has one of the following owners:

```dart
enum CardOwner {
  player,
  opponent,
  neutral,
}
```

Ownership affects:

- Card border
- Card glow
- Score
- Which player controls move activation
- End-of-match ownership count

Capturing a card changes only its owner unless a move applies additional effects.

---

## 9. Match Scoring

The score is based on how many cards each side controls.

A normal match begins with five cards belonging to each side, including cards still in the hand.

During play, captured cards shift the score.

Example:

```text
Player: 6
Opponent: 4
```

At the end of the match:

- More cards controlled: Win
- Fewer cards controlled: Loss
- Equal cards controlled: Draw

Alternative scoring systems may later be added for tournaments or special matches.

---

## 10. Android Controls

The game should support both touch-control styles.

### Tap Placement

1. Tap a card in the player’s hand.
2. Valid spaces highlight.
3. Tap an empty board cell.
4. The card moves into that cell.

### Drag Placement

1. Press and hold a card.
2. Drag it toward the board.
3. Valid spaces highlight.
4. Release it over an empty space.

Tap controls are important for smaller Android screens.

### Selected Card Feedback

When selected, a card should:

- Rise slightly
- Gain a glow
- Enlarge slightly
- Emphasize its directional values
- Highlight valid board spaces
- Return to its hand position if placement is cancelled

---

## 11. Initial Screen Layout

The first build should use landscape orientation.

```text
┌─────────────────────────────────────────────────────┐
│ Opponent Trainer              Turn                  │
│                                                     │
│ Opponent Hand:   [?] [?] [?] [?]                   │
│                                                     │
│                 ┌─────┬─────┬─────┐                 │
│                 │     │     │     │                 │
│                 ├─────┼─────┼─────┤                 │
│                 │     │     │     │                 │
│                 ├─────┼─────┼─────┤                 │
│                 │     │     │     │                 │
│                 └─────┴─────┴─────┘                 │
│                                                     │
│ Player Hand: [Card] [Card] [Card] [Card] [Card]    │
│                                                     │
│ Score: 5–5        Terrain: None        Menu          │
└─────────────────────────────────────────────────────┘
```

---

## 12. Flutter Screens

Flutter should manage the following screens:

### Title Screen

- Game logo
- Continue
- New Game
- Settings
- Credits

### Home Screen

- Battle
- Collection
- Decks
- Adventure
- Booster Packs
- Inventory
- Player Profile

### Collection Screen

- View owned cards
- Sort by Pokédex number
- Sort by set
- Sort by rarity
- Sort by type
- View card variants
- View shiny cards
- View missing cards

### Deck Builder

- Select five cards
- Prevent invalid decks
- Display combined deck strength
- Save multiple decks
- Set a default deck

### Battle Setup

- Select deck
- Select opponent
- View match rules
- View terrain
- Start match

### Results Screen

- Victory, loss, or draw
- Score
- Captures made
- Experience gained
- Rewards
- New cards
- Rematch
- Return to menu

---

## 13. Flame Battle Components

The Flame portion of the game should contain:

```text
TriadGame
├── BoardComponent
├── BoardCellComponent
├── CardComponent
├── PlayerHandComponent
├── OpponentHandComponent
├── ScoreComponent
├── TurnIndicatorComponent
├── TerrainComponent
├── WeatherComponent
└── EffectLayer
```

### BoardComponent

Responsible for:

- Creating the 3×3 grid
- Storing board positions
- Checking whether cells are occupied
- Highlighting valid positions
- Receiving card placements

### BoardCellComponent

Responsible for:

- Board coordinates
- Empty or occupied state
- Placement highlight
- Touch detection
- Terrain or hazard state

### CardComponent

Responsible for:

- Pokémon artwork
- Directional values
- Owner border
- Selection state
- Placement animation
- Capture animation
- Status icons
- Move indicators

---

## 14. Suggested Project Structure

```text
pokemon_triad/
├── android/
├── assets/
│   ├── cards/
│   ├── pokemon/
│   ├── trainers/
│   ├── backgrounds/
│   ├── icons/
│   ├── effects/
│   ├── audio/
│   └── data/
│       ├── pokemon.json
│       ├── cards.json
│       ├── moves.json
│       ├── decks.json
│       ├── trainers.json
│       ├── terrains.json
│       └── items.json
│
├── lib/
│   ├── main.dart
│   │
│   ├── app/
│   │   ├── app.dart
│   │   ├── routes.dart
│   │   └── theme.dart
│   │
│   ├── models/
│   │   ├── triad_card.dart
│   │   ├── pokemon.dart
│   │   ├── card_values.dart
│   │   ├── deck.dart
│   │   ├── move.dart
│   │   ├── item.dart
│   │   ├── terrain.dart
│   │   ├── player_profile.dart
│   │   └── match_state.dart
│   │
│   ├── services/
│   │   ├── card_repository.dart
│   │   ├── pokemon_repository.dart
│   │   ├── save_service.dart
│   │   ├── deck_service.dart
│   │   ├── inventory_service.dart
│   │   └── match_service.dart
│   │
│   ├── screens/
│   │   ├── title_screen.dart
│   │   ├── home_screen.dart
│   │   ├── collection_screen.dart
│   │   ├── deck_builder_screen.dart
│   │   ├── inventory_screen.dart
│   │   ├── battle_setup_screen.dart
│   │   └── battle_screen.dart
│   │
│   ├── widgets/
│   │   ├── card_thumbnail.dart
│   │   ├── pokemon_card_view.dart
│   │   ├── deck_slot.dart
│   │   ├── rarity_icon.dart
│   │   └── type_icon.dart
│   │
│   └── game/
│       ├── triad_game.dart
│       ├── board/
│       │   ├── board_component.dart
│       │   ├── board_cell_component.dart
│       │   └── board_position.dart
│       ├── cards/
│       │   ├── card_component.dart
│       │   ├── draggable_card_component.dart
│       │   └── card_flip_effect.dart
│       ├── systems/
│       │   ├── placement_system.dart
│       │   ├── capture_system.dart
│       │   ├── type_system.dart
│       │   ├── move_system.dart
│       │   ├── terrain_system.dart
│       │   ├── weather_system.dart
│       │   ├── score_system.dart
│       │   └── turn_system.dart
│       ├── ai/
│       │   ├── ai_controller.dart
│       │   └── move_evaluator.dart
│       └── overlays/
│           ├── hand_overlay.dart
│           ├── score_overlay.dart
│           ├── turn_overlay.dart
│           └── match_result_overlay.dart
│
└── pubspec.yaml
```

---

## 15. Core Data Models

### Card Owner

```dart
enum CardOwner {
  player,
  opponent,
  neutral,
}
```

### Card Values

```dart
class CardValues {
  const CardValues({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final int north;
  final int south;
  final int east;
  final int west;
}
```

### Triad Card

```dart
class TriadCard {
  const TriadCard({
    required this.id,
    required this.name,
    required this.speciesId,
    required this.imagePath,
    required this.values,
    required this.owner,
    required this.types,
    required this.rarity,
    required this.setId,
    this.level = 1,
    this.isShiny = false,
  });

  final String id;
  final String name;
  final String speciesId;
  final String imagePath;
  final CardValues values;
  final CardOwner owner;
  final List<String> types;
  final String rarity;
  final String setId;
  final int level;
  final bool isShiny;

  TriadCard copyWith({
    CardOwner? owner,
    int? level,
  }) {
    return TriadCard(
      id: id,
      name: name,
      speciesId: speciesId,
      imagePath: imagePath,
      values: values,
      owner: owner ?? this.owner,
      types: types,
      rarity: rarity,
      setId: setId,
      level: level ?? this.level,
      isShiny: isShiny,
    );
  }
}
```

### Board Position

```dart
class BoardPosition {
  const BoardPosition(this.row, this.column);

  final int row;
  final int column;

  bool get isValid {
    return row >= 0 && row < 3 && column >= 0 && column < 3;
  }

  BoardPosition offset(int rowOffset, int columnOffset) {
    return BoardPosition(
      row + rowOffset,
      column + columnOffset,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BoardPosition &&
        other.row == row &&
        other.column == column;
  }

  @override
  int get hashCode => Object.hash(row, column);
}
```

---

## 16. Capture Comparison Logic

```dart
enum CompareDirection {
  north,
  south,
  east,
  west,
}

bool placedCardWins({
  required TriadCard placed,
  required TriadCard adjacent,
  required CompareDirection direction,
}) {
  switch (direction) {
    case CompareDirection.north:
      return placed.values.north > adjacent.values.south;

    case CompareDirection.south:
      return placed.values.south > adjacent.values.north;

    case CompareDirection.east:
      return placed.values.east > adjacent.values.west;

    case CompareDirection.west:
      return placed.values.west > adjacent.values.east;
  }
}
```

When a card is placed:

1. Check north.
2. Check south.
3. Check east.
4. Check west.
5. Ignore empty cells.
6. Ignore friendly cards under standard rules.
7. Compare values against enemy cards.
8. Capture every enemy card that loses the comparison.
9. Play capture animations.
10. Recalculate score.

---

## 17. Card JSON Format

### Standard Card

```json
{
  "id": "base1_bulbasaur_001",
  "speciesId": "bulbasaur",
  "name": "Bulbasaur",
  "setId": "kanto_beginnings",
  "number": 1,
  "rarity": "common",
  "image": "assets/pokemon/bulbasaur.png",
  "values": {
    "north": 3,
    "south": 3,
    "east": 3,
    "west": 3
  },
  "types": ["grass", "poison"],
  "stage": "basic",
  "isShiny": false
}
```

### Variant Card

```json
{
  "id": "forest_bulbasaur_014",
  "speciesId": "bulbasaur",
  "name": "Bulbasaur",
  "setId": "viridian_forest",
  "number": 14,
  "rarity": "uncommon",
  "image": "assets/pokemon/bulbasaur_forest.png",
  "values": {
    "north": 4,
    "south": 3,
    "east": 2,
    "west": 3
  },
  "types": ["grass", "poison"],
  "stage": "basic",
  "isShiny": false
}
```

A card variant may have different values, rarity, artwork, moves, or bonuses while remaining the same Pokémon species.

---

## 18. Card Variants

A Pokémon may appear in multiple sets.

Example:

### Kanto Beginnings Bulbasaur

```text
North: 3
South: 3
East: 3
West: 3
```

### Viridian Forest Bulbasaur

```text
North: 4
South: 3
East: 2
West: 3
```

### Shiny Bulbasaur

```text
North: 4
South: 3
East: 3
West: 3
```

Higher rarity does not always mean every side is stronger.

A variant should have a different strategic identity rather than simply replacing every earlier version.

---

## 19. Evolution

Cards may gain experience through battles.

Experience progression should be intentionally slow so Pokémon do not evolve after only a few matches.

Evolution stages include:

```text
Basic
Stage 1
Stage 2
```

Example:

```text
Bulbasaur → Ivysaur → Venusaur
```

Possible evolution requirements:

- Minimum card level
- Required number of victories
- Required evolution item
- Required card copy
- Required player rank
- Required biome or location
- Required friendship
- Special evolution condition

Evolved cards may have stronger or more specialized directional values.

Directional values always remain fixed and never rotate.

---

## 20. Type Weaknesses and Resistances

Pokémon types will eventually influence captures and moves.

Possible approaches include:

### Temporary Side Bonus

A super-effective matchup grants:

```text
+1 to the touching value
```

Example:

```text
Water side value: 4
Fire defender value: 4

Water gains +1 due to type advantage.

Effective comparison: 5 vs 4
```

### Resistance Reduction

A resistant defender may reduce an attacking type effect.

### Move-Only Type System

Normal card placement remains based on printed values, while type advantages apply only when moves activate.

This may be easier to balance and should be considered for the first expanded ruleset.

---

## 21. Moves

Moves provide active or passive abilities.

Most attack moves require the card to be touching another card.

Exceptions include:

- Terrain moves
- Weather moves
- Ranged moves
- Global moves
- Support moves
- Trap moves

### Example Moves

#### Ember

- Targets an adjacent card
- Applies Burn
- May reduce one side value temporarily

#### Vine Whip

- Targets an adjacent card
- May affect a card one additional space away in a straight line

#### Water Gun

- Targets an adjacent card
- Stronger against Fire-type cards

#### Thunder Wave

- Applies Paralysis
- Prevents or delays move activation

#### Growl

- Reduces one adjacent enemy side value

#### Sand Attack

- Hides or weakens one enemy side

#### Rain Dance

- Changes the current weather to Rain

#### Stealth Rock

- Places a hazard on an empty cell

---

## 22. Terrain

Terrain may be determined by the location where the match occurs.

Examples:

- Route
- Forest
- Cave
- Mountain
- Ocean
- City
- Laboratory
- Gym
- Power Plant

Terrain may:

- Strengthen certain types
- Weaken certain types
- Change move effects
- Create hazards
- Affect specific board cells
- Alter capture rules

Example:

```text
Viridian Forest Terrain

Grass and Bug cards gain +1 on one randomly selected side when placed.
Fire moves are stronger.
Rain lowers Fire move strength.
```

Terrain rules should remain readable and avoid excessive hidden modifiers.

---

## 23. Weather

Weather can be selected based on:

- Current area
- Season
- Time of day
- Random chance
- Trainer abilities
- Pokémon moves

Possible weather:

- Clear
- Rain
- Harsh Sunlight
- Sandstorm
- Hail
- Fog
- Thunderstorm

Weather may affect:

- Type effects
- Move strength
- Visibility
- Side values
- Status duration
- Terrain effects

Weather should be displayed clearly at the top of the battle screen.

---

## 24. Wild Pokémon Encounters

Wild Pokémon battles are used to obtain new cards.

A wild Pokémon must first be defeated.

After defeat, a short capture opportunity begins.

During the capture opportunity, the player may use a Poké Ball from their inventory.

The player does not automatically obtain every defeated wild Pokémon.

---

## 25. Poké Ball Capture System

Each Poké Ball has a base catch percentage.

Example:

```text
Poké Ball: 35%
Great Ball: 50%
Ultra Ball: 65%
Master Ball: 100%
```

Each wild Pokémon has Catch Resistance.

Catch Resistance may depend on:

- Species
- Rarity
- Level
- Evolution stage
- Shiny status
- Card bonuses
- Current area
- Special event status
- Remaining capture time
- Status conditions

### Example Formula

```text
Effective Catch Chance =
Poké Ball Base Rate
- Pokémon Catch Resistance
+ Status Bonuses
+ Capture Bonuses
```

Example:

```text
Great Ball Base Rate: 50%
Wild Pokémon Resistance: 18%
Sleep Bonus: 10%

Final Catch Chance: 42%
```

The chance should always be clamped between a minimum and maximum allowed value.

---

## 26. Player Inventory

The player should have a separate inventory from their card collection.

### Card Collection

Stores:

- Pokémon cards
- Trainer cards
- Terrain cards
- Card variants
- Shiny cards

### Player Inventory

Stores:

- Poké Balls
- Potions
- Evolution items
- Berries
- Fossils
- Key items
- Booster packs
- Currency
- Crafting materials

This prevents non-card items from becoming mixed into deck management.

---

## 27. Non-Damage Items

Because cards do not use traditional HP, items such as Potions need alternative effects.

Possible Potion effects:

- Remove a negative status
- Restore a disabled move
- Restore a reduced side value
- Remove Burn
- Remove Paralysis
- Cleanse a card before placement
- Recover a card’s once-per-match ability
- Protect a card from the next negative effect

Items should not undermine the core directional-value system.

---

## 28. Opponent AI

The first AI can evaluate every legal card placement.

Each possible move receives a score based on:

- Immediate captures
- Number of exposed weak sides
- Protection from corners
- Protection from edges
- Center control
- Type advantage
- Terrain bonus
- Future capture risk
- Remaining hand strength

### Basic AI Difficulties

#### Easy

- Often selects random legal moves
- Prefers captures when obvious
- Makes strategic mistakes

#### Normal

- Evaluates immediate captures
- Avoids exposing very weak sides
- Uses corners and edges

#### Hard

- Predicts the player’s likely next move
- Protects valuable cards
- Uses moves and terrain strategically
- Considers match score and remaining cards

---

## 29. First Playable Version

The first milestone should remain small.

### Included

- Flutter title screen
- Battle button
- One player deck
- One opponent deck
- 3×3 Flame board
- Five cards per side
- Tap-to-place controls
- Drag-to-place controls
- Directional comparisons
- Ownership capture
- Card-flip animation
- Alternating turns
- Basic AI
- Score tracking
- Win, loss, and draw results
- Local save file
- Android APK export

### Not Included Yet

- Moves
- Type weaknesses
- Terrain
- Weather
- Evolution
- Experience
- Wild encounters
- Poké Balls
- Booster packs
- Adventure map
- Online multiplayer

The basic board game must be stable before larger systems are added.

---

## 30. Initial Card Set

A small Kanto test set may contain:

```text
Bulbasaur
Ivysaur
Venusaur
Charmander
Charmeleon
Charizard
Squirtle
Wartortle
Blastoise
Caterpie
Metapod
Butterfree
Pidgey
Rattata
Spearow
Pikachu
Nidoran♀
Nidoran♂
Oddish
Bellsprout
```

Only ten cards are technically required for the first test match, but twenty cards provide more deck variety.

---

## 31. Development Phases

### Phase 1: Project Foundation

- Install Flutter
- Install Android Studio
- Configure Android SDK
- Create Flutter project
- Add Flame dependency
- Configure landscape orientation
- Add asset folders
- Create navigation system

### Phase 2: Data Models

- Create card owner enum
- Create directional values model
- Create Pokémon card model
- Create deck model
- Create board-position model
- Create match-state model
- Load cards from JSON

### Phase 3: Static Battle Board

- Create Flame game
- Draw 3×3 board
- Add board cells
- Add player hand
- Add opponent hand
- Render placeholder cards

### Phase 4: Card Placement

- Select cards by tapping
- Drag cards
- Highlight valid cells
- Place cards
- Prevent invalid placement
- Remove played card from hand

### Phase 5: Capture Rules

- Check adjacent cells
- Compare side values
- Capture enemy cards
- Animate ownership changes
- Update score

### Phase 6: Turn System

- Alternate turns
- Lock input during opponent turn
- Detect match completion
- Display active player
- Handle first-player selection

### Phase 7: AI

- Generate legal placements
- Score possible moves
- Select a move
- Add thinking delay
- Animate AI placement

### Phase 8: Results and Saving

- Calculate winner
- Display results screen
- Save player settings
- Save selected deck
- Save match statistics

### Phase 9: Android Build

- Configure application ID
- Add app icon
- Add splash screen
- Build debug APK
- Install on Android device
- Test multiple screen sizes
- Build release APK

### Phase 10: Expanded Pokémon Systems

- Card collection
- Deck builder
- Types
- Moves
- Status effects
- Terrain
- Weather
- Experience
- Evolution
- Wild capture
- Poké Balls
- Inventory
- Booster packs

### Phase 11: Adventure Mode

- Pallet Town
- Route 1
- Viridian City
- Trainers
- Search actions
- Wild encounters
- Pokémon Center
- Poké Mart
- Gym progression

### Phase 12: Multiplayer

- Player accounts
- Server-authoritative matches
- Private room codes
- Ranked matchmaking
- Friend battles
- Match history
- Anti-cheat validation

---

## 32. Suggested Flutter Packages

Initial packages may include:

```yaml
dependencies:
  flutter:
    sdk: flutter

  flame:
  flame_audio:
  provider:
  shared_preferences:
  path_provider:
  collection:
```

Later packages may include:

```yaml
  drift:
  sqlite3_flutter_libs:
  riverpod:
  go_router:
  web_socket_channel:
  firebase_core:
  supabase_flutter:
```

Package versions should be selected when the project is created so they match the installed Flutter SDK.

---

## 33. Save Data

Initial save data should include:

```text
Player name
Player ID
Settings
Audio volume
Selected deck
Owned cards
Card quantities
Card levels
Card experience
Unlocked opponents
Match wins
Match losses
Match draws
Inventory items
Currency
Adventure progress
```

Static card definitions should remain separate from individual owned-card data.

Example:

```text
Card Definition:
base1_bulbasaur_001

Owned Card Instance:
instance_000124
Level: 6
Experience: 310
Shiny: false
Acquired: Booster Pack
```

---

## 34. Multiplayer Security

When multiplayer is eventually added, the server should control:

- Deck validation
- Turn order
- Legal placements
- Card ownership
- Capture calculations
- Move activation
- Random rolls
- Match rewards
- Experience
- Card acquisition
- Ranked results

The Android client should display the game but should not be trusted to determine rewards or final results.

---

## 35. First Technical Goal

The immediate development goal is:

> Build an installable Android APK where the player selects a five-card Pokémon deck and completes one full Triple Triad match against an AI trainer.

This version should demonstrate:

- Flutter navigation
- Flame integration
- Mobile card controls
- Board placement
- Capture logic
- Opponent AI
- Score calculation
- Match completion

Once this is stable, the larger Pokémon RPG and collection systems can be added without replacing the core battle engine.

---

## 36. Long-Term Vision

The completed game may eventually include:

- Full Kanto adventure
- Multiple card sets
- Set-specific variants
- Shiny Pokémon
- Evolution
- Experience
- Trainer progression
- Gym Leaders
- Elite Four
- Wild capture encounters
- Day and night encounter tables
- Location-based terrain
- Seasonal weather
- Booster packs
- Card trading
- Player inventory
- Achievements
- Daily challenges
- Friend battles
- Ranked multiplayer
- Tournaments
- Spectator mode
- Player profiles
- Match replays

The Triple Triad board should remain the foundation of every major system.

---

## 37. Final Design Principle

The project should be developed in layers.

The core 3×3 card battle must be:

- Clear
- Fast
- Responsive
- Strategic
- Easy to understand
- Difficult to master
- Comfortable on a touchscreen

New mechanics should expand the core game rather than bury it under excessive rules.

The game should always feel like Pokémon collection and progression built around a strong Triple Triad battle system.
