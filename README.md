<p align="center">
  <img src="assets/big-cheese-icon.png" width="220" alt="Big Cheese — a cheese wedge with an enlarged pointer">
</p>

<h1 align="center">Big Cheese</h1>

<p align="center"><strong>No one but you can move your cheese!</strong></p>

Big Cheese is a tiny Omarchy plugin that makes your pointer big for two seconds
when you shake it. Just the cursor, now much harder to lose.

<p align="center">
  <img src="assets/preview.png" alt="Big Cheese product preview showing its enlarged pointer, native panel, and key features">
</p>

## Install

```bash
omarchy plugin add https://github.com/OldJobobo/big-cheese.git --enable --yes
```

The cheese lands in the right side of your bar.

## Use it

- **Shake the mouse:** find your cursor.
- **Left-click the cheese:** open the tiny control panel.
- **Double-click the cheese:** unlock full color and a cheese pointer twice the standard size and duration until the shell restarts.
- **Right-click the cheese:** turn shake detection on or off.

That is the whole interface. Big Cheese does not need a settings cathedral.

## Make it yours

Open [`cheese.toml`](cheese.toml). It is the whole settings file:

```toml
start_enabled = true
shake_effort = "normal" # gentle | normal | workout
pointer_size = 72       # standard pixels: 48–128; cheese mode is 2×
big_for_seconds = 2.0   # standard seconds: 0.5–5.0; cheese mode is 2×
```

`gentle` notices a smaller shake. `workout` makes you earn your cheese. Restart
the Omarchy shell after saving.

## The good stuff

- One sharp pointer, anchored to the real hotspot.
- Clicking still works exactly where it should.
- The large pointer borrows the fill and outline colors from your cursor theme.
- Odd monitor layouts and negative screen coordinates are welcome.
- Tiny jitters, normal swipes, and pointer warps do not set it off.

## Handy commands

```bash
# Find it now
omarchy-shell jobo-big-cheese trigger

# See what the cheese is thinking
omarchy-shell jobo-big-cheese status | jq

# Quiet, please / welcome back
omarchy-shell jobo-big-cheese disable
omarchy-shell jobo-big-cheese enable
```

## A few honest notes

Big Cheese is built for Omarchy on Hyprland. It matches the active Xcursor
version of your default arrow; Hyprland does not reveal the exact cursor shape
chosen by each app. Hyprcursor-only themes fall back to a dark pointer with a
light outline.

Like every Omarchy Shell plugin, it runs unsandboxed. Read the code before
installing it if the repository is not yours. Big Cheese does not read input
devices, use the network, or save your cursor coordinates.

## Update or remove

```bash
omarchy plugin update jobo.big-cheese --yes

omarchy plugin disable jobo.big-cheese
omarchy plugin remove jobo.big-cheese --yes
```

## Tinkering

The shake thresholds live in `services/ShakeDetector.qml`. Runtime state is
available through the `status` command above. For the full validation and
release routine, see [`RELEASING.md`](RELEASING.md).

```bash
./tests/run-qml-tests.sh -o -,txt
python -m pytest -q tests
```

If Big Cheese saved you one frantic desktop search, you can
[buy OldJobobo a coffee](https://ko-fi.com/oldjobobo).

The color cheese is from [Google Noto Emoji](https://github.com/googlefonts/noto-emoji),
released under the [SIL Open Font License 1.1](assets/LICENSE-NOTO-EMOJI.txt).

MIT licensed. Cheese responsibly.
