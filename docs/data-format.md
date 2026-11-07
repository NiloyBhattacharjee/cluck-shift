# Rules file format

All rules and tuning numbers live in [`data/rules.json`](../data/rules.json). The game reads it once at start-up
(`main.gd`), and every new night builds its `ShiftState` from it. Supervisor notes change a copy of the rules during
the night, never the file's data. Edit it, relaunch, and run the tests.

## Top level

| Field | Type | Meaning |
|---|---|---|
| `routes` | object: kind to exit | Starting rules: where each tray kind goes at 10 PM. Exits are `"left"`, `"center"` (straight on) and `"right"`. Every kind with a rule spawns, with equal chance. Two kinds may share an exit. |
| `pay_per_tray` | integer | Pay for a correct tray before the combo multiplier. |
| `strikes_allowed` | integer | Strikes in one hour before the player is sent home. |
| `estops` | integer | Emergency stops per night. |
| `estop_seconds` | number | How long an emergency stop halts the belt and the hour clock. |
| `hour_seconds` | number | Length of each hour in seconds of play. |
| `note_seconds` | number | How long the supervisor note shows at the start of an hour; the first tray spawns when it goes. |
| `clean_hour_bonus` | integer | Added at the end of an hour with no strikes (and at least one tray sorted). |
| `stamp_chance` | number, 0 to 1 | Share of trays that get a stamp while any stamp rule exists. |
| `swing_seconds` | number | How long a gate takes to swing; a tray reaching the red line during it is missed. |
| `coffee_factor` | number, 0.5 to 1 | Coffee multiplies belt speed by this and divides the tray interval by it. |
| `shop` | array of items | The break-room items, in display order (Skip is added by the game). |
| `pa` | object | PA announcements (below). |
| `strange` | object | The strange night from 2 AM: strange trays, radio clucks, flickering lights (below). |
| `endings` | object | Title and line for the `normal` and `secret` 6 AM endings (below). |
| `hours` | array of 8 hour objects | 10 PM first, 5 AM last. |

## Hour object

```json
{
  "speed": [130, 180], "interval": [2.2, 1.7],
  "note": { "text": "Nuggets now go RIGHT. Same box as the drumsticks. Don't ask.", "route": { "nugget": "right" } }
}
```

| Field | Type | Meaning |
|---|---|---|
| `speed` | [start, end] px/s | Belt speed at the start and end of the hour; it slides linearly between them. |
| `interval` | [start, end] seconds | Time between trays at the start and end of the hour. |
| `note` | object | The supervisor note for the start of this hour. |

## Note object

| Field | Type | Meaning |
|---|---|---|
| `text` | string | What the supervisor says. Shown on the sticky note. |
| `route` | `{kind: exit}` | Move a kind to an exit. A kind that has no rule yet starts spawning (needs art in `Tray.FOOD`). |
| `stamp` | `{colour: exit}` or `{colour: null}` | Add a stamp rule (stamps beat kinds), or cancel one with `null`. Needs art in `Tray.STAMPS`. |
| `swap` | `[exit, exit]` | Everything going to one exit goes to the other, and back. |

The first hour's note has only `text`. Every later note has `text` and **exactly one** of `route`, `stamp` or
`swap`, with exactly one entry.

## Checked by the tests

`tests/test_logic.gd` fails if:

- there are not 8 hours, or `hour_seconds` is less than `note_seconds + 20`,
- an hour's belt gets slower, or `speed x interval` is 100 px or less at either end (trays could overlap),
- an hour's last interval is below 0.6 s,
- an hour's top speed leaves under 0.4 s to react to a tray coming out from under the PA banner,
- a note has no `text`, or (after the first hour) does not change exactly one rule,
- a route or stamp names an exit other than `left`, `center` or `right`, or a swap names the same exit twice,
- any kind (starting or added by a note) has no drawing in `Tray.FOOD`, or any stamp none in `Tray.STAMPS`,
- `stamp_chance` is not between 0 and 0.5, or `swing_seconds` is not shorter than the both-Shifts window,
- a shop item lacks a name, text or positive price, or the shop is not exactly Coffee, Mate's Help and Earplugs,
- `coffee_factor` is not between 0.5 and 1,
- the PA starts at 10 PM or after the last hour, announcements could overlap (`every[0]` <= `seconds`), or there are
  fewer than 4 lines.

## Shop item

```json
{ "id": "coffee", "name": "Coffee", "price": 150, "text": "Next hour the belt runs 20% slower and trays come 20% less often." }
```

| Field | Meaning |
|---|---|
| `id` | `coffee`, `mate` or `earplugs`: the effect `ShiftState.buy()` applies. A new id needs code. |
| `name`, `text` | Shown on the vending-machine card. |
| `price` | Taken off the wallet. Refused if the wallet is short. |

## PA object

```json
"pa": { "from_hour": 2, "every": [6, 11], "seconds": 2.5, "lines": ["Please stop high-fiving the drumsticks.", "..."] }
```

| Field | Meaning |
|---|---|
| `from_hour` | First hour with announcements (0 = 10 PM, 2 = 12 AM). |
| `every` | [min, max] seconds between the end of one announcement and the start of the next. |
| `seconds` | How long the banner stays up. |
| `lines` | What the PA says, picked at random. |

## Strange object

```json
"strange": {
  "from_hour": 4, "chance": 0.1, "max_per_hour": 4,
  "radio_chance": 0.5, "radio": ["...kssh... bawk... STRAIGHT on... bawk bawk... kssh...", "..."],
  "flicker": { "every": 9, "dark": [[0, 0.2], [0.45, 1.2]] }
}
```

| Field | Meaning |
|---|---|
| `from_hour` | First strange hour (4 = 2 AM). Must be at or after `pa.from_hour`, so the radio has a PA to cut into. |
| `chance` | Chance that a new tray is strange (a chicken in sunglasses and a trench coat). |
| `max_per_hour` | Most strange trays in one hour. |
| `radio_chance` | Chance that a PA announcement is clucking on the radio instead. |
| `radio` | What the radio says. These are the hints for the secret ending. |
| `flicker.every` | Length of one flicker cycle in seconds of game clock. |
| `flicker.dark` | `[start, end]` windows inside each cycle when the lights are out. |

The data tests fail if `from_hour` is before the PA or past the night, `chance` is not in (0, 0.1], `max_per_hour` is
below 1, there are fewer than 3 radio lines, no radio line says STRAIGHT or none says DOCK, a flicker window does not
fit its cycle, the lights are out 25% of the time or more, or more than 2 flashes start within any one second.

## Endings object

```json
"endings": {
  "normal": { "title": "6 AM. YOU MADE IT!", "text": "Payslip in hand, you catch the first bus home." },
  "secret": { "title": "THE GREAT ESCAPE", "text": "The trucks leave the loading dock at dawn. The drivers are chickens." }
}
```

`ShiftState.ending()` picks the key: `secret` when every strange tray that reached the red line was sent straight on
(and there was at least one), otherwise `normal`. Each needs a non-empty `title` and `text`.

## Recipes

**Change a starting rule:** edit `routes`.

**Change what happens at 2 AM:** edit `hours[4].note` (hours count from 0 = 10 PM).

**Add a new kind mid-night:** give a note `"route": {"wings_bbq": "right"}`, then add `"wings_bbq"` to `Tray.FOOD`
and a drawing in `Tray._draw()` (`scripts/tray.gd`). The data test fails until the art exists.

**Add a new stamp colour:** a note with `"stamp": {"green": "right"}`, plus a colour in `Tray.STAMPS`.

**Make the night shorter for testing:** lower `hour_seconds`.

**Reprice the shop:** edit `price` in `shop`. **Add a PA line:** append to `pa.lines`.

**Make the strange night start earlier:** lower `strange.from_hour` (not below `pa.from_hour`). **More strange trays:**
raise `strange.chance` and `strange.max_per_hour`. **Calmer lights:** shorten or remove `strange.flicker.dark` windows.
