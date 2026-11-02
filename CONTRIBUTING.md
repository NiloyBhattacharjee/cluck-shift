# Contributing to Cluck Shift

Thanks for helping. Bug reports, playtest notes, new supervisor rules and pull requests are all welcome.

## Set up

You need [Godot 4.7](https://godotengine.org/download) (standard build).

```bash
godot --headless --path . --import
godot --headless --path . -s tests/test_logic.gd
godot --headless --path . --fixed-fps 60 -s tests/test_play.gd
```

[docs/testing.md](docs/testing.md) explains what each suite covers.

## Ground rules

- **Shift keys only.** Gameplay input is Left Shift, Right Shift and both together. Enter and Space drive menus.
  No mouse, no other gameplay keys.
- **Rules are data.** Routes, pay, strikes and tuning go in `data/rules.json`, not in code. If a new kind of rule
  needs code, add the code once and make the rule itself data.
- **Rules live in `ShiftState`.** Anything that decides pay, strikes, routing or timing goes in
  `scripts/shift_state.gd`, which has no nodes, so it can be tested directly. `main.gd` only connects it to the scene.
- **Every rule change has a test.** Add a check to `tests/test_logic.gd`, and to `tests/test_play.gd` if it changes
  what the player sees. Break the rule on purpose once and confirm the test fails.
- **Small scenes and scripts with clear names.** Placeholder art is drawn with shapes in `_draw()`.
- **Cartoony, no gore.** Chickens are food here, but in a cartoon way.

## Issues

Use the templates: **Bug report** for something wrong, **Feature or rule idea** for something new. Roadmap work is
tracked as issues labelled `phase 1` to `phase 4`.

## Pull requests

1. Open or pick an issue first for anything large, so we can agree on the approach.
2. Keep the change focused. Both test suites must pass (CI runs them).
3. Update `docs/` if players or designers can see the change, and add a line under **Unreleased** in
   [CHANGELOG.md](CHANGELOG.md).
4. Write commit messages that say what changed and why: a short subject line, then a body that explains the
   behaviour, and `Closes #N` for the issues it finishes.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
