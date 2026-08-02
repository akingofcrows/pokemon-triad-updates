# Pokémon Triad Experience and Leveling System

## Overview

Pokémon should not gain experience only when they flip an opposing card. A flip-only system makes defensive, support, terrain, and status-focused Pokémon progress too slowly.

The recommended system rewards **meaningful participation**:

- Placement
- Direct flips
- Combo flips
- Assists
- Useful move effects
- Status application or removal
- Successful defense
- Match survival
- Victory
- Optional battle objectives

> Pokémon gain experience for meaningful participation, not merely for delivering the final flip.

## Base XP Rewards

| Action | XP |
|---|---:|
| Placed on the board | 4 |
| Directly flip an enemy card | 5 |
| Trigger a combo flip | 3 per card |
| Assist an allied flip | 2 |
| Trigger a useful move effect | 2 |
| Apply a valid status | 2 |
| Remove a status | 2 |
| Protect or support an ally | 2 |
| Successfully resist a capture | 2 |
| Remain allied at match end | 2 |
| Team wins | 6 |
| Match ends in a draw | 3 |
| Match MVP | 3 |
| Complete a battle objective | 2–5 |

These are starting values and should be adjusted through playtesting.

## Participation XP

A Pokémon receives 4 XP the first time it is placed during a match.

This ensures that opening cards, defensive cards, and support Pokémon still progress even when they do not flip an opponent.

A Pokémon should not repeatedly receive placement XP if an effect removes and redeploys it.

## Direct and Combo Flips

A direct flip grants 5 XP.

Combo flips grant 3 XP each.

Example:

```text
Placed:             4 XP
Direct flip:        5 XP
Two combo flips:    6 XP
Victory:            6 XP
Survival:           2 XP
------------------------
Total:             23 XP
```

Combo flips award slightly less because they may resolve automatically after the first capture.

## Assist XP

A Pokémon receives 2 XP when its effect directly helps another allied Pokémon flip a card.

Examples:

- Bulbasaur Roots a target before an ally captures it.
- Squirtle pushes an enemy beside a stronger allied side.
- Pidgey exposes a weak side with Gust.
- Charmander applies Burn, reducing the target's strongest side.
- Pikachu applies Paralysis and disables a reaction.
- A terrain effect supplies the point needed to win a comparison.
- A support move increases an ally's attacking side.
- A move removes Armor, Shield, or Guard before the capture.

The server should track meaningful effects until the affected card is flipped, the effect expires, or the card leaves play.

Recommended cap:

```text
Maximum assist XP caused by one captured card: 4 XP
```

## Useful Move XP

A move grants 2 XP when it produces a meaningful result.

Qualifying examples:

- Successfully applying Burn, Poison, Paralysis, Sleep, Wet, Rooted, or Freeze
- Moving an enemy card
- Protecting an ally
- Removing a status
- Destroying a hazard
- Breaking Armor or Shield
- Revealing a hidden side that is later used
- Trapping a card
- Restoring Condition or a move charge
- Redirecting an attack

A move does not receive XP merely for being activated.

Examples that should not award XP:

- Applying a non-stacking status that is already active
- Healing a Pokémon already at full Condition
- Using a status move against an immune target
- Replacing identical terrain without creating a new effect

## Defensive XP

A Pokémon receives 2 XP when an enemy attempts to capture it and it remains under allied control.

Defense may come from:

- A stronger printed side
- Type resistance
- Armor
- Shield
- Guard
- Terrain
- A support effect
- A defensive move

Recommended cap:

```text
Maximum defense XP per Pokémon per match: 6 XP
```

## Survival and Victory

A Pokémon receives 2 XP if it remains under the player's control when the match ends.

Every participating Pokémon receives:

```text
Victory: 6 XP
Draw:    3 XP
Loss:    No result bonus
```

Pokémon still keep participation and action XP after a loss.

## MVP

One participating Pokémon may receive 3 bonus XP as Match MVP.

MVP scoring should consider:

- Direct flips
- Combo flips
- Assists
- Useful effects
- Successful defenses
- Survival
- Objectives

The Pokémon with the most flips should not automatically become MVP.

## Examples

### Support Bulbasaur

```text
Placed:                  4 XP
Leech Seed effect:       2 XP
Capture assist:          2 XP
Survival:                2 XP
Victory:                 6 XP
-----------------------------
Total:                  16 XP
```

### Offensive Pidgey

```text
Placed:                  4 XP
Two direct flips:       10 XP
Survival:                2 XP
Victory:                 6 XP
-----------------------------
Total:                  22 XP
```

### Defensive Squirtle

```text
Placed:                  4 XP
Withdraw effect:         2 XP
Two successful defenses: 4 XP
Victory:                 6 XP
-----------------------------
Total:                  16 XP
```

Squirtle receives no survival XP if it is controlled by the opponent when the match ends.

## Encounter Modifiers

| Encounter | Modifier |
|---|---:|
| Practice match | ×0.25 |
| Tutorial match | ×0.50 |
| Common wild encounter | ×1.00 |
| Strong wild encounter | ×1.20 |
| NPC Trainer | ×1.25 |
| Gym Trainer | ×1.40 |
| Rival battle | ×1.50 |
| Gym Leader | ×1.75 |
| Story boss | ×1.75–2.00 |
| Standard PvP | ×1.00 |
| Tournament | ×1.25 |

Example:

```text
Base XP: 20
Gym Trainer modifier: ×1.40
Final XP: 28
```

## Opponent Strength Modifier

| Opponent difference | XP change |
|---|---:|
| Equal or weaker | Normal |
| 2–4 levels higher | +20% |
| 5–9 levels higher | +40% |
| 10+ levels higher | +60% |
| 5–9 levels lower | −25% |
| 10–14 levels lower | −50% |
| 15+ levels lower | Minimum XP |

This prevents Route 1 farming from remaining optimal forever.

## Repeated Encounter Diminishing Returns

| Repeated victories | XP rate |
|---|---:|
| First 5 | 100% |
| Victories 6–10 | 75% |
| Victory 11 onward | 50% |

The penalty may reset daily or after the player battles several different opponents.

## PvP Anti-Farming

Recommended rules:

- Reduced XP against the same player repeatedly
- No XP for immediate forfeits
- Minimum turn requirement
- Daily PvP XP cap
- Full rewards for normal matchmaking
- Separate tournament reward rules

Example:

```text
First 3 matches against same player: 100%
Matches 4–5:                         50%
Further matches:                     10%
```

## Unused Pokémon and EXP Share

Pokémon that are never placed normally receive no XP.

An EXP Share may grant unused deck Pokémon a small amount:

```text
Unused Pokémon receive 20% of participation and victory XP.
```

EXP Share should not grant:

- Flip XP
- Combo XP
- Assist XP
- Defense XP
- MVP XP
- Objective XP

## Example XP Curve

| Level | XP to next level |
|---:|---:|
| 1 → 2 | 40 |
| 2 → 3 | 55 |
| 3 → 4 | 75 |
| 4 → 5 | 100 |
| 5 → 6 | 135 |
| 6 → 7 | 175 |
| 7 → 8 | 225 |
| 8 → 9 | 285 |
| 9 → 10 | 355 |
| 10 → 11 | 435 |
| 11 → 12 | 525 |
| 12 → 13 | 625 |
| 13 → 14 | 740 |
| 14 → 15 | 870 |
| 15 → 16 | 1,015 |

At approximately 15–25 XP per meaningful match, early levels arrive regularly while evolution still requires sustained use.

## Evolution Pacing

Level should remain the main evolution requirement, but some Pokémon may also require:

- A minimum number of matches
- A minimum number of victories
- Friendship
- Species mastery
- Story progress
- Route discovery
- Move mastery
- An evolution item
- A time-of-day condition
- A special achievement

Example:

```text
Bulbasaur evolution requirements:

Level 16
Participated in at least 20 victories
Completed the Growth milestone
```

Additional requirements should be used selectively rather than applied to every species.

## Optional Battle Objectives

Examples:

- Win without losing control of the starter.
- Trigger a three-card combo.
- Use a super-effective move.
- Successfully defend twice.
- Apply two different statuses.
- Win without using a Trainer card.
- Capture the wild target from its weakest side.

Suggested reward:

```text
Objective completed: 2–5 XP
```

## Post-Match XP Summary

Players should see exactly why each Pokémon gained XP.

```text
BULBASAUR — 16 XP

Placed                  +4
Leech Seed              +2
Capture Assist          +2
Match Survival          +2
Victory                 +6
```

This teaches players that support, defense, and positioning are valuable.

## Server Tracking

The server should record:

- Pokémon placed
- Direct flips
- Combo flips
- Move effects
- Status applications and removals
- Side modifiers
- Successful defenses
- Card ownership at match end
- Assist contributors
- Match result
- Encounter type
- Opponent strength
- Repeated encounter count
- PvP opponent history
- Completed objectives

All XP must be calculated by the server.

## First-Version Rules

1. Placement awards 4 XP.
2. Direct flips award 5 XP.
3. Combo flips award 3 XP.
4. Valid assists award 2 XP.
5. Useful move effects award 2 XP.
6. Successful defenses award 2 XP.
7. Survival awards 2 XP.
8. Victory awards 6 XP.
9. Draws award 3 XP.
10. MVP awards 3 XP.
11. Unused Pokémon receive no XP without EXP Share.
12. Strong opponents provide bonus XP.
13. Weak opponents provide reduced XP.
14. Repeated encounters use diminishing returns.
15. PvP rewards include anti-farming limits.
16. The post-match screen explains every XP source.
17. Evolution requires sustained progression.

## Balance Principles

- Every useful role should progress.
- Direct flips should remain highly rewarding.
- Support Pokémon should not be punished.
- Defensive placement should matter.
- Losses should still provide some progression.
- Strong opponents should be more rewarding.
- Weak encounter farming should become inefficient.
- Evolution should feel earned.
- XP calculations should be transparent.
