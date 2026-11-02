# Architecture

How the Godot project is put together, which script owns what, and where to make common changes.
For the game rules themselves, see [design.md](design.md).

## Files

```
cluck_shift/
├── project.godot          # 960x540, GL Compatibility renderer, Sfx autoload, main scene
├── export_presets.cfg     # "Web" preset: no threads, so it runs on itch.io without special headers
├── data/
│   └── rules.json         # starting routes, the 8 hours (belt + supervisor note), pay, strikes (docs/data-format.md)
├── scenes/
│   ├── main.tscn          # the whole game screen
│   └── tray.tscn          # one tray (Area2D)
├── scripts/
│   ├── shift_state.gd     # ShiftState: every rule of the night, no nodes (the part the tests drive)
│   ├── main.gd            # scene glue: state machine, input, spawning, moving trays, HUD
│   ├── belt.gd            # Belt: draws belt, fork, gates, bins; owns the layout points
│   ├── tray.gd            # Tray: path following and drawing
│   └── sfx.gd             # Sfx autoload: named sound hooks (placeholder beeps for now)
├── tests/
│   ├── test_logic.gd      # 132 checks on ShiftState, Tray.advance and rules.json
│   └── test_play.gd       # plays a whole night of main.tscn headless with real key events
└── docs/                  # this folder
```

## Scene tree

```
Main (Node2D)                 main.gd     state machine, input, spawning, HUD text
├── Belt (Node2D)             belt.gd     draws everything static; reads route + scroll
├── Trays (Node2D)                        parent of all live Tray instances (draw order: above Belt)
│   └── Tray (Area2D) ...     tray.gd     one per tray, from tray.tscn
│       └── Shape (CollisionShape2D)      52 x 36 rectangle
├── Fork (Area2D)                         the commit zone; area_entered -> main._on_tray_at_fork
│   └── Shape (CollisionShape2D)          80 x 20 rectangle, placed at Belt.FORK + (0, -25) in _ready
├── SpawnTimer (Timer)                    one-shot; first start after note_seconds, then logic.interval
├── HourTimer (Timer)                     one-shot, hour_seconds; timeout -> HOUR_END; paused during e-stops
└── HUD (CanvasLayer)
    ├── Stats (Label)                     pay, combo, strikes, e-stops, belt speed
    ├── Rules (Label)                     "SUPERVISOR SAYS" board, rebuilt from the current rules each hour
    ├── NoteCard (ColorRect)              yellow sticky note, shown for the first note_seconds of an hour
    │   └── Text (Label)
    └── Dim (ColorRect)                   overlay for menu / hour tally / game over / win
        └── Message (Label)
```

Autoload: `Sfx` (`scripts/sfx.gd`), one `AudioStreamPlayer` per named sound.

## Who owns what

| Script | Owns | Does not do |
|---|---|---|
| `shift_state.gd` (`ShiftState`, RefCounted) | Current hour and clock, applying supervisor notes, the live rules (routes and stamps), route and gate swing, belt speed and interval, pay, combo, strikes, e-stops, the hour tally, picking the next tray (seeded RNG) | Nodes, drawing, sound, input events |
| `main.gd` | Which state the game is in, the two Timers, turning key events into `press_shift`, spawning and moving trays, reacting to the Fork, the note card, rules board, bin labels and HUD text | Any rule arithmetic, or second-guessing a verdict from `ShiftState` |
| `belt.gd` (`Belt`) | Layout constants (`SPAWN`, `FORK`, `EXITS`, `FLOOR`, `DECISION_Y`) and drawing the line, the swing flash and bin labels | Game logic |
| `tray.gd` (`Tray`) | Its kind and stamp, art for every kind (`FOOD`) and stamp (`STAMPS`), its remaining path, whether it has been routed or is falling, its result outline | Deciding where it goes |
| `sfx.gd` (`Sfx`) | Turning a sound name into a sound | Knowing when to play |

The split exists for one reason: **every rule is in a class with no nodes, so it can be tested directly** and the
scene can be rebuilt (Phase 3 art and juice) without touching a rule.

## Data flow

```mermaid
flowchart LR
    J[(data/rules.json)] -->|parsed once| M[main.gd cfg]
    M -->|ShiftState.new cfg<br/>on every clock-in| L[ShiftState]
    K[Shift key events] --> M
    M -->|press_shift side| L
    F[Fork Area2D<br/>area_entered] --> M
    M -->|sort kind| L
    M -->|tick delta| L
    L -->|route, pay, combo,<br/>strikes, speed| M
    M -->|route, scroll| B[Belt drawing]
    M -->|HUD text| H[HUD labels]
    M -->|names| S[Sfx autoload]
```

## The physics frame

`main._physics_process` runs only in PLAYING:

1. `step = logic.tick(delta)`: advances the clock, gate swing, hour and ramp; returns the belt distance (0 during
   an e-stop, when the hour does not advance either).
2. `spawn_timer.paused` and `hour_timer.paused` follow `logic.is_stopped()`; the note card hides after `note_seconds`.
3. Every tray `advance(step)`s along its path. A tray that has been routed and has used up its path has reached its
   bin: play `tray_thunk`, `queue_free()`. Trays already queued for deletion are skipped, because several physics
   frames can run before the idle frame that frees them.
4. HUD and Belt redraw from `logic`.

The physics server then checks overlaps. When a tray's shape first overlaps the Fork's shape, `area_entered` calls
`_on_tray_at_fork(tray)`, which:

1. ignores it unless PLAYING and the tray is not already routed,
2. sets `tray.routed` and calls `logic.sort(tray.kind, tray.stamp)`, which returns `ok`, `wrong` or `missed`,
3. sends the tray to `Belt.EXITS[logic.route]`, or to `Belt.FLOOR` (tumbling) if missed, outlines it green or red,
   and plays `ding`, `strike_buzz` or `missed`,
4. enters GAME_OVER if `logic.sent_home()`.

When the `HourTimer` times out, `_on_hour_over` enters HOUR_END, which clears the belt and calls `logic.end_hour()`.

Collision setup: trays have `monitoring = false` (they never look for anything) and stay `monitorable`. The Fork has
`monitorable = false` and stays `monitoring`. Both are on the default layer and mask 1.

## Input path

`main._unhandled_input` receives key events:

- Released keys and echo (auto-repeat) events are ignored.
- Outside PLAYING, Enter, keypad Enter and Space continue: MENU to PLAYING, HOUR_END to the next hour (or WIN after
  5 AM), GAME_OVER and WIN to MENU. Everything else is ignored.
- In PLAYING, only `KEY_SHIFT` counts. `event.location == KEY_LOCATION_LEFT` means left; anything else means right.
  `logic.press_shift(side)` returns `toggle`, `estop` or `denied`, which picks the sound.

Using `_unhandled_input` (not `_input`) means a future pause menu or UI control can consume keys first.

## How to change things

### Change where a tray kind goes

At 10 PM: edit `routes` in `data/rules.json`. Later in the night: edit that hour's `note` (see
[data-format.md](data-format.md)). The rules board and bin labels follow the rules. Run the tests.

### Add a supervisor note type

1. Handle the new field in `ShiftState.apply_note()` and return the keys it changed.
2. Count it in the "changes exactly one rule" data test in `tests/test_logic.gd` and add a check for its effect.
3. Document it in `docs/data-format.md`.

### Add a new tray kind

1. Add it to `routes` in `data/rules.json`, or have a note add it: `"route": {"tender": "left"}`. It spawns from then.
2. Add its colour to `Tray.FOOD` and a `match` branch in `Tray._draw()` in `scripts/tray.gd`.
3. Run `tests/test_logic.gd`. It fails with "tray art exists for tender" if you skip step 2.

### Retune difficulty

Change an hour's `speed` and `interval` pairs in `data/rules.json`. The data tests fail if trays could overlap or come
less than 0.6 s apart. Re-run `tests/test_play.gd` to check a perfect player can still keep up all night.

### Add a sound

Add a name to `Sfx.TONES` (or, from Phase 3, load a file) and call `Sfx.play("name")` where it should play.
Unknown names are ignored, so a missing sound never crashes the game.

### Add a game state (Phase 2)

1. Add it to `enum State` in `main.gd`.
2. Add a branch to `_enter()` for what happens on entry.
3. Decide in `_unhandled_input` which keys it accepts.
4. Add a check to `tests/test_play.gd` that drives into and out of it.

## Phase 3 hooks

These are the places Phase 3 plugs into. They do not exist yet:

- **Shop**: a SHOP state between HOUR_END and the next PLAYING. `ShiftState` gains `spent`, `buy(item)` and the item
  effects, which `start_hour()` applies (Coffee scales the hour's belt; Earplugs block the PA; Mate's Help is checked
  in `sort()`).
- **PA announcements**: timing in `ShiftState.tick()` (seeded RNG, testable); a banner node in the HUD.
- **Juice**: a `juice.gd` node for popups, particles and camera shake, called from `_on_tray_at_fork`.
- **Title**: a `title.gd` node drawn in the HUD, shown only in MENU.
