# Shortcut Peek

Start something from the Omarchy menu, dock or app grid that already has a keybinding,
and a small toast shows you the shortcut. It reads **your** bindings, so every override
in `~/.config/hypr/bindings.lua` counts.

![Shortcut Peek toast](preview.png)

A fork of [Omarchy Key Promoter](https://github.com/ForrestKnight/omarchy-key-promoter)
by Forrest Knight. The toast and the binding reader are his. The difference is how it
decides that you skipped the shortcut:

| | Key Promoter | Shortcut Peek |
|---|---|---|
| Evidence that the shell started it | the menu closed a moment before | the launch itself carries the shell's environment |
| Menu | yes | yes |
| Dock and app grid | no | yes |
| Browser, terminal, TUI apps (btop, ...) | no | yes |
| `omarchy-launch-or-focus ... gtk-launch <app>` binds | no | yes |
| Windowless tools (`pkill hyprpicker \|\| hyprpicker -a`) | no | yes |
| Slow apps (Electron, Steam) | 3 s | waits up to 10 s for the first window |

It also includes three fixes still waiting upstream: the toast margin on Quickshell 0.3
(gooddadmike), theme colors (Gareth Hubball) and the real default browser behind
`omarchy-browser.desktop` (Tasos Kanellias).

## Install

```bash
omarchy plugin add https://github.com/007cubed/omarchy-shortcut-peek.git --enable --yes
```

If Forrest Knight's Key Promoter is installed, disable it first so you don't get two toasts:

```bash
omarchy plugin disable fkcodes.key-promoter
```

## Settings

Inline on the plugin's entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "guykawaii.shortcut-peek", "duration": 3500, "position": "bottom-right", "window": 3000, "showCount": true }
```

- `position`: `top-left`, `top-center`, `top-right`, `bottom-left`, `bottom-center`, `bottom-right`
- `window`: how long after the menu closes a script or shell layer still counts (ms)
- `showCount`: show how many times this shortcut has been suggested

## How it decides

The plugin never sees key presses.

**Apps and web apps.** Everything uwsm launches gets its own systemd scope under
`app-graphical.slice`, and the scope's first process is the launcher itself.
`bin/launch-watch` watches that directory with `inotifywait` and reads the new process's
environment: the Omarchy shell marks the processes it starts with `QS_*` variables
(`omarchy-launch-shell`), and Hyprland's environment never has them. So each launch is
reported as `shell` or `other`. The first window after a `shell` launch is matched
against your binds; an `other` launch (a keybinding, a terminal) cancels the wait. Timing
cannot fool it: pressing the shortcut right after closing the menu is an `other` launch.

**Scripts** (screenshot, color picker, lock) have no scope. After the menu closes, a short
process scan looks for young processes that carry the shell marker and match a bind.

**Shell layers** (emojis, clipboard) leave no trace, so they count when they open within
`window` ms of the menu closing.

When several bindings do the same thing, the one with the fewest modifiers wins. Media
keys (`XF86Calculator`, ...) are never suggested.

## Dependencies and privileges

A stock Omarchy install: `omarchy-menu-keybindings`, `hyprctl`, `jq`, `ps`, `inotifywait`,
`xdg-terminal-exec`. No sudo, no network, no extra binds. It never edits Hyprland or shell
configuration. The only file it writes is `~/.local/state/omarchy/shortcut-peek.json`
(suggestion counts).

## Debugging

```bash
omarchy-shell shortcut-peek state      # is the launch watcher running?
omarchy-shell shortcut-peek resolved   # binds it can suggest, and what each matches on
omarchy-shell shortcut-peek show "SUPER + B" "Browser"   # test toast
```

## Tests

```bash
node test/promoter.test.js
```

## Remove

```bash
omarchy plugin remove guykawaii.shortcut-peek
```

## License

MIT. See [LICENSE](LICENSE).
