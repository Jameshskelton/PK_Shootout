# Penalty Shootout — Game Design & Implementation Plan

## 1. Overview
A 2D World Cup penalty shootout game built in Godot 4 (GDScript). The player takes turns shooting penalties against an AI goalkeeper; the opponent's turns are auto-simulated. Standard FIFA shootout rules: best of 5 kicks each (alternating), then sudden death.

**Scope:** Minimal MVP. Core loop only — no menus, 3 teams (palette swaps), pixel-art visuals, simple SFX.

## 2. Tech Stack
- **Engine:** Godot 4.x
- **Language:** GDScript
- **Rendering:** 2D (`CanvasItem` / `Node2D`)
- **Physics:** Lightweight — tweened ball motion (no full RigidBody simulation needed)

## 3. Scene Architecture

```
Main (Node2D)                      <- root, holds match state
├── Background (Sprite2D)          <- pitch + crowd (pixel-art, static)
├── Goal (Node2D)
│   ├── GoalFrame (Sprite2D)      <- posts + crossbar (pixel-art)
│   ├── Net (Sprite2D)            <- net graphic (crosshatch texture)
│   └── Goalkeeper (Sprite2D)     <- dives via tween (pixel-art, 4-6 frames)
├── Ball (Sprite2D)               <- tweened to target on shot (pixel-art)
├── PenaltySpot (Marker2D)        <- ball start position
├── AimReticle (Sprite2D)         <- follows mouse, clamped to goal area (pixel-art crosshair)
├── PowerMeter (Control)          <- hold-to-charge bar
└── UI (CanvasLayer)
    ├── ScoreLabel                <- "BRA 2 - 1 GER"
    ├── RoundIndicator            <- "Kick 3 of 5" / "Sudden Death"
    ├── ResultLabel               <- "GOAL!" / "SAVED!" / "MISS!"
    └── EndScreen                 <- "You Win/Lose" + restart button
```

## 4. Core Systems

### 4.1 Aim System
- `AimReticle` follows mouse position, clamped to a rectangle covering the goal mouth.
- Visible only during the player's aiming phase.
- Reticle position = intended target spot inside (or just outside for misses) the goal.
- Reticle can drift slightly with higher power to simulate reduced accuracy.

### 4.2 Power & Shot System
- On mouse-down: `PowerMeter` begins filling (hold to charge, 0→1 over ~1.2s).
- On mouse-release: shot fires. Power affects ball speed and accuracy:
  - Low power → slow ball, keeper more likely to save.
  - Optimal mid-range → fast + accurate.
  - Too high → accuracy drops (target shifts randomly), risk of skying over bar.
- Ball travels from `PenaltySpot` toward `AimReticle` position via a `Tween` (linear + small arc via scale/Z for depth illusion).
- Final target zone determined by reticle position + power-induced accuracy jitter.

### 4.3 Goalkeeper AI
- Keeper picks a dive direction **when the ball is struck** (small reaction delay of ~0.15s to avoid clairvoyance).
- Dive logic:
  - 6 zones: top-left, mid-left, bottom-left, top-right, mid-right, bottom-right, center.
  - Weighted random selection; slight bias toward corners where player tends to aim.
  - **~40% save rate target:**
    - Exact zone match → **SAVE** (counts toward the 40%).
    - Adjacent zone → small chance of fingertip save (15%).
    - Otherwise → **GOAL**.
- Keeper dive is a tween (rotation + position) over ~0.4s, with pixel-art frame swap mid-dive.

### 4.4 Opponent Turn Simulation
- Fully automatic: AI shooter picks a zone + power, AI keeper (player's side) picks a zone. Resolve save/goal. Show a brief ball animation. No player input.
- **Corner-weighted zone selection** (mimics real penalty tendencies):
  - Top-left: ~25%
  - Top-right: ~25%
  - Bottom-left: ~20%
  - Bottom-right: ~20%
  - Center: ~10%

### 4.5 Match State Machine
States: `KICKOFF_INTRO` → `PLAYER_AIM` → `PLAYER_SHOT` → `RESOLVE` → `OPPONENT_TURN` → `RESOLVE` → `CHECK_RESULT` → (loop or `MATCH_END`)

- Tracks: player score, opponent score, current kick number, which team's turn, phase.
- Standard rules: after 5 kicks each, higher score wins. If tied → sudden death (one kick each, first to be ahead after equal kicks wins).
- Early-win check: if one team can't be caught with remaining kicks, end early.

### 4.6 Result Resolution
After ball + keeper resolve:
- **GOAL:** ball settles in net, `ResultLabel` flashes "GOAL!", increment score.
- **SAVE:** keeper deflects ball away, "SAVED!".
- **MISS:** ball flies wide/over, "MISS!" (no score).
- Brief 1.5s pause, then advance to next kick.

## 5. Asset List (pixel-art)
- **Pitch background:** pixel-art 3-quarter view field with line markings, crowd silhouettes in stands.
- **Goal frame + net:** pixel-art goal with crosshatch net texture.
- **Goalkeeper sprite:** pixel-art, idle + dive frames (4-6 frames: idle, dive-left, dive-right, dive-center-high, dive-center-low). Drawn facing forward.
- **Ball sprite:** pixel-art ball (16x16 or 32x32), optional simple roll animation frames.
- **Reticle:** pixel-art crosshair/target.
- **Player/shooter sprite:** pixel-art player at the spot (1-2 frames). Color-tinted per team.
- **Teams:** 3 pixel-art kit variations (yellow, red, blue) — palette swaps of one base sprite.
- **SFX:** ball kick, net ripple, save, crowd cheer, whistle.
- **Fonts:** monospace or pixel font (e.g., "Press Start 2P" style) for cohesive aesthetic.

## 6. Team Selection (minimal)
- 3 teams as color variants (yellow, red, blue kits).
- Random opponent at match start (or fixed pairing for MVP).
- Team choice stored as a color value applied to shooter sprite + score label.

## 7. Implementation Milestones

| # | Milestone | Deliverable |
|---|-----------|-------------|
| 0 | Asset prep | Create placeholder rectangles (goal, keeper, ball, background). Use until final pixel-art is ready. |
| 1 | Project scaffold | Godot project, main scene, background + goal + ball + penalty spot placed. |
| 2 | Aim system | Reticle follows mouse, clamped to goal mouth. |
| 3 | Shot system | Power meter, ball tween from spot to target on release. |
| 4 | Goalkeeper AI | Keeper dives to 6 zones, ~40% save logic with adjacent fingertip chance. |
| 5 | Match state machine | Turn alternation, score tracking, round indicator. |
| 6 | Opponent simulation | Auto-resolved AI turns, corner-weighted zone selection. |
| 7 | Win/lose + restart | End screen, restart button, sudden death handling. |
| 8 | Pixel-art pass | Drop in final sprites, palette-swap teams, pixel font, animation frames for keeper dive + ball. |
| 9 | SFX + polish | Kick, net, save, cheer, whistle sounds; result labels; brief celebration. |

## 8. Asset Sourcing Strategy
- **Placeholder-first:** Use simple colored rectangles for all sprites during milestones 0-7 so the gameplay loop is fully testable before final art.
- **Final pixel-art:** Create or source pixel-art sprites before milestone 8. Options:
  - Draw pixel-art directly (Aseprite, Piskel, or Godot's tile editor).
  - Use free CC0 pixel-art packs (itch.io / OpenGameArt) for goal/keeper/ball.
  - Generate pixel-art assets via an image tool.
- Palette swaps for teams applied via Godot's `modulate` or `self_modulate` property on a single base sprite.

## 9. Out of Scope (for MVP)
- Menus, settings, difficulty selection.
- Player-controlled goalkeeping.
- Tournament brackets / multiple matches.
- Player names, stats, leaderboards.
- Replays, slow-mo, camera shake.
- 3D graphics, real physics simulation.

## 10. Key Tuning Constants

| Constant | Value | Notes |
|----------|-------|-------|
| Keeper save rate (target) | ~40% | Exact zone match + adjacent fingertip (15%). |
| Keeper reaction delay | 0.15s | Prevents clairvoyant keeper. |
| Power charge time | 1.2s | 0→1 on hold. |
| Keeper dive duration | 0.4s | Tween + frame swap. |
| Result pause duration | 1.5s | Before next kick. |
| Opponent corner weight | 90% | 25/25/20/20 split for corners vs 10% center. |
| Kicks per team (regular) | 5 | Standard shootout. |
| Sudden death | Yes | One kick each, first ahead after equal kicks wins. |
