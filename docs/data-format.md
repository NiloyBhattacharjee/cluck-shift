# Rules file format

All rules and tuning numbers live in [`data/rules.json`](../data/rules.json). The game reads it once at start-up
(`main.gd`), and every new shift builds its `ShiftState` from it. Edit it, relaunch, and run the tests.

## Example (the shipped file)

```json
{
  "routes": { "wing": "left", "drumstick": "right", "nugget": "center" },
  "pay_per_tray": 10,
  "strikes_allowed": 3,
  "estops": 3,
  "estop_seconds": 2.5,
  "belt": {
    "start_speed": 110,
    "max_speed": 280,
    "speed_ramp": 1.5,
    "start_interval": 2.4,
    "min_interval": 0.9,
    "interval_ramp": 0.013
  }
}
```

## Fields

| Field | Type | Meaning |
|---|---|---|
| `routes` | object: kind to exit | Where each tray kind belongs. Exits are `"left"`, `"center"` (straight on) and `"right"`. Every kind listed here spawns, with equal chance. Two kinds may share an exit. |
| `pay_per_tray` | integer | Pay for a correct tray before the combo multiplier. |
| `strikes_allowed` | integer | Wrong sorts before the player is sent home. |
| `estops` | integer | Emergency stops per night. |
| `estop_seconds` | number | How long an emergency stop halts the belt. |
| `belt.start_speed` | number, px/s | Belt speed at clock-in. |
| `belt.max_speed` | number, px/s | Belt speed never goes above this. |
| `belt.speed_ramp` | number, px/s per second | How much faster the belt gets each second. |
| `belt.start_interval` | number, seconds | Time between trays at clock-in. |
| `belt.min_interval` | number, seconds | Trays never come faster than this. |
| `belt.interval_ramp` | number, seconds per second | How much shorter the gap gets each second. |

## Checked by the tests

`tests/test_logic.gd` fails if:

- a route names an exit other than `left`, `center` or `right`,
- a kind in `routes` has no drawing in `Tray.FOOD`,
- `start_speed x start_interval` or `max_speed x min_interval` is 100 px or less (trays could overlap),
- `min_interval` is below 0.6 s (not humanly playable),
- the ramp goes the wrong way (`max_speed < start_speed` or `min_interval > start_interval`).

## Coming in Phase 2

An `hour_seconds` field and an `hours` array, one entry per hour, each with its own belt numbers and an optional
supervisor `note`. See [design.md, section 15.3](design.md#153-supervisor-notes-rule-changes).
