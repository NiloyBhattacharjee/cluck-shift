# Changelog

All notable changes to Cluck Shift are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the build phases (0.1 = Phase 1).

## [Unreleased]

### Added
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
