# Pokémon Triad Story Mode Travel System

## Overview

Story Mode uses a **location-based battle path** instead of traditional free-roaming travel. Players select a location, complete its battles and story nodes, and unlock the next major destination.

The system should:

- Work cleanly on mobile
- Keep progression easy to understand
- Support wild Pokémon battles
- Support NPC Trainer battles
- Allow repeated encounters
- Support captures, rare variants, and shiny hunting
- Expand easily into multiple regions

> The first journey through a route is linear. Once completed, the route becomes an open replay hub.

## Main Navigation

```text
Battle
└── Story Mode
```

Story Mode displays a list or map of locations.

```text
KANTO STORY

[ Route 1 ]
[ Viridian City — Locked ]
[ Route 2 — Locked ]
[ Viridian Forest — Locked ]
[ Pewter City — Locked ]
```

Only unlocked locations may be selected. Locked locations appear greyed out and show their unlock requirement.

## Beginning the Journey

After the player:

- Creates their Trainer
- Completes Professor Oak's introduction
- Receives a starter card
- Wakes up in their bedroom
- Finishes the opening tutorial

The first available location is:

```text
Route 1
```

All later locations remain locked.

## Location Introduction

The first time a player selects a location, a short narration introduces it.

```text
ROUTE 1

The road north of Pallet Town winds through grassy fields
and scattered trees.

Pidgey call from the branches while movement stirs beneath
the tall grass.

Viridian City waits at the far end of the route.
```

After the narration, the location's nodes appear.

## Route Battle Path

Each route contains a sequence of battle and story nodes.

Example Route 1:

```text
1. Wild Battle
2. Wild Battle
3. Youngster Joey
4. Wild Battle
5. Item Discovery
6. Lass Natalie
7. Final Wild Battle
8. Viridian City Unlocked
```

The interface may display them as buttons:

```text
[ Wild Battle 1 ]
[ Wild Battle 2 — Locked ]
[ Youngster Joey — Locked ]
[ Wild Battle 3 — Locked ]
[ Item Discovery — Locked ]
[ Lass Natalie — Locked ]
[ Final Wild Battle — Locked ]
```

Or as a vertical path:

```text
Pallet Town
    │
[ Wild Battle ]
    │
[ Wild Battle ]
    │
[ Youngster Joey ]
    │
[ Wild Battle ]
    │
[ Item Discovery ]
    │
[ Lass Natalie ]
    │
[ Final Wild Battle ]
    │
Viridian City
```

## Unlocking Nodes

A node unlocks when the previous required node is completed.

```text
Wild Battle 1 defeated
→ Wild Battle 2 unlocked
```

Completed nodes remain replayable.

Locked nodes should display:

- A lock icon
- Greyed-out appearance
- The required previous node

## Wild Battle Nodes

Wild Battle nodes randomly select a Pokémon from the location's encounter table.

Example Route 1 encounter table:

| Pokémon | Encounter weight |
|---|---:|
| Pidgey | 40 |
| Rattata | 35 |
| Sentret | 10 |
| Spearow | 10 |
| Rare encounter | 5 |

Each replay rerolls the encounter.

A wild encounter may generate:

- Species
- Level
- Gender
- Shiny status
- Directional values
- Bonus side
- Move set
- Trait
- Variant
- Capture Stability

## Wild Pokémon Levels

Wild Pokémon use location-based level ranges.

```json
{
  "locationId": "route_1",
  "wildLevelRange": {
    "min": 2,
    "max": 5
  }
}
```

Recommended early ranges:

| Location | Wild levels |
|---|---:|
| Oak tutorial | 1–3 |
| Route 1 | 2–5 |
| Route 2 | 4–7 |
| Viridian Forest | 5–8 |
| Route 3 | 8–12 |
| Mt. Moon | 10–15 |

Rare encounters may receive a small level bonus.

```text
Common encounter: normal route range
Uncommon encounter: route range +0 to +1
Rare encounter: route range +1 to +2
Final route encounter: route maximum +1
```

A captured Pokémon keeps its exact generated level.

## Trainer Nodes

Trainer nodes use fixed NPC decks and dialogue.

```text
YOUNGSTER JOEY

"I've battled every Pokémon on this route!
My Rattata is tougher than it looks!"
```

Example deck:

```text
Rattata — Level 4
Pidgey — Level 3
Sentret — Level 3
```

Trainer decks should usually be fixed so story battles can be balanced intentionally.

Possible Trainer rewards:

- Coins
- Trainer XP
- Pokémon XP
- Trainer cards
- Items
- Route progress
- Story dialogue
- Rematch unlocks

## First-Clear Rewards

The first time a node is completed, the player receives special rewards.

```text
WILD ENCOUNTER 1 CLEARED

Rewards:
Trainer XP +25
Poké Ball ×2
Route 1 Progress +1
```

First-clear rewards may include:

- Trainer XP
- Coins
- Poké Balls
- Potions
- Booster tickets
- Card materials
- Route mastery
- Story items
- Cosmetics

Repeat battles should not repeatedly grant full first-clear rewards.

## Repeat Battles

Completed Wild Battle nodes remain replayable.

Players may replay them to:

- Gain Pokémon XP
- Catch missing species
- Search for better levels
- Search for stronger directional values
- Find rare traits
- Find card variants
- Hunt shiny Pokémon
- Complete CardDex entries
- Earn route materials
- Complete objectives

Repeat battles should give reduced Trainer XP but normal Pokémon participation XP.

## Capture Integration

Wild Pokémon may be captured during Wild Battles.

A wild Pokémon does not need to be flipped first, but flipping it improves the capture chance.

```text
Place Poké Ball
→ Select adjacent capturable Pokémon
→ Play capture animation
→ Success or failure
```

Only one Poké Ball may be used per battle.

## Poké Ball Placement

Poké Balls are placed on empty board spaces.

When placed:

- Adjacent capturable Pokémon highlight
- The player taps one highlighted target
- Only one Pokémon is selected
- The ball is consumed after the attempt

Example:

```text
        Pidgey
           │
Rattata — Poké Ball — Sentret
```

The player selects one target:

```text
Target: Sentret
```

One Poké Ball can capture only one Pokémon.

## Capture Animation

When a target is selected:

1. The board background blurs
2. The target Pokémon appears in a modal
3. The selected Poké Ball rotates quickly
4. The ball launches toward the Pokémon
5. The Pokémon is drawn into the ball
6. The ball lands
7. It shakes one, two, or three times
8. The Pokémon is captured or breaks free

Success:

```text
Shake 1
Shake 2
Shake 3
Click!

Gotcha!
Pidgey was captured!
```

Failure:

```text
Shake 1
Shake 2

Oh no!
Pidgey broke free!
```

## Captured Card State

On a successful capture, the Pokémon card becomes frozen for the rest of the battle.

The captured card:

- Is greyed out
- Cannot be flipped
- Cannot move
- Cannot attack
- Cannot trigger comparisons
- Cannot trigger combos
- Cannot be targeted
- Remains in its board space
- Is guaranteed as a reward

```text
CAPTURED
Level 4 Pidgey

Card frozen for the remainder of battle.
```

The frozen card should display:

- Desaturated artwork
- Darkened side values
- Poké Ball icon
- Lock icon
- Captured label

## Captured Card and Scoring

Captured cards become neutral.

They do not count toward either player's final score.

```text
Player-controlled cards:   4
Opponent-controlled cards: 3
Captured cards:            1
Unused spaces:             1

Player wins 4–3
```

The captured card continues to block its square.

## Failed Capture

If the Pokémon breaks free:

- The Poké Ball is consumed
- The card remains active
- Ownership does not change
- It can still be flipped
- No second Poké Ball may be used

```text
Pidgey broke free!

Poké Ball use:
1 / 1
```

## Capture Bonuses

The following may improve capture chance:

- Target is already player-controlled
- Target was flipped
- Poké Ball wins its side comparison
- Target is surrounded
- Target has a status condition
- Better Poké Ball is used
- Target has reduced Capture Stability

Example:

```text
Base capture chance:         35%
Player-controlled bonus:    +20%
Sleep bonus:                +15%
Ball comparison bonus:      +10%
Capture resistance:         -20%
---------------------------------
Final chance:                60%
```

## Shiny Encounters

A shiny may appear in any eligible wild node.

A captured shiny keeps its exact generated:

- Species
- Level
- Shiny status
- Directional values
- Move set
- Gender
- Trait
- Bonus side
- Encounter location

```text
Wild encounter:
Level 5 Shiny Sentret

Capture reward:
Level 5 Shiny Sentret
```

Shinies should use:

- Special entrance animation
- Sparkles
- Shiny border
- Sound cue
- Clear shiny label

## Final Route Battle

The final node should feel more important than a standard encounter.

Possible final nodes:

- Strong wild Pokémon
- Rare encounter
- Route guardian
- Mini-boss
- Scripted encounter
- Strong Trainer

Example:

```text
FINAL ROUTE 1 ENCOUNTER

Level 6 Spearow
```

The next location unlocks only after this node is defeated.

## Major Location Unlocks

For Kanto, Route 1 unlocks Viridian City.

```text
ROUTE 1 COMPLETE

Viridian City unlocked!
```

The Story Mode list updates:

```text
[ Route 1 — Complete ]
[ Viridian City ]
[ Route 2 — Locked ]
[ Viridian Forest — Locked ]
```

## Town and City Nodes

Cities may include non-battle nodes.

Example Viridian City:

```text
VIRIDIAN CITY

[ Arrival Scene ]
[ Pokémon Center Tutorial ]
[ Poké Mart — Oak's Parcel ]
[ Trainer School ]
[ Rival Battle ]
[ Route 2 — Locked ]
[ Route 22 — Locked ]
```

Town nodes may contain:

- Dialogue
- Shops
- Quests
- Tutorials
- Card rewards
- Deck checks
- Rival battles
- Branching route unlocks

## Route Completion Mode

After a route is fully completed, it becomes a replay hub.

```text
ROUTE 1 — COMPLETE

[ Random Wild Battle ]
[ Species Hunt ]
[ Youngster Joey Rematch ]
[ Lass Natalie Rematch ]
[ Route Challenges ]
[ Route Research ]
```

The player no longer needs to replay every story node in order.

## Post-Completion Modes

### Random Search

Roll any normal species from the route.

### Species Hunt

Choose a previously discovered species.

```text
[ Hunt Pidgey ]
[ Hunt Rattata ]
[ Hunt Spearow ]
```

### Strong Search

Generate higher-level encounters.

### Rare Search

Improve rare species and variant chances.

### Shiny Hunt

Slightly improve shiny odds after enough route mastery.

### Mastery Challenge

Battle stronger cards under special rules.

## Route Mastery

Each route tracks completion and collection progress.

```text
ROUTE 1

Story Progress:        7 / 7
Wild Species Found:    3 / 4
Wild Species Caught:   2 / 4
Trainer Battles:       2 / 2
Hidden Challenges:     1 / 3
Route Mastery:         46%
```

Possible rewards:

| Mastery | Reward |
|---:|---|
| Story clear | Unlock next location |
| 25% | Route item reward |
| 50% | Species Hunt |
| 75% | Strong Search |
| 100% | Route sleeve, title, or booster |

## Trainer Rematches

Completed Trainer nodes may unlock stronger rematches.

```text
YOUNGSTER JOEY

[ Story Battle — Complete ]
[ Rematch — Level 8 ]
[ Challenge Objective ]
```

Rematches may contain:

- Stronger decks
- Evolved Pokémon
- New move loadouts
- Special rules
- Better rewards
- Unique Trainer cards

## Early Kanto Progression

```text
Pallet Town
Route 1
Viridian City
Route 2 South
Viridian Forest
Route 2 North
Pewter City
Route 3
Mt. Moon
Route 4
Cerulean City
```

Each location defines its own:

- Encounter table
- Level range
- Trainers
- Story nodes
- Rewards
- Capture opportunities
- Route mastery

## Example Route Data

```json
{
  "id": "route_1",
  "name": "Route 1",
  "region": "kanto",
  "unlockRequirement": "oak_intro_complete",
  "wildLevelRange": {
    "min": 2,
    "max": 5
  },
  "nodes": [
    {
      "id": "route_1_wild_1",
      "type": "wild",
      "requiredNode": null
    },
    {
      "id": "route_1_wild_2",
      "type": "wild",
      "requiredNode": "route_1_wild_1"
    },
    {
      "id": "youngster_joey",
      "type": "trainer",
      "requiredNode": "route_1_wild_2"
    },
    {
      "id": "route_1_wild_3",
      "type": "wild",
      "requiredNode": "youngster_joey"
    },
    {
      "id": "route_1_item_scene",
      "type": "story",
      "requiredNode": "route_1_wild_3"
    },
    {
      "id": "lass_natalie",
      "type": "trainer",
      "requiredNode": "route_1_item_scene"
    },
    {
      "id": "route_1_final",
      "type": "wild_boss",
      "requiredNode": "lass_natalie"
    }
  ],
  "completionUnlocks": [
    "viridian_city",
    "route_1_replay_mode"
  ]
}
```

## Recommended First Version

### Route 1 Path

```text
1. Wild Battle
2. Wild Battle
3. Youngster Joey
4. Wild Battle
5. Item Discovery
6. Lass Natalie
7. Final Wild Battle
8. Viridian City Unlocked
```

### Level Ranges

```text
Oak tutorial:            Level 1–3
Route 1 wild Pokémon:    Level 2–5
Youngster Joey:          Level 3–5
Lass Natalie:            Level 4–6
Final Route 1 encounter: Level 5–7
```

### Replay Features

```text
Random Wild Battle
Trainer Rematches
Species Hunt
Shiny Encounters
Route Mastery
```

## Final Design Rule

> Story Mode uses a location-based battle path. Players complete wild battles, Trainer battles, and story scenes to unlock the next major destination. Completed routes remain replayable for experience, captures, CardDex completion, variants, and shiny hunting.
