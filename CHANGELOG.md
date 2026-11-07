# Changelog

All notable changes to Cluck Shift are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and 0.1.0 is the first public release.

## [Unreleased]

### Fixed
- On a web page, Enter did nothing once the game had lost keyboard focus, which a click on the page text does, and a
  shift ran on unseen (#46). Now an amber bar says to click the game, a shift pauses, a click starts the game and works the
  menus, and Enter resumes from the pause card.

### Added
- **Touchscreens** (#44). Phones and tablets play the same web build: tap each half of the screen for its gate, both sides
  for the emergency stop, and cards in the break room. There is a pause button and a pause menu. The game follows whichever
  input was used last, so a keyboard, a touchscreen, or both all work. Text is larger in touch mode, and a phone held upright
  is asked to turn sideways.

## [0.1.0] - 2026-11-07

### Added
- **Gambling in the break room, on in-game pay only** (#41). Double or Nothing bets $300 on a clean next hour. Chicken
  Slots is a $50 spin: three Shift presses stop three reels, with a $5,000 jackpot. The slots pay back 87% on average.
  The payslip gets a Bets and slots line.

### Changed
- **No more auto combos** (#40). A tray's exit is picked first, every open exit equally likely. From 12 AM no two trays
  in a row share an exit, so every tray needs a key press; before that, never three. Gaps between trays vary by 15%.
  From 12 AM between a quarter and a half of trays are stamped, the most at 5 AM. Red trays now keep coming after the 5 AM note
  cancels them, as decoys that go where their chicken goes.
- The break room is now two rows of cards, to fit six.
- **Fast pacing.** A night is about 4 minutes instead of 10: hours last 30 s, not 75, so a new rule lands every 30 s.
  The belt starts at 160 px/s, not 100, and trays reach one every 0.72 s by 5 AM, not 0.9 s.
- The gate swings in 0.08 s, not 0.12 s. PA announcements are shorter and more frequent. Trays are strange 10% of the
  time, not 6%, to make up for shorter hours.
- The tally screen is gone: the hour's tally is on the break-room heading, so there is one Enter between hours. One
  Enter after being sent home starts a new night.
- The Sticky Keys warning on the title screen is now a readable amber bar, not faint grey text (#21).

### Added
- **Phase 5: polish around the same loop.** Esc or P pauses mid-shift: the belt, clock, PA, flicker and timers all
  stop, and Q quits to the title. Losing window focus pauses too (#31).
- M mutes all sound on the title or the pause card, remembered between sessions (#31).
- A record book in `user://records.cfg`: nights played and survived, best take-home pay, best combo, best accuracy and
  whether the secret ending has been found. The title shows the best night; the payslip and the sent-home card say
  NEW BEST (#32).
- The 6 AM ending draws the night's ledger beside the payslip: pay per hour as bars, a red X per strike (#33).
- Music: a synthesized bass, kick and hi-hat loop on the line that gets 3% faster every hour (#34).
- A Windows Desktop export preset: one self-contained `Cluck Shift.exe` for itch.io (#35).
- Tests: 201 rule checks (ledger and records) and 188 play checks (mute, pause, music, ledger, records on disk).
- **Phase 4: the strange night.** From 2 AM a few trays a night carry a chicken in sunglasses and a trench coat. No
  rule covers them: routing them never costs a strike, pays nothing and leaves the combo alone (#19).
- From 2 AM half the PA announcements are clucking on the radio, with hints ("STRAIGHT on... the DOCK..."). Earplugs
  mute them too (#19).
- From 2 AM the lights flicker: the line dims twice in about a second, every 9 seconds, with an electric buzz. At most
  2 flashes a second, for photosensitive players (#19).
- A "TO LOADING DOCK" sign under the straight-on bin.
- **Two endings** at 6 AM, drawn at dawn with a payslip. Normal: the night bus home. Secret, if every strange tray was
  sent straight on: The Great Escape, delivery trucks leaving the dock driven by chickens (#20).
- Tests: 189 rule checks (strange trays, radio, flicker, endings and their data) and 163 play checks (the autoplayer
  lets every strange tray through and must get the secret ending).

### Fixed
- Shift with no left/right location (remote desktop, some browsers) no longer acts as Right Shift. The game switches
  the gates to Z and / and says so on the title and HUD (#22).

### Added
- **Phase 3: the break room, distractions and juice.** Between hours the break-room vending machine sells Coffee
  (slower belt next hour), Mate's Help (covers your next strike) and Earplugs (no PA next hour), chosen with the Shift
  keys. Spending comes off take-home pay, shown on the win screen.
- PA announcements from 12 AM: a banner over the top of the belt hides incoming trays for a few seconds.
- Juice: pay and combo popups, feather puffs, screen shake on strikes, a pulsing hazard tint during emergency stops.
- Every sound is now synthesized (clicks, bells, slide whistle, siren, ka-ching, PA chime, factory hum) instead of
  placeholder beeps. No audio files.
- A title screen with a night-shift chicken in a hard hat, the controls and the Sticky Keys hint.
- Tests: 161 rule checks; the whole-night playthrough now goes through the shop (137 checks).
- **Phase 2: the whole night.** Eight 75-second hours from 10 PM to 6 AM on an `HourTimer`, with the clock on the
  HUD. Each hour has its own belt (speed and interval slide from the hour's first to its second value, and every hour
  starts faster). Strikes reset every hour; pay, combo and emergency stops carry over. An hour ends in a tally with a
  $100 clean-hour bonus; surviving 5 AM shows the 6 AM win screen.
- Supervisor notes: a sticky note at the start of every hour changes one rule, as data in `rules.json`: move a kind,
  add or cancel a stamp rule, or swap two exits. Red and blue stamps beat the kind; tenders appear at 1 AM; the chutes
  swap at 2 AM. The rules board and bin labels follow the rules and mark what changed.
- Missed trays: a gate takes 0.12 s to swing, and a tray that reaches the red line mid-swing falls off the line as a
  strike.
- Tests: 132 rule checks and a whole-night playthrough of the real scene (62 checks).
- **Phase 1: one playable packing line.** A conveyor feeds a three-way fork. Left Shift and Right Shift toggle the
  gates (one open at a time; both closed means straight on). Trays of wings, drumsticks and nuggets lock in when they
  touch the red line, are outlined green or red, and slide into their bin.
- Scoring: $10 per correct tray, a combo multiplier (x2 from 5 in a row, capped at x5), strikes for wrong sorts,
  and SENT HOME after 3 strikes with pay, trays sorted, accuracy and best combo. Enter clocks in again.
- Emergency stop: both Shifts within 0.15 s halt the belt for 2.5 s, 3 per night. It never changes the gate, and the
  gates still work while stopped.
- The belt speeds up from 110 to 280 px/s and trays come from every 2.4 s to every 0.9 s over about two minutes.
- All rules and tuning in `data/rules.json`; the rules board and bin labels are generated from it.
- Sound hooks (`gate_click`, `ding`, `strike_buzz`, `tray_thunk`, `estop`) with generated placeholder beeps.
- Headless tests: 44 rule checks and a 150 s scripted playthrough of the real scene; CI runs both.
- Web export preset with thread support off, for itch.io.
- Docs: game design (with state machines and flow diagrams), architecture, data format, testing and releasing.
