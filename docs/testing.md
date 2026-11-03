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
play test run a whole 10-minute night in about five seconds, frame for frame the same as real time.

## tests/test_logic.gd: the rules (161 checks)

Drives `ShiftState` directly. No scene, no timing.

| Group | What it proves |
|---|---|
| Gates | Gates start closed. Each Shift toggles its gate; opening one closes the other. The same Shift twice is two toggles, not a stop. Gates close at the start of each hour. |
| Gate swing | A toggle starts the swing. A tray at the red line during the swing is missed: a strike that resets the combo. After `swing_seconds` the tray goes where the gate points. Wrong is not missed. |
| Emergency stop | Both Shifts within the window stop the belt, use a charge, leave the gate as it was. While stopped the belt does not move or ramp and the hour does not run down. Gates work during a stop. No stacking. Restarts after `estop_seconds`. Charges are per night. With none left: refused, gate unchanged. Shifts further apart than the window are two toggles. |
| Scoring and combo | $10 per correct tray, x2 on the 5th in a row, capped. Wrong: strike, combo reset, no pay lost. Best combo kept. Accuracy is correct / sorted (0 when nothing sorted). The combo carries into the next hour. |
| Strikes per hour | One short is still working. Strikes reset each hour. 3 in one hour is sent home. |
| Clock | Hours are named 10 PM to 6 AM. The clock reads 10:00 PM, 10:30 PM halfway, never shows the next hour early, and the last hour is 5 AM. |
| Belt per hour | Each hour starts at its first speed and interval, rises linearly, stops at its second value; the next hour starts at its own speed. |
| Supervisor notes | Replays every note in order: 10 PM changes nothing; nuggets move right; red stamps go straight and beat the kind; tenders appear; the 2 AM swap moves every left/right rule but not straight, and marks exactly what moved; by 5 AM red is cancelled, blue goes left and wings go straight. Notes never change the data a new night starts from. |
| Hour tally | A clean hour earns the bonus and the tally names the hour; no bonus after a strike or with nothing sorted. |
| Spawning | Before any stamp rule there are only the three kinds and no stamps. With a stamp rule about `stamp_chance` of trays are stamped. A kind added by a note starts spawning. |
| Shop | Can't buy with an empty wallet, and a refused purchase changes nothing. Buying takes the price off the wallet, not off what you earned. Unknown items can't be bought. One dollar short is still too short. |
| Items | Coffee slows the belt and spaces trays by the same factor (gap unchanged) and lasts one hour. Mate's Help covers a wrong tray (no strike, combo still breaks, no pay), only once, lasts across hours until used, and covers a missed tray too (which still falls). |
| PA | None before `pa.from_hour`; from then the PA interrupts within the note time plus `every` max, keeps interrupting through the hour, each lasting `pa.seconds`. Earplugs: no PA all hour; they last one hour. |
| Tray path | `Tray.advance` follows a leg, carries leftover distance round a corner, stops at the end; a missed tray tumbles. |
| Data | 8 hours; each hour's belt speeds up, never overlaps trays, keeps at least 0.6 s per tray; every note has text and changes exactly one rule (none at 10 PM) with real exits; every kind and stamp has art; `stamp_chance` and `swing_seconds` are sensible; the shop is exactly the three known items with names, text and prices; `coffee_factor` is sensible; PA announcements can't overlap and have enough lines. |

## tests/test_play.gd: the real game (137 checks)

Loads `scenes/main.tscn` and plays it through `Viewport.push_input` key events, the real `SpawnTimer` and
`HourTimer`, and the real Fork `Area2D` overlap.

**Run 1: a full night with an autoplayer.** Each frame it finds the front tray that has not been routed, asks
`ShiftState.exit_for(kind, stamp)` where it belongs under the current rules, and presses the one Shift that sets that
route (at most once every 0.25 s). At 6 s into 10 PM it presses both Shifts in the same frame. In the break room it
buys Coffee after 10 PM, Mate's Help after 11 PM and Earplugs after 12 AM, using the Shift keys to choose, and skips
the rest. At 12 AM, with the mate standing by, it sends one tray wrong on purpose. Checks:

- the game opens on the title screen, with no factory hum; Enter clocks in,
- every hour: it starts in order, the supervisor note shows, strikes are reset and gates closed, only the line is on
  screen, the hum plays, and the rules board marks each rule the note changed,
- a feather puff when a tray lands, and a "+$" popup,
- no trays while the note is up, and the note goes away after `note_seconds`,
- both Shifts stop the belt and flash the hazard tint with an EMERGENCY STOP popup; trays and the hour timer do not
  move during the stop; both timers are paused,
- every hour ends in a tally with the belt cleared and the PA banner and hum off; Enter goes to the break room,
- the break room opens on Skip and shows your pay; an item you can't afford is refused and you stay in the shop;
  the Shifts move the selection; Enter buys and starts the next hour with the price taken off; Skip spends nothing,
- 11 PM runs slower (coffee); at 12 AM the coffee has worn off and the mate is standing by; the deliberate wrong
  tray is covered (no strike) with the mate's popup and a shake,
- the PA banner interrupts at 12 AM, and at 1 AM the earplugs keep it quiet all hour,
- at 6 AM: all 8 hours played, every tray right except the covered one (about 398 trays), a clean-hour bonus every
  hour, $500 spent, the win screen shows earned, spent and take-home pay, exactly one emergency stop used, and Enter
  goes back to the title.

That is the main balance check: **at every hour's top speed, a player who reads each tray and presses once can sort
everything**.

**Run 2: an idle night.** Nobody presses anything, except one Left Shift fired just as the first tray reaches the
red line. Checks:

- that tray misses the swinging gate, falls, and is a strike, with a MISSED! popup,
- the idle player is sent home in the first hour on exactly 3 strikes, the screen shows the time and shakes,
- the belt is frozen after game over and Shift does nothing,
- Enter goes to the title, and Enter again starts a clean night at 10 PM (no pay, nothing spent, no mate, all
  emergency stops) with old trays cleared,
- on that new night, Z does nothing; a Shift with no left/right location moves no gate, switches on the Z and /
  backup keys and shows them on the HUD; then Z works the left gate (#22).

A frame limit fails the run instead of hanging if something stops progressing.

## Checking the tests catch bugs

Each rule was broken on purpose to make sure a suite notices:

| Mutation | test_logic | test_play |
|---|---|---|
| `sort()` compares with `!=` instead of `==` (Phase 1) | 10 failures | 5 failures |
| Both-Shift detection always false (Phase 1) | 8 failures | not run |
| Stamp rules ignored (kind always wins) | 2 failures | not run |
| Gate swing never makes a tray miss | 3 failures | 2 failures |
| Strikes not reset at the start of an hour | 2 failures | not run |
| Hour timer keeps running during an emergency stop | not run | 3 failures |
| Mate's Help never covers | 5 failures | 4 failures |
| Earplugs ignored | 2 failures | 2 failures |
| Coffee ignored | 3 failures | 3 failures |
| Shop doesn't check the price | 5 failures | 6 failures |
| Coffee and Earplugs never wear off | 3 failures | 2 failures |

The swing mutant first passed the play test, because `main.gd` worked out "missed" by itself instead of using the
rules' verdict. That was fixed: the scene now follows `ShiftState.sort()`'s result. Repeat this when changing a
rule: break it, see a test fail, fix it.

## Manual playtest checklist

Automated tests cannot judge feel. Before a release, play once and confirm:

- [ ] The title screen shows the chicken, the controls and the Sticky Keys hint; Enter starts at 10:00 PM with the
      supervisor's note on a sticky note and the factory hum.
- [ ] Left Shift and Right Shift each light their own gate box, chute and bin; the gate boxes flash orange as it swings.
- [ ] A tray that crosses the red line goes where the lit route was, outlined green or red.
- [ ] Pressing a Shift just as a tray hits the line makes it tumble off: a strike.
- [ ] Combo and multiplier rise; pay jumps by $20 on the 5th in a row; the combo survives into the next hour.
- [ ] Both Shifts: STOPPED!, the belt and the clock freeze for about 2.5 s, E-STOPS goes down by one.
- [ ] At 11:00 PM: tally screen with the bonus if clean; Enter opens the break room on Skip.
- [ ] In the break room the Shifts move the selection, Enter buys (ka-ching) and starts 11 PM with nuggets moved,
      marked `*` on the board. Coffee makes the belt visibly slower.
- [ ] Popups and puffs on correct sorts, bigger popups at combo 5, 10, 15; shake and STRIKE! on wrong sorts.
- [ ] From 12 AM the PA banner interrupts with a ding-dong; with Earplugs it doesn't.
- [ ] With Mate's Help, a wrong tray shows YOUR MATE COVERED IT! and no strike.
- [ ] From 12 AM red-stamped trays (round R badge) go straight whatever is on them.
- [ ] At 2 AM the chutes swap and the bins relabel.
- [ ] 3 strikes in one hour: SENT HOME with the time. Enter returns to the menu.
- [ ] Surviving 5 AM: the 6 AM win screen with earned, spent and take-home pay, and accuracy.
- [ ] Every sound plays and none is jarringly loud; the hum stops off the line.
- [ ] Web build: the same, in Chrome and Firefox, after clicking the page once.
