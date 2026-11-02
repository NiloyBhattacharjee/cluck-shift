# Testing

Two headless test scripts, no add-ons. Each prints one `ok` or `FAIL` line per check and exits with code 0 only if
every check passed. CI runs both on every push and pull request ([`.github/workflows/test.yml`](../.github/workflows/test.yml)).

## Running

```bash
# once, after cloning (registers class_name scripts)
godot --headless --path . --import

godot --headless --path . -s tests/test_logic.gd
godot --headless --path . --fixed-fps 60 -s tests/test_play.gd
```

`godot` is your Godot 4.7 binary (on Windows, the `_console.exe` build shows the output). `--fixed-fps 60` makes the
play test run 150 s of game time in about a second, frame for frame the same as real time.

## tests/test_logic.gd: the rules (44 checks)

Drives `ShiftState` directly. No scene, no timing.

| Group | What it proves |
|---|---|
| Gates | Gates start closed (straight). Each Shift toggles its gate. Opening one closes the other. The same Shift twice quickly is two toggles, not a stop. |
| Emergency stop | Both Shifts within the window stop the belt and use one charge. The gate is left as it was before the pair. The belt neither moves nor ramps while stopped. Gates work during a stop. A second stop during a stop is refused. The belt restarts after `estop_seconds`. With no charges left it is refused and the gate is unchanged. Shifts further apart than the window are two toggles. |
| Scoring and combo | A correct sort pays `pay_per_tray`. x1 for the first 4 in a row, x2 on the 5th. A wrong sort is a strike and resets the combo but costs no pay. Best combo is kept. Accuracy is correct over sorted, and 0 when nothing is sorted. The multiplier caps at 5. |
| Strikes | One short of `strikes_allowed` is still working; reaching it is sent home. |
| Belt ramp | Starts at the configured values, speeds up, and stops at `max_speed` and `min_interval`. |
| Tray path | `Tray.advance` moves along a leg, carries leftover distance round a corner, and stops at the end. |
| Data | Every route is a real exit and every kind has art. Trays can never overlap. At full speed trays are at least 0.6 s apart. The ramp goes the right way. |

## tests/test_play.gd: the real game (17 checks)

Loads `scenes/main.tscn` and plays it through `Viewport.push_input` key events, the real `Timer` and the real
Fork `Area2D` overlap.

**Run 1: autoplayer, 150 s.** Each frame it finds the front tray that has not been routed yet, looks up its exit in
`rules.json`, and presses the one Shift that sets that route (at most once every 0.25 s, like a fast human). At 5 s
it presses both Shifts in the same frame. Checks:

- the game opens on the menu and Enter clocks in,
- both Shifts stop the belt, no tray moves during the stop, and the spawn timer is paused,
- after 150 s: no strikes, at least 60 trays sorted (it gets about 109), the belt reached top speed,
  exactly one emergency stop used, still on shift.

That last group is the main balance check: **at full speed a player who reads the tray and presses once can sort
everything**. If a tuning change breaks that, this test fails.

**Run 2: idle player.** A fresh shift where nobody presses anything (the gate stays straight, so wings and
drumsticks are strikes). Checks:

- the game ends on exactly `strikes_allowed` strikes and shows the SENT HOME screen,
- the belt is frozen after game over and Shift does nothing,
- Enter starts a new shift with 0 strikes, $0, full emergency stops, old trays cleared and one new tray.

A frame limit (240 s of game time) fails the run instead of hanging if something stops progressing.

## Checking the tests catch bugs

During Phase 1 the rules were deliberately broken to make sure the suites notice:

| Mutation | test_logic | test_play |
|---|---|---|
| `sort()` compares with `!=` instead of `==` | 10 failures | 5 failures |
| Both-Shift detection always false | 8 failures | not run |

Repeat this when changing a rule: break it, see a test fail, fix it.

## Manual playtest checklist (Phase 1)

Automated tests cannot judge feel. Before a release, play once and confirm:

- [ ] The title screen shows the controls; Enter starts.
- [ ] Left Shift and Right Shift each light their own gate box, chute and bin. Pressing the lit one again goes straight.
- [ ] A tray that crosses the red line goes where the lit route was at that moment, and is outlined green or red.
- [ ] Ding on correct, buzz on wrong, thunk when a tray lands, click on every gate change.
- [ ] Combo and x-multiplier rise; pay jumps by $20 on the 5th in a row.
- [ ] Both Shifts together: STOPPED! shows, the belt freezes for about 2.5 s, E-STOPS goes down by one.
- [ ] After 3 e-stops, both Shifts just buzz.
- [ ] Third strike: SENT HOME with pay, trays, accuracy and best combo. Enter starts clean.
- [ ] After about 2 minutes the belt is at 2.5x and still playable.
- [ ] Web build: the same, in Chrome and Firefox, after clicking the page once.
