<p align="center">
  <img src="assets/big-cheese-icon.png" width="220" alt="Big Cheese — a cheese wedge with an enlarged pointer">
</p>

<h1 align="center">Big Cheese</h1>

<p align="center"><strong>No one but you can move your cheese!</strong></p>

Big Cheese is a tiny Omarchy plugin that makes your pointer big for two seconds
when you shake it. Just the cursor, now much harder to lose.

<p align="center">
  <img src="preview.png" alt="Big Cheese product preview showing its enlarged pointer, native panel, and key features">
</p>

## Install

```bash
omarchy plugin add https://github.com/OldJobobo/big-cheese.git --enable --yes
```

The cheese lands in the right side of your bar.

## Use it

- **Shake the mouse:** find your cursor.
- **Left-click the cheese:** open the tiny control panel for Grow, trail, and cursor colors.
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
mouse_trail = "reveal" # off | reveal | always
```

`gentle` notices a smaller shake. `workout` makes you earn your cheese. The
panel changes Grow, trail, and cursor-color behavior for the current shell
session; `cheese.toml` remains the restart default. Restart the Omarchy shell
after editing the file.

## Try theme-colored native cursors

The optional prototype keeps your normal cursor shapes and hotspots while
mapping them to the current Omarchy accent and background. It generates the
cursor data under `$XDG_RUNTIME_DIR`, adds one disposable discovery symlink,
and does not edit persistent cursor or desktop configuration.

Use **Theme cursor colors** in the panel to apply the Omarchy palette to both
normal and enlarged cursors, or control the native-cursor prototype directly:

```bash
./scripts/theme-cursor.py apply-omarchy

# Return to the cursor theme and size that were active before the prototype
./scripts/theme-cursor.py restore
```

While active, Big Cheese rebuilds the temporary cursor when Omarchy colors
change. Some applications cache cursor surfaces until they are reopened. The
setting remains opt-in and restores the theme that was active before it.

## The good stuff

- One sharp pointer, anchored to the real hotspot.
- Clicking still works exactly where it should.
- Optional **Grow** mode turns shake speed into growth speed, then eases fluidly back down.
- Cursor colors can follow Omarchy or return to the active cursor-theme palette.
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

Big Cheese is built for Omarchy on Hyprland. Its enlarged vector pointer uses
the active Omarchy accent and background directly. The optional native-cursor
prototype preserves the available Xcursor shapes and hotspots; themes without
readable Xcursor assets fall back to Adwaita shapes before recoloring.

Like every Omarchy Shell plugin, it runs unsandboxed. Read the code before
installing it if the repository is not yours. Big Cheese does not read input
devices, use the network, or save your cursor coordinates. The optional native
cursor prototype reads the active cursor/theme assets and writes only its
runtime theme, discovery symlink, and crash-recovery state.

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
