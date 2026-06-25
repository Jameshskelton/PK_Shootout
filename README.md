# Penalty Shootout

A 2D World Cup penalty shootout game built in Godot 4 using GDScript. The player takes penalty kicks against an AI goalkeeper, while the opponent's turns are automatically simulated. Standard FIFA shootout rules apply: 5 kicks per team, alternating turns, with sudden death if tied.

## How to Play

1. **Run** the project in Godot 4 (open `project.godot` and press Play, or run from the command line).
2. **Move** the mouse to aim the reticle. It locks to the goal mouth.
3. **Hold** left mouse button to charge the power meter.
4. **Release** to shoot.
5. Watch the goalkeeper dive and see the result (GOAL / SAVED / MISS).
6. After 5 kicks each, the team with more goals wins. Tied? Sudden death.
7. When the match ends, click **PLAY AGAIN** or press **R** to restart.

See `penalty_shootout.md` for a full breakdown of game rules and design.

## Project Structure

```
hackathon_demo/
├── project.godot               # Godot 4 project config (2560x1440 viewport)
├── icon.svg                    # Project icon (soccer ball on pitch)
├── penalty_shootout.md         # Full game design document & implementation plan
├── assets/
│   ├── fonts/                  # (Reserved for future pixel fonts)
│   ├── sfx/                    # (Reserved for future sound effects)
│   └── sprites/                # Game sprite assets
│       ├── ball.png            # Soccer ball sprite
│       ├── goalie.png          # Goalkeeper sprite
│       └── pk_background.png   # Pitch background image
├── scenes/
│   └── Main.tscn               # The single game scene (all nodes defined here)
└── scripts/
    ├── Main.gd                 # Core game logic (~667 lines)
    ├── PowerMeter.gd           # Hold-to-charge power bar
    └── EndScreen.gd            # Win/lose overlay with restart button
```

## Architecture

### Scene Tree

All game objects exist in a single scene (`Main.tscn`), rooted at a `Node2D`. The scene tree looks like this:

```
Main (Node2D)                      # Root — manages match state & orchestrates gameplay
├── Background (Sprite2D)          # Pitch background (pk_background.png, scaled to fill 2560x1440)
├── Goal (Node2D)                  # Positioned at (1280, 880) — goal mouth area
│   ├── Net (ColorRect)            # Invisible mesh area for goal detection
│   ├── GoalFrame (ColorRect)      # Goal posts and crossbar (light outline)
│   └── Goalkeeper (Node2D)        # Positioned at (0, 80) relative to Goal
│       └── KeeperSprite (Sprite2D)# Goalkeeper texture (goalie.png)
├── PenaltySpot (Marker2D)         # Ball start position (1280, 1160)
│   └── SpotVisual (ColorRect)     # Small white circle at penalty spot
├── Ball (Node2D)                  # Ball node (1280, 1160)
│   └── BallSprite (Sprite2D)      # Ball texture (ball.png)
├── AimReticle (Node2D)            # Follows mouse, clamped to goal bounds
│   └── ReticleShape (ColorRect)   # Orange crosshair square
├── PowerMeter (Control)           # Charge bar at bottom of screen
│   ├── Bar (ColorRect)            # Dark background bar
│   └── Fill (ColorRect)           # Green→yellow→red fill
└── UI (CanvasLayer)               # Overlay UI layer
    ├── ScoreLabel (Label)         # "YOU 3 - 2 OPP"
    ├── RoundIndicator (Label)     # "Your turn - Kick 3 of 5"
    ├── ResultLabel (Label)        # "GOAL!" / "SAVED!" / "MISS!" (flashes briefly)
    └── EndScreen (Control)        # Post-match overlay
        ├── Dimmer (ColorRect)     # Dark overlay (0.6 alpha)
        ├── Panel (Panel)          # Centered result box
        │   ├── TitleLabel         # "YOU WIN!" or "YOU LOSE"
        │   ├── ScoreLabel         # "Final Score: YOU 3 - 2 OPP"
        │   ├── DetailLabel        # "Sudden Death Victory" / etc.
        │   └── RestartButton      # "PLAY AGAIN" button
```

### Scripts

#### `Main.gd` (Root script — ~667 lines)

The main script orchestrates the entire game. It contains the state machine, all game systems, and input handling.

**State machine** (`GameState` enum):
| State | Description |
|---|---|
| `KICKOFF_INTRO` | Shows "GET READY!" for 2 seconds, then starts first turn |
| `PLAYER_AIM` | Reticle follows mouse; player can hold/release to shoot |
| `PLAYER_SHOT` | Ball is tweening from spot to target |
| `RESOLVE` | Shot result shown (GOAL/SAVED/MISS) for 1.5s, then advances turn |
| `OPPONENT_TURN` | Auto-simulated AI shot with ball animation |
| `CHECK_RESULT` | After opponent's turn, checks match state (continue/end/sudden death) |
| `MATCH_END` | Match is over; shows end screen |

**Key systems:**
- **Aim system** — Reticle position is clamped to the goal bounds (controlled by `GoalFrame` size). Zone is determined by dividing the goal into a 3x3 grid → 7 zones (corners + mid-sides + center).
- **Shot system** — Power charges from 0→1 over ~1.2s. Low power is weak but accurate. Optimal is mid-range. High power (>0.8) adds ±120px jitter and 20% sky miss chance. Ball position is tweened from penalty spot to target.
- **Goalkeeper AI** — ~40% save rate. Exact zone match = save. Adjacent zone = 15% fingertip save chance. Keeper dives with 0.15s reaction delay. Dive is a parallel tween (position + rotation).
- **Opponent AI** — Corner-weighted zone selection (25/25/20/20/10 for TL/TR/BL/BR/center). Realistic power distribution (15% weak, 50% mid, 35% strong). Keeper uses same ~40% save logic.
- **Match flow** — Alternating kicks (player, opponent). Early-win detection (if uncatchable). Sudden death after tied regulation. Score tracking with round indicator UI.

**Constants** (all tuning values are defined at the top of `Main.gd`):
| Constant | Value | Purpose |
|---|---|---|
| `KICKS_PER_TEAM` | 5 | Standard FIFA shootout kicks |
| `KEEPER_REACTION_DELAY` | 0.15s | Delay before keeper dives (prevents clairvoyance) |
| `KEEPER_SAVE_PROBABILITY` | 0.4 (40%) | Chance of exact zone match save |
| `KEEPER_FINGERTIP_PROBABILITY` | 0.15 (15%) | Chance of save on adjacent zone |
| `POWER_HIGH_THRESHOLD` | 0.8 | Above this → jitter + sky miss risk |
| `JITTER_HIGH_POWER` | 120px | Max jitter offset on high-power shots |
| `MISS_OFFSET` | 160px | Vertical offset on sky misses |
| `RESULT_PAUSE_DURATION` | 1.5s | Time result label is shown |

#### `PowerMeter.gd` (~63 lines)

A simple `Control`-based power bar that charges while the player holds the shoot button.

- `start_charging()` — Begins filling (records start time, makes bar visible)
- `release()` — Stops charging, returns final power (0→1), hides bar
- `get_current_power()` — Returns current charge level (read every frame by `_process()`)
- Fill color changes: green (0–0.4) → yellow (0.4–0.75) → red (0.75–1.0)

#### `EndScreen.gd` (~63 lines)

Post-match overlay that displays results with a fade-in animation.

- `show_result(victory, p_score, o_score, sudden_death)` — Called by `Main.gd -_end_match()`. Sets title color (green for win, red for loss), final score text, and detail label (regulation vs sudden death).
- Fade-in animation: dark dimmer + panel alpha tweened over 0.5s.
- Emits `restart_requested` signal when "PLAY AGAIN" button is pressed.
- Restart handled by `Main.gd -_on_restart_requested()` which reloads the scene.

## Running the Project

### Requirements
- **Godot 4.x** (tested with Godot 4.6, GL Compatibility renderer)
- No external dependencies — everything is built-in GDScript and Scene nodes

### Quick Start
1. Open `project.godot` in Godot 4 editor
2. Press **F5** (or the Play button) to run
3. The game launches directly into the match (no menu screen)

Alternatively, from the command line:
```bash
godot --path /path/to/hackathon_demo --headless  # headless mode
godot --path /path/to/hackathon_demo             # normal mode (requires display)
```

## Game Rules

### Standard Match
1. Two teams alternate penalty kicks (player, opponent, player, ...).
2. Each team gets 5 kicks in regulation.
3. A kick results in: **GOAL** (score +1), **SAVED** (no score), or **MISS** (no score).
4. After all 5 kicks each: higher score wins. If tied → sudden death.

### Sudden Death
- Both teams get 1 kick per round.
- After both have kicked, if scores differ, the match ends.
- If still tied, another round begins.
- Continues until one team scores and the other doesn't.

### Early Win
- If one team mathematically cannot be caught (leader is ahead by more goals than the trailing team has remaining kicks), the match ends early.

### Shooting Mechanics
- **Aim:** Move mouse to position reticle within the goal mouth (clamped).
- **Charge:** Hold left mouse button (power meter fills from 0→1 over ~1.2s).
- **Release:** Ball tweens from penalty spot to reticle position.
- **Power effects:**
  - Low (<0.3): slow ball, keeper has more reaction time
  - Mid (0.3–0.8): accurate and fast
  - High (>0.8): ±120px jitter, 20% chance of skying the ball

### Goalkeeper AI
- Picks dive zone when ball is struck (0.15s reaction delay).
- 40% chance of picking the exact zone → SAVED.
- Otherwise, picks a weighted random zone (biased toward corners).
- Adjacent zones have 15% chance of fingertip save.
- Dive animation: position + rotation tween over ~0.4s.

### Opponent Simulation
- Fully automatic (no player input).
- Zone selection: corner-weighted (TL 25%, TR 25%, BL 20%, BR 20%, Center 10%).
- Power distribution: 15% weak (0.1–0.3), 50% mid (0.4–0.7), 35% strong (0.75–1.0).
- Keeper uses the player's goalkeeper with the same ~40% save logic.

## Asset Notes

### Current Assets
| Asset | File | Usage |
|---|---|---|
| Ball | `assets/sprites/ball.png` | Soccer ball Sprite2D, scaled to fit game |
| Goalkeeper | `assets/sprites/goalie.png` | Goalkeeper Sprite2D, scaled to ~4x |
| Background | `assets/sprites/pk_background.png` | Pitch background, scaled to 2560x1440 |

### Placeholder vs Final
- All visual elements are AI-generated pixel-art style images.
- `ColorRect` nodes are used for:
  - Goal frame (light outline, transparent net area)
  - Aim reticle (orange square)
  - Power meter bar (dark with colored fill)
  - Ball/goalkeeper placeholder shapes (replaced by `Sprite2D` with textures)
- Everything uses `mouse_filter = 2 (IGNORE)` to avoid mouse event consumption.
- Background uses `Sprite2D` with `centered = false` and scale set to fill the viewport.

## Implementation Milestones

The project is built incrementally per `penalty_shootout.md`:

| Milestone | Status | Description |
|---|---|---|
| 0 — Asset Prep | Done | Placeholder rectangles for all visual elements |
| 1 — Project Scaffold | Done | Godot project file, main scene, directory structure |
| 2 — Aim System | Done | Reticle follows mouse, clamped to goal mouth |
| 3 — Shot System | Done | Power meter, ball tween, power-based accuracy jitter |
| 4 — Goalkeeper AI | Done | Dive logic, ~40% save rate, adjacent fingertip chance |
| 5 — Match State Machine | Done | Turn alternation, score tracking, round indicator |
| 6 — Opponent Simulation | Done | Auto-resolved AI turns, corner-weighted zone selection |
| 7 — Win/Lose + Restart | Done | End screen, restart button, sudden death handling |
| 8 — Pixel-Art Pass | Pending | Final sprites, palette-swap teams, pixel font, animations |
| 9 — SFX + Polish | Pending | Sound effects, result labels, final tuning |

## License

This project was built for hackathon demo purposes. Check individual asset files for their respective licenses.