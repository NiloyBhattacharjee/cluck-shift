# Changelog

All notable changes to Cluck Shift are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the build phases (0.1 = Phase 1).

## [Unreleased]

### Added
- **Phase 3: the break room, distractions and juice.** Between hours the break-room vending machine sells Coffee
  (slower belt next hour), Mate's Help (covers your next strike) and Earplugs (no PA next hour), chosen with the Shift
  keys. Spending comes off take-home pay, shown on the win screen.
- PA announcements from 12 AM: a banner over the top of the belt hides incoming trays for a few seconds.
- Juice: pay and combo popups, feather puffs, screen shake on strikes, a pulsing hazard tint during emergency stops.
- Every sound is now synthesized (clicks, bells, slide whistle, siren, ka-ching, PA chime, factory hum) instead of
  placeholder beeps. No audio files.
- A title screen with a night-shift chicken in a hard hat, the controls and the Sticky Keys hint.
- Tests: 161 rule checks; the whole-night playthrough now goes through the shop (133 checks).
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
