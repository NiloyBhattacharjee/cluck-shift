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
play test run a whole 4-minute night in about five seconds, frame for frame the same as real time.

## tests/test_logic.gd: the rules (299 checks)

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
| Spawning | Before any stamp rule there are only the three kinds and no stamps. Over 2,000 trays in each of the eight hours, with strange trays kept coming: never three in a row to one exit; from 12 AM never two, with all three exits in play; every open exit gets a fair share. From 12 AM at least a fifth of trays are stamped, and 5 AM has the most. Red trays keep coming after the 5 AM note cancels them, go where their kind goes, and appear in no other hour. A kind added by a note starts spawning. The gap between trays stays within `interval_jitter` and really varies. |
| Gambling | A bet needs the money and comes off the wallet, not `spent`. A clean hour wins it; a strike, or nothing sorted, loses it; a strike the mate covers doesn't. 20,000 spins: every result pays what the table says, each symbol comes up as often as its weight says, and the measured payback matches the table. |
| Shop | Can't buy with an empty wallet, and a refused purchase changes nothing. Buying takes the price off the wallet, not off what you earned. Unknown items can't be bought. One dollar short is still too short. |
| Items | Coffee slows the belt and spaces trays by the same factor (gap unchanged) and lasts one hour. Mate's Help covers a wrong tray (no strike, combo still breaks, no pay), only once, lasts across hours until used, and covers a missed tray too (which still falls). |
| PA | None before `pa.from_hour`; from then the PA interrupts within the note time plus `every` max, keeps interrupting through the hour, each lasting `pa.seconds`. Earplugs: no PA all hour; they last one hour. |
| Strange trays | None before `strange.from_hour`; from then at most `max_per_hour` an hour, and the count resets each hour. Sent straight on: escaped, with no pay, no sorting count and the combo untouched. Sent left: caught, no strike. Caught mid-swing too, and Mate's Help isn't used. Accuracy ignores them. |
| Radio and flicker | Lights steady before 2 AM; from 2 AM dark for the share the `flicker` windows add up to, and still flickering in an emergency stop. Over two strange hours the PA plays both radio clucks (from `strange.radio`, `pa_radio` set) and normal lines, and nothing else. Earplugs mute the radio too. |
| Endings | No strange trays: normal. All let through: secret. One caught: normal again. |
| Ledger | Starts empty; every `end_hour()` appends its tally in order, with its strikes, pay and bonus. |
| Records | The first night to 6 AM beats every record; take-home is pay minus spending; accuracy is kept as a fraction. The same night again beats nothing but counts. A night sent home can only beat the combo, never the pay. The NEW BEST wording. Records and mute survive a save and load; no file means blank records with sound on. |
| Tray path | `Tray.advance` follows a leg, carries leftover distance round a corner, stops at the end; a missed tray tumbles. |
| Data | 8 hours; each hour's belt speeds up, never overlaps trays, keeps at least 0.6 s per tray even at the shortest gap and at least 0.4 s to react to a tray coming out from under the PA; every note has text and changes exactly one rule (none at 10 PM) with real exits; every kind and stamp has art; `stamp_chance` and `swing_seconds` are sensible; the shop is exactly the five known items with names, text and prices; `no_repeat_from` and `interval_jitter` are sensible; every slot symbol has art, a payout and a weight that fits the strip; the slots pay back 80% to 100% and a pair gives back less than a spin costs; `coffee_factor` is sensible; PA announcements can't overlap and have enough lines. The strange night starts after the PA; strange trays are rare but at least one an hour; radio lines mix with the PA and hint at STRAIGHT and DOCK; flicker windows fit the cycle, keep the lights on most of the time and never start more than 2 flashes in a second (photosensitivity); strange trays have art and no rule; both endings have a title and text. |

## tests/test_play.gd: the real game (235 checks)

It reads and writes `user://test_play_records.cfg`, never the player's own record book, and deletes it at the end.

Loads `scenes/main.tscn` and plays it through `Viewport.push_input` key events, the real `SpawnTimer` and
`HourTimer`, and the real Fork `Area2D` overlap.

**Run 1: a full night with an autoplayer.** Each frame it finds the front tray that has not been routed, asks
`ShiftState.exit_for(kind, stamp)` where it belongs under the current rules, and presses the one Shift that sets that
route (at most once every 0.25 s). At 6 s into 10 PM it presses both Shifts in the same frame. In the break room it
buys Coffee after 10 PM, Mate's Help after 11 PM and Earplugs after 12 AM, using the Shift keys to choose, and skips
the rest. At 12 AM, with the mate standing by, it sends one tray wrong on purpose. From 2 AM it sends every strange
tray straight on, which no rule says to do. Checks:

- the game opens on the title screen, with no factory hum or music and a blank record book; M mutes (and the
  setting is saved), M again unmutes; Enter clocks in,
- every hour: it starts in order, the supervisor note shows, strikes are reset and gates closed, only the line is on
  screen, the hum and the music play with the music at `1 + 0.03 x hour` speed, and the rules board marks each rule
  the note changed,
- a feather puff when a tray lands, and a "+$" popup,
- no trays while the note is up, and the note goes away after `note_seconds`,
- both Shifts stop the belt and flash the hazard tint with an EMERGENCY STOP popup; trays and the hour timer do not
  move during the stop; both timers are paused,
- straight after: Esc shows the PAUSED card and stops the hum and music; Shift moves no gate; M on the card mutes;
  for a second nothing moves (trays, game clock, hour timer) and both timers are paused; Esc goes back to work with
  the sound back,
- every hour ends with the belt cleared and the PA banner, hum and music off, straight into the break room (or the ending after 5 AM) with no screen to Enter past,
- the break room opens on Skip and shows the hour's tally and your pay; an item you can't afford is refused and you stay in the shop;
  the Shifts move the selection; Enter buys and starts the next hour with the price taken off; Skip spends nothing,
- after 2 AM the autoplayer bets on Double or Nothing: the HUD shows it, and the clean hour wins it,
- after 3 AM it spins the slots: Enter can't skip the reels, they spin until stopped, three Shift presses land each one on the symbol
  that was drawn, the wallet on screen includes the payout, and Enter starts the next hour,
- the payslip has a Bets and slots line with the night's net result,
- 11 PM runs slower (coffee); at 12 AM the coffee has worn off and the mate is standing by; the deliberate wrong
  tray is covered (no strike) with the mate's popup and a shake,
- the PA banner interrupts at 12 AM, and at 1 AM the earplugs keep it quiet all hour,
- 10 PM to 1 AM: the lights hold steady and no strange tray appears; 2 AM to 5 AM: the lights flicker (the belt is
  tinted); every tally has the lights back on,
- the green RADIO? banner shows at least once after 2 AM, and a PSST... THANKS. popup when a strange tray escapes,
- every strange tray seen on the belt (13 on the seeded night) reached the red line and was let through,
- at 6 AM: all 8 hours played, every tray right except the covered one (about 398 trays), a clean-hour bonus every
  hour, $500 spent, exactly one emergency stop used; the secret ending (THE GREAT ESCAPE) shows, not the dim card,
  with a payslip of earned, break room, take-home pay and "Let through to the dock: 13 of 13"; with one strange tray
  counted as caught the same screen shows the normal ending instead; and Enter goes back to the title and hides it,
- the 6 AM ledger has all 8 hours, each clean with a bonus; the record book on disk has 1 night survived, the
  take-home pay and the secret ending; the payslip says NEW BEST for take-home pay and the secret ending.

That is the main balance check: **at every hour's top speed, a player who reads each tray and presses once can sort
everything**.

**Run 2: an idle night.** Nobody presses anything, except one Left Shift fired just as the first tray reaches the
red line. Checks:

- that tray misses the swinging gate, falls, and is a strike, with a MISSED! popup,
- the idle player is sent home in the first hour on exactly 3 strikes, the screen shows the time and shakes,
- the belt is frozen after game over and Shift does nothing; the night counts in the record book,
- one Enter starts a clean night at 10 PM (no pay, nothing spent, no mate, all
  emergency stops) with old trays cleared,
- on that new night, Z does nothing; a Shift with no left/right location moves no gate, switches on the Z and /
  backup keys and shows them on the HUD; then Z works the left gate (#22),
- P pauses that night too, Q on the pause card goes back to the title, and the quit night doesn't count (#31).

A frame limit fails the run instead of hanging if something stops progressing.

A third run plays on a touchscreen, with taps instead of keys:

- keyboard wording until the first tap, and a tap right after a screen opens does nothing else,
- a tap on the title clocks in; each half of the screen works its gate; two fingers make an emergency stop,
- the pause button moves no gate and opens the menu; paused, a tap moves no gate; a key switches to keyboard wording and a tap back again;
  the Sound button mutes and unmutes; Back to work resumes,
- in the break room a tap right after it opens or off the cards does nothing, one tap chooses and a second buys,
- on the slots taps stop the reels, a tap as they land can't skip the result, and one after that goes back to the line,
- the sent-home card says Tap, a tap right away can't skip it, and one after that starts a new night.

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
| Strange trays sorted like food (Phase 4) | 7 failures | 1 failure (the autoplayer stalls) |
| Any exit lets a strange tray escape | 4 failures | passes: the autoplayer always sends them straight on |
| One escape is enough for the secret ending | 2 failures | 1 failure |
| Lights never flicker | 3 failures | 4 failures |
| No radio clucks | 2 failures | 1 failure |
| No cap on strange trays per hour | 3 failures | passes |
| Pause doesn't stop `logic.tick()` (Phase 5) | not run | 2 failures |
| Records count pay from a night sent home | 1 failure | passes: the idle night earns nothing |

Two Phase 4 mutants pass the play test: they only change which result a wrong move gets, and the autoplayer never
makes that move. The logic suite covers both.

The swing mutant first passed the play test, because `main.gd` worked out "missed" by itself instead of using the
rules' verdict. That was fixed: the scene now follows `ShiftState.sort()`'s result. Repeat this when changing a
rule: break it, see a test fail, fix it.

## Manual playtest checklist

Automated tests cannot judge feel. Before a release, play once and confirm:

- [ ] The title screen shows the chicken, the controls and the Sticky Keys warning on an amber bar; Enter starts at 10:00 PM with the
      supervisor's note on a sticky note and the factory hum.
- [ ] Left Shift and Right Shift each light their own gate box, chute and bin; the gate boxes flash orange as it swings.
- [ ] A tray that crosses the red line goes where the lit route was, outlined green or red.
- [ ] Pressing a Shift just as a tray hits the line makes it tumble off: a strike.
- [ ] Combo and multiplier rise; pay jumps by $20 on the 5th in a row; the combo survives into the next hour.
- [ ] Both Shifts: STOPPED!, the belt and the clock freeze for about 2.5 s, E-STOPS goes down by one.
- [ ] At 11:00 PM the break room opens on Skip, with the hour's tally and the bonus if clean on its heading.
- [ ] On a real phone, held sideways (Android and iPhone): the title says TAP; each half of the screen works its gate; two fingers
  stop the belt; the II button pauses; the sound starts after the first tap; text is readable; held upright it asks to turn sideways.
- [ ] From 12 AM no two trays in a row go to the same bin, and the gaps between trays feel uneven.
- [ ] Double or Nothing: the HUD shows BET $300; the next break room says YOU WON or YOU LOST.
- [ ] Chicken Slots: three Shift presses stop the reels, the last one drags on, ticks slow down and the result pays out.
- [ ] In the break room the Shifts move the selection, Enter buys (ka-ching) and starts 11 PM with nuggets moved,
      marked `*` on the board. Coffee makes the belt visibly slower.
- [ ] Popups and puffs on correct sorts, bigger popups at combo 5, 10, 15; shake and STRIKE! on wrong sorts.
- [ ] From 12 AM the PA banner interrupts with a ding-dong; with Earplugs it doesn't.
- [ ] With Mate's Help, a wrong tray shows YOUR MATE COVERED IT! and no strike.
- [ ] From 12 AM red-stamped trays (round R badge) go straight whatever is on them.
- [ ] At 2 AM the chutes swap and the bins relabel.
- [ ] 3 strikes in one hour: SENT HOME with the time. Enter starts a new night at 10:00 PM.
- [ ] From 2 AM: a few trays carry a chicken in sunglasses and a trench coat; sending one left or right says BAWK?!
      with no strike, sending it straight on says PSST... THANKS.
- [ ] From 2 AM the line dims briefly every 9 s with a buzz, and it is not uncomfortable to look at.
- [ ] From 2 AM some announcements are a green RADIO? banner with static and clucks; Earplugs silence them.
- [ ] Surviving 5 AM: the dawn ending with the payslip. Every strange tray straight on: THE GREAT ESCAPE with trucks
      driven by chickens. Otherwise: the night bus.
- [ ] Every sound plays and none is jarringly loud; the hum stops off the line.
- [ ] Esc (and P) pauses mid-shift: everything freezes and goes quiet; Esc resumes; Q quits to the title. Clicking
      off the window pauses too.
- [ ] M mutes on the title and the pause card, and stays muted after restarting the game.
- [ ] The music runs on the line, stops in the shop, and is noticeably quicker by 5 AM.
- [ ] After a finished night the title shows the best night; the 6 AM payslip shows NEW BEST and the hour-by-hour
      chart, with red X marks over hours with strikes.
- [ ] Windows .exe: double-click, it runs full speed with sound and no console window.
- [ ] Web build: the same, in Chrome and Firefox, after clicking the page once.
