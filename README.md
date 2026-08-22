<p align="center">
  <img src="assets/big-cheese-icon.png" width="220" alt="Big Cheese — a cheese wedge with an enlarged pointer">
</p>

<h1 align="center">Big Cheese</h1>

<p align="center"><strong>Your cursor wandered off. Give the mouse a shake.</strong></p>

Big Cheese is a tiny Omarchy plugin that makes your pointer big for two seconds
when you shake it. No rings. No radar sweep. Just the cursor, but now much harder
to lose.

<p align="center">
  <img src="assets/big-cheese-preview.png" alt="Big Cheese displaying one enlarged cursor on an Omarchy desktop">
</p>

## Install

```bash
omarchy plugin add https://github.com/OldJobobo/big-cheese.git --enable --yes
```

The cheese lands in the right side of your bar.

## Use it

- **Shake the mouse:** find your cursor.
- **Left-click the cheese:** find it without the ceremony.
- **Right-click the cheese:** turn shake detection on or off.

That is the whole interface. Big Cheese does not need a settings cathedral.

## The good stuff

- One sharp pointer. No locate ring and no doubled cursor.
- The real hotspot stays put, so clicking still works exactly where it should.
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

MIT licensed. Cheese responsibly.

<p align="center"><strong>No one but you can move your cheese!</strong></p>
