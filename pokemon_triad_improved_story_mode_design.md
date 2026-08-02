# Pokémon Triad Improved Story Mode Design

## Overview

Story Mode is the main progression system for the Pokémon Triad app.

The player begins in Pallet Town, receives their starter from Professor Oak, and is asked to retrieve Oak's Parcel from Viridian City.

After Oak's introduction:

- Route 1 unlocks
- All later locations remain locked
- The player completes Route 1 battles and story events
- Viridian City unlocks
- The parcel quest continues

> Each location should contain a mixture of story, battles, exploration, optional objectives, and replay activities.

## Main Story Mode Screen

When the player selects Story Mode, they see a vertical list of location cards.

```text
KANTO JOURNEY

Chapter 1: Oak's Parcel
Main Quest: Reach Viridian City
Region Progress: 3%
Badges: 0 / 8

[ Pallet Town — Available ]
[ Route 1 — Available ]
[ Viridian City — Locked ]
[ Route 2 — Locked ]
[ Viridian Forest — Locked ]
[ Pewter City — Locked ]
```

## Location Cards

Each location card should show:

- Location name
- Artwork
- Current weather
- Time of day
- Short description
- Story progress
- Wild species progress
- Trainer progress
- Completion status
- Unlock requirement

Example:

```text
ROUTE 1

Evening • Light Rain

A narrow route connecting Pallet Town and Viridian City.

Story Progress: 0 / 7
Wild Species: 0 / 4
Trainers Defeated: 0 / 2

[ Enter Route ]
```

Locked example:

```text
VIRIDIAN CITY

Locked

Requirement:
Complete Route 1
```

Completed example:

```text
PALLET TOWN

Story Complete
Side Stories: 1 / 3
Secrets Found: 0 / 2

[ Revisit ]
```

## Story Chapters

### Chapter 1: A New Journey

```text
Pallet Town
Route 1
Viridian City
Return to Pallet Town
```

### Chapter 2: Toward Pewter City

```text
Route 2
Viridian Forest
Pewter City
Pewter Gym
```

### Chapter 3: Across the Mountains

```text
Route 3
Mt. Moon
Route 4
Cerulean City
```

Chapters provide clear regional milestones and organize a long campaign.

## Main Quest System

Oak's Parcel should appear as an active main quest.

```text
MAIN QUEST

Oak's Parcel

Professor Oak is expecting a package from the
Viridian City Poké Mart.

Current Objective:
Reach Viridian City

Rewards:
Trainer XP
Poké Balls
Story Progress
```

Quest stages:

```text
1. Reach Viridian City
2. Visit the Viridian Poké Mart
3. Collect Oak's Parcel
4. Return to Professor Oak
```

The return journey should not require replaying every Route 1 node. Provide a direct return option with a short travel scene.

```text
[ Return to Pallet Town ]
```

## Location Types

### Towns and Cities

Focus on:

- Dialogue
- Shops
- Quests
- Tutorials
- Rival battles
- NPC interactions
- Optional battles
- Route unlocks
- Card rewards

### Routes

Focus on:

- Wild battles
- NPC Trainers
- Item discoveries
- Optional events
- Capture opportunities
- Route mastery
- Wild species completion

### Forests and Caves

May include:

- Multiple sections
- Longer paths
- Environmental hazards
- Limited healing
- Rare encounters
- Hidden routes
- Boss battles
- Special board rules

### Gyms

May include:

- Gym Trainers
- Puzzle nodes
- Special battle rules
- Deck restrictions
- Challenge objectives
- Gym Leader battle

## Route Structure

Routes should contain more than consecutive battles.

Recommended Route 1 structure:

```text
1. Route 1 Introduction
2. Wild Encounter
3. Berry Tree Discovery
4. Wild Encounter
5. Youngster Joey
6. Injured Pidgey Event
7. Wild Encounter
8. Lass Natalie
9. Final Route Encounter
10. Viridian City Arrival
```

## Required and Optional Nodes

Required nodes must be completed to progress.

Optional nodes may provide:

- Items
- Rare encounters
- Side quests
- Additional dialogue
- Route mastery
- CardDex progress
- Cosmetic rewards

Example:

```text
Wild Battle 2
      │
      ├── Continue North
      │
      └── Investigate Rustling Grass
              └── Optional Rare Encounter
```

Optional nodes should never block the main story.

## Story Scenes Between Battles

Short scenes make routes feel alive.

### Berry Tree

```text
A small berry tree grows beside the path.

[ Pick a Berry ]
[ Leave It Alone ]
```

### Injured Pidgey

```text
A frightened Pidgey is trapped beneath a fallen branch.

[ Help the Pidgey ]
[ Continue Forward ]
```

### Lost Item

```text
Something glints in the tall grass.

[ Investigate ]
[ Ignore It ]
```

## Small Story Choices

Choices may affect:

- Small rewards
- NPC reactions
- Friendship
- Optional encounters
- Future dialogue
- Route mastery
- Hidden achievements

They do not need to create completely separate storylines.

## Route Objectives

### Story Objectives

Required for progression.

```text
Defeat the final Route 1 encounter
```

### Exploration Objectives

Examples:

- Encounter every Route 1 species
- Find the hidden Potion
- Speak to every Trainer
- Discover the optional event
- Catch one wild Pokémon

### Challenge Objectives

Examples:

- Win without losing control of the starter
- Trigger a combo flip
- Capture a wild Pokémon
- Successfully defend twice
- Win without using an item

Example summary:

```text
ROUTE 1

Story:       7 / 7
Exploration: 3 / 5
Challenges:  1 / 3
Mastery:     58%
```

## Wild Battle Nodes

Wild nodes randomly select from the location's encounter pool.

| Pokémon | Encounter Weight |
|---|---:|
| Pidgey | 40 |
| Rattata | 35 |
| Sentret | 10 |
| Spearow | 10 |
| Rare Encounter | 5 |

Each encounter may generate:

- Species
- Level
- Gender
- Shiny status
- Directional values
- Move set
- Trait
- Variant
- Capture Stability

Completed wild nodes remain replayable.

## Trainer Nodes

Trainer nodes use fixed decks and unique dialogue.

Example:

```text
YOUNGSTER JOEY

"My Rattata is tougher than it looks!"
```

Trainer nodes may include:

- First-clear dialogue
- Victory dialogue
- Defeat dialogue
- Rematch dialogue
- Challenge objectives
- Stronger rematch decks

## Arrival Scenes

Major locations should have short arrival scenes.

```text
VIRIDIAN CITY

The paved streets of Viridian City are busier than
anything you have seen in Pallet Town.

Trainers move between the Pokémon Center and the
Poké Mart while Route 2 stretches north beyond the city.
```

Then display city nodes:

```text
[ Poké Mart ]
[ Pokémon Center ]
[ Trainer School ]
[ Explore City ]
[ Route 2 — Locked ]
```

## Viridian City Example

```text
VIRIDIAN CITY

[ Arrival Scene ]
[ Pokémon Center Tutorial ]
[ Poké Mart — Oak's Parcel ]
[ Trainer School ]
[ Explore City ]
[ Rival Battle ]
[ Route 2 — Locked ]
[ Route 22 — Locked ]
```

Not every node must be a battle.

## Story Battle Rules

Important locations may introduce special board rules.

### Route 1

```text
Tall Grass

Some wild Pokémon receive a defensive bonus
while occupying grass spaces.
```

### Viridian Forest

```text
Dense Forest

Bug Pokémon begin with an additional move charge.
Flying movement effects have reduced range.
```

### Pewter Gym

```text
Rock-Solid Defense

The Gym Leader's Pokémon begin with Armor.
```

## Weather and Time

Location cards should display current weather and time.

Weather may affect:

- Dialogue
- Artwork
- Ambient audio
- Encounter weights
- Certain species
- Capture modifiers
- Optional events
- Specialized Poké Balls
- Move effects

Weather should add atmosphere without blocking progression.

## First-Clear Rewards

Possible first-clear rewards:

- Trainer XP
- Poké Balls
- Potions
- Trainer cards
- Card sleeves
- Deck boxes
- Titles
- Battle Bag slots
- Route Search modes
- Location backgrounds
- CardDex information

Example:

```text
ROUTE 1 COMPLETE

Rewards:
Viridian City unlocked
Route 1 Replay Hub unlocked
Species Hunt unlocked
Poké Ball ×3
Trainer XP +100
Route 1 background
```

## Replay Mode

Completed routes become replay hubs.

```text
ROUTE 1 — COMPLETE

Story:
[ Replay Route Story ]

Activities:
[ Random Wild Battle ]
[ Species Hunt ]
[ Trainer Rematch ]
[ Route Challenges ]
[ Route Research ]
[ Shiny Hunt ]
```

Players should not need to replay the entire route story to access wild battles.

## Post-Completion Activities

### Random Wild Battle

Roll any normal wild species from the route.

### Species Hunt

Target a previously discovered species.

```text
[ Hunt Pidgey ]
[ Hunt Rattata ]
[ Hunt Spearow ]
```

### Trainer Rematches

Fight stronger versions of completed Trainers.

### Route Challenges

Special objectives and restrictions.

### Route Research

Reveal encounter rates, levels, rare species, weather effects, and secrets.

### Shiny Hunt

Unlock after sufficient mastery and slightly improve shiny encounter chances.

## Route Mastery

```text
ROUTE 1

Story Progress:        7 / 7
Wild Species Found:    3 / 4
Wild Species Caught:   2 / 4
Trainer Battles:       2 / 2
Hidden Events:         1 / 3
Challenge Objectives:  2 / 5
Route Mastery:         54%
```

| Mastery | Reward |
|---:|---|
| Story clear | Unlock next location |
| 25% | Route item reward |
| 50% | Species Hunt |
| 75% | Strong Search |
| 100% | Exclusive sleeve, title, or booster |

## Locked Location Previews

Locked locations should remain visible.

```text
PEWTER CITY

Locked

A stone city near the base of the mountains.

Known Features:
• Pewter Gym
• Museum
• Poké Mart

Requirement:
Complete Viridian Forest
```

This creates anticipation and shows the player where the journey is heading.

## Recommended Route 1 Design

```text
1. Opening Scene
2. Wild Encounter
3. Berry Tree Discovery
4. Wild Encounter
5. Youngster Joey
6. Optional Pidgey Rescue
7. Wild Encounter
8. Lass Natalie
9. Final Wild Encounter
10. Viridian City Arrival
```

Main requirement:

```text
Defeat the final wild encounter
```

Optional goals:

```text
Catch Pidgey
Catch Rattata
Find the hidden Potion
Defeat both Trainers
Complete one capture
Help the injured Pidgey
```

Completion rewards:

```text
Viridian City unlocked
Route 1 Replay Hub unlocked
Species Hunt unlocked
Poké Ball ×3
Trainer XP +100
```

## Recommended Screen Structure

```text
Story Mode
│
├── Chapter Header
├── Active Main Quest
├── Region Progress
├── Badge Progress
│
├── Vertical Location List
│
├── Pallet Town
│   ├── Story scenes
│   ├── Oak's Lab
│   ├── Player's House
│   └── Side quests
│
├── Route 1
│   ├── Required story nodes
│   ├── Optional events
│   ├── Wild battles
│   ├── Trainer battles
│   ├── Capture opportunities
│   └── Route mastery
│
└── Viridian City
    ├── Arrival scene
    ├── Poké Mart
    ├── Pokémon Center
    ├── Trainer School
    ├── Rival battle
    └── Next route unlock
```

## Final Design Rules

1. Story Mode uses a vertical location list.
2. Professor Oak's dialogue unlocks Route 1.
3. All later locations remain locked until their requirements are met.
4. Route 1 must be completed before Viridian City unlocks.
5. Locations contain story, battles, exploration, and optional events.
6. Routes use required and optional nodes.
7. The active main quest remains visible.
8. Towns and cities contain more than battles.
9. Completed routes become replay hubs.
10. Route mastery rewards exploration and collection.
11. Locked locations remain visible as previews.
12. Chapters organize the regional story.
13. Weather, time, artwork, and ambience give locations identity.
14. Important battles may use unique board rules.
15. Story progression and repeatable grinding remain separate.

> The player should always know where they are, what their next objective is, what they have completed, and what destination they are working toward.
