# Ghostty for herdr

`config` is the Ghostty config for herdr-graphite. `scripts/install.sh` copies it to `~/.config/ghostty/config`.

## What it sets

| Setting | Value | Why |
|---|---|---|
| Font | iA Writer Mono S, then Adwaita Mono | Rounder letters and wider spacing than SF Mono. `ttf-ia-writer` is in the Omarchy repo. `adwaita-fonts` is in Arch `extra`. |
| Size and line height | 10 pt, +14 % | A calmer text block. |
| Cell width | -10 % | iA Writer Mono S draws "%" 11 % wider than its other glyphs (0.667 em, not 0.600 em). Ghostty sizes each cell by the widest glyph, so letters would sit too far apart. -10 % restores the normal spacing. |
| Ligatures | off | Code shows as typed. |
| Padding | 24 px left and right, 20 px top and bottom | Roomy edges. `window-padding-balance` spreads the spare pixels. |
| Colours | The Graphite palette, written in the file | The file does not read the Omarchy theme folder, so it looks the same on any theme. |

The cursor, key and scroll lines are the Omarchy defaults. Your own lines in the old file are in the backup that the install makes.

## Start herdr in Ghostty

Pick one.

1. **Make Ghostty the default terminal.** The Omarchy herdr launcher then opens it:

   ```
   omarchy-default-terminal ghostty
   ```

   `scripts/install.sh --set-default-terminal` runs this line. It changes the terminal for every Omarchy launcher, not only herdr.

2. **A launch line for one Hyprland bind.** It leaves the default terminal as it is:

   ```
   setsid uwsm-app -- ghostty --class=com.herdr.graphite -e herdr
   ```

   Put it in the bind that you use for herdr (`bind = SUPER ALT, RETURN, exec, <the line>` in `hyprland.conf` syntax). The class `com.herdr.graphite` lets a window rule find the herdr window.

Neither line was tested on a live Hyprland session. The headless check in `scripts/render-base-shots.sh` runs `ghostty -e herdr` with this config.
