# tmux-which-key

> ## ⚠️ Unmaintained — looking for a new maintainer
>
> This project was just an experiment. It works, but I have no time to develop or
> maintain it any further, so it is **not actively maintained**.
>
> **If you want to take it over, please do!** Feel free to fork it and carry it
> forward — you don't need my permission. If you open an issue or a pull request
> to let me know, I'm happy to link your fork here as the official successor so
> that people land on the maintained version instead of this one.
>
> Bug reports and feature requests will most likely go unanswered — please don't
> take it personally.

A LazyVim-style which-key popup for tmux. Press a trigger key to open a discoverable, keyboard-driven menu of **your own tmux key bindings**, grouped by what they do, with breadcrumb navigation and Nord-themed colors.

![Nord theme](https://img.shields.io/badge/theme-Nord-88C0D0?style=flat-square)
![tmux](https://img.shields.io/badge/tmux-3.3+-green?style=flat-square)

![tmux-which-key screenshot](https://gist.githubusercontent.com/Nucc/2eb50f2a324d8e79a8f231b16cdb3b4f/raw/screenshot.png)

## Features

- **Built from your real tmux config** - the menu is generated from `tmux list-keys`, so it always shows the bindings you actually have, including plugin and custom ones
- **Automatic grouping** - bindings are sorted into window / pane / session / layout / buffer / misc by the tmux command they run
- **Real descriptions** - uses the `bind-key -N` notes tmux ships with, and falls back to the command itself
- **Faithful execution** - the selected binding is handed back to tmux verbatim, so format strings like `#{pane_current_path}` and interactive commands behave exactly as when typed
- **Breadcrumb navigation** - always know where you are in the menu tree
- **Nord color theme** - clean, readable color scheme using 24-bit true color
- **Optional JSON overrides** - rename, regroup, or hide individual keys
- **Optional caching** - reuse the parsed key table between popups, dropped whenever the tmux config is reloaded
- **Single-keystroke input** - no Enter key required, instant response

## Requirements

- tmux >= 3.3 (for `display-popup` support); tmux >= 3.1 for the `-N` binding notes used as descriptions
- A terminal with true color (24-bit) support
- `jq` - only needed if you use an optional overrides file

## Installation

### With [TPM](https://github.com/tmux-plugins/tpm) (recommended)

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'Nucc/tmux-which-key'
```

Then press `prefix + I` to install.

### Manual

Clone the repository:

```bash
git clone https://github.com/Nucc/tmux-which-key.git ~/.tmux/plugins/tmux-which-key
```

Add to your `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-which-key/which-key.tmux
```

Reload tmux:

```bash
tmux source-file ~/.tmux.conf
```

### Nix (with Flakes)

If you use Nix and Flakes, you can add this plugin to your [Home Manager](https://github.com/nix-community/home-manager) configuration.

1. Add to your `flake.nix` inputs:

```nix
{
  inputs.tmux-which-key.url = "github:Nucc/tmux-which-key";
}
```

2. Add the package to `programs.tmux.plugins` in your configuration:

```nix
{ pkgs, inputs, ... }: {
  programs.tmux.plugins = [
    inputs.tmux-which-key.packages.${pkgs.system}.default
  ];
}
```

**Note:** `jq` is only needed if you use an optional overrides file; the menu itself works without it.

## Usage

Press `prefix + Space` (default) to open the which-key popup.

The root menu lists groups; pressing a group key shows the real tmux bindings in
that group.

- **Press a key** to run the corresponding tmux binding, or to enter a group
- **Escape** to go back one level or close the menu
- **Backspace** to go back one level or close the menu
- **Tab** / **Shift-Tab** to page forward and back when a group does not fit on
  screen

A key always works even when it is on another page, so paging is only needed to
look a binding up, never to run one.

Groups are indicated by a `+` prefix and shown in cyan, with the number of
bindings they contain. The breadcrumb shows the key table and the current group.

### Where the menu comes from

The menu is not a hand-written list. On every open the plugin reads the live key
table with `tmux list-keys -T prefix`, so it shows exactly the bindings your tmux
config defines - defaults, your own `bind-key` lines, and anything other plugins
add.

- **Descriptions** come from the `bind-key -N` note tmux records for a binding.
  Bindings without a note fall back to showing the tmux command itself.
- **Groups** are derived from the tmux command a binding runs:

  | Group | Bindings running commands such as |
  |-------|-----------------------------------|
  | `window` | `new-window`, `select-window`, `kill-window`, `find-window`, ... |
  | `pane` | `split-window`, `select-pane`, `resize-pane`, `swap-pane`, ... |
  | `session` | `new-session`, `detach-client`, `switch-client`, `choose-tree`, ... |
  | `layout` | `select-layout`, `next-layout`, `previous-layout` |
  | `buffer` | `copy-mode`, `paste-buffer`, `choose-buffer`, `save-buffer`, ... |
  | `misc` | everything else |

  An overrides file can move a key into another group, and can name a group of
  its own that is not in this table.

  Wrappers are looked through, so `confirm-before ... kill-pane` lands in `pane`
  and `command-prompt ... rename-session` lands in `session`.
- **Execution** hands the original tmux command back to tmux via `source-file`,
  so quoting and format strings such as `#{pane_current_path}` are parsed by tmux
  itself. Commands that take over the client - `choose-*`, `command-prompt`,
  `copy-mode`, `customize-mode`, `display-popup`, `confirm-before` - are deferred
  slightly so the which-key popup closes first.

## Configuration

### Tmux Options

Set these in your `~/.tmux.conf` before loading the plugin:

| Option | Default | Description |
|--------|---------|-------------|
| `@which-key-trigger` | `Space` | Key binding (after prefix) to open the menu |
| `@which-key-table` | `prefix` | tmux key table to show (`prefix`, `root`, `copy-mode-vi`, ...) |
| `@which-key-config` | _(auto-detected)_ | Path to an optional JSON overrides file |
| `@which-key-cache` | `off` | Set to `on` to cache the parsed key table between popups |
| `@which-key-popup-height` | `16` | Popup height (lines or percentage) |
| `@which-key-popup-width` | `100` | Popup width (characters or percentage) |
| `@which-key-popup-bg` | `#2E3440` | Popup background color |
| `@which-key-popup-fg` | `#4C566A` | Popup border/foreground color |
| `@which-key-popup-x` | `C` | Popup X position (`C` = centered) |
| `@which-key-popup-y` | `S` | Popup Y position (`S` = status line) |

A real key table holds far more entries than a hand-written menu, so a group
often does not fit at the default size. The footer then shows a page counter and
**Tab** / **Shift-Tab** page through it; a larger line count, or a percentage
such as `60%`, shows more at once.

Example:

```tmux
set -g @which-key-config '~/.config/tmux-which-key/config.json'
set -g @which-key-popup-height '70%'
set -g @which-key-popup-width '95%'
set -g @plugin 'Nucc/tmux-which-key'
```

### Caching

Reading the key table costs a few milliseconds; turning it into the menu costs
rather more. With `@which-key-cache` set to `on` the parsed table is written to
`$XDG_CACHE_HOME/tmux-which-key/<table>.cache` and reused by later popups.

```tmux
set -g @which-key-cache 'on'
```

The cache is dropped when:

- **the tmux config is reloaded** - tmux re-runs `which-key.tmux`, which clears
  the cache directory, so a reload always rebuilds the menu
- **the overrides file is edited** - the cache is ignored once it is older than
  the file it was built from
- **you ask it to** - `scripts/which-key.sh --clear-cache`

A binding added at runtime with a bare `bind-key`, without a config reload, is
not picked up until the cache is cleared. If you would rather not think about it,
leave caching off; the menu is built from scratch in a few tens of milliseconds.

### Custom Key Binding

By default the plugin binds `prefix + Space`. You can override this with `@which-key-trigger`, or create your own binding entirely in `~/.tmux.conf`.

Changing the trigger removes the key the plugin bound last time, as long as that
key still runs this plugin - tmux keeps old bindings across a config reload, so
without this an abandoned trigger would linger and run an outdated command line.
A key you have rebound yourself is never touched. Setting the trigger to `None`
unbinds it and binds nothing.

To bind `Ctrl-Space` directly (no prefix needed):

```tmux
# Disable the default prefix binding
set -g @which-key-trigger 'None'

# Bind Ctrl-Space directly (-n = no prefix)
bind-key -n C-Space run-shell 'tmux display-popup -E -h 60% -w 90% -x C -y S -S "fg=#4C566A" -s "bg=#2E3440" "~/.tmux/plugins/tmux-which-key/scripts/which-key.sh --table prefix #{pane_id}"'
```

To use an overrides file with a manual binding:

```tmux
bind-key -n C-Space run-shell 'tmux display-popup -E -h 60% -w 90% -x C -y S -S "fg=#4C566A" -s "bg=#2E3440" "~/.tmux/plugins/tmux-which-key/scripts/which-key.sh --config ~/.config/tmux-which-key/config.json #{pane_id}"'
```

A hand-written binding does not go through `@which-key-cache`; add `--cache` to
the script arguments to enable it, and clear the cache from `~/.tmux.conf`
itself, which tmux re-runs on every reload:

```tmux
run-shell '~/.tmux/plugins/tmux-which-key/scripts/which-key.sh --clear-cache'
bind-key -n C-Space run-shell 'tmux display-popup -E -h 60% -w 90% -x C -y S -S "fg=#4C566A" -s "bg=#2E3440" "~/.tmux/plugins/tmux-which-key/scripts/which-key.sh --cache #{pane_id}"'
```

### Overrides File (optional)

Nothing needs to be configured - the menu works from your tmux config alone. An
overrides file only fills in what tmux cannot tell us: a nicer description for a
binding that has no `-N` note, a different group, or keys to leave out.

The plugin looks for it in this order:

1. Path set via `@which-key-config` tmux option
2. `$XDG_CONFIG_HOME/tmux-which-key/config.json` (usually `~/.config/tmux-which-key/config.json`)
3. `~/.tmux-which-key.json`

To start from the shipped example:

```bash
mkdir -p ~/.config/tmux-which-key
cp ~/.tmux/plugins/tmux-which-key/configs/example.json ~/.config/tmux-which-key/config.json
```

The file is a JSON object keyed by key name, one entry per key you want to
change:

```json
{
  "|": { "description": "Split vertical" },
  "_": { "description": "Split horizontal" },
  "e": { "description": "Enable pane sync", "group": "pane" },
  "Space": { "hide": true }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `description` | string | Label to show. Overrides the `bind-key -N` note. |
| `group` | string | Group to file the key under - one of the built-in ids, or a new name |
| `hide` | boolean | `true` leaves the key out of the menu entirely |

Every field is optional; anything you leave out keeps its default, so an entry
can set a description, a group, both, or neither.

A `group` that is not one of the built-in ids (`window`, `pane`, `session`,
`layout`, `buffer`, `misc`) creates a new group, listed after the built-in ones.
Its menu key is the first free letter of its own name - `tools` gets `t`,
`plugins` gets `u` because `p` and `l` are taken - falling back to any free key
if the whole name is spoken for. Group names are case sensitive, and an empty
name falls back to `misc`.

```json
{
  "I":   { "description": "TPM install", "group": "plugins" },
  "U":   { "description": "TPM update",  "group": "plugins" },
  "M-u": { "description": "TPM clean",   "group": "plugins" }
}
```

Key names are written as they appear in the menu - for example `|`, `#`, `C-p`,
`M-1`, `Space`, `PPage`. Run the script with `--dump` (see below) to see the exact
name of every key.

### Adding Your Own Entries

There is no plugin-specific place to add commands any more - add a normal tmux
binding and it shows up in the menu. Give it a note with `-N` so it gets a
readable description:

```tmux
bind-key -N "Lazygit" g display-popup -E -d "#{pane_current_path}" -w 90% -h 90% lazygit
bind-key -N "Split vertical" | split-window -h -c "#{pane_current_path}"
```

### Inspecting What The Menu Sees

`--dump` prints the parsed table - group, key, description, command - without
opening the menu:

```bash
~/.tmux/plugins/tmux-which-key/scripts/which-key.sh --dump
~/.tmux/plugins/tmux-which-key/scripts/which-key.sh --table copy-mode-vi --dump
```

## Limitations

- Only keys the popup can read are selectable: printable characters, `C-<letter>`,
  `M-<char>`, arrows, `PPage`/`NPage`, `Home`/`End`, `Ins`/`Del` and function keys.
  Other named keys are listed but cannot be triggered from the menu.
- Bindings without a `bind-key -N` note show their raw tmux command until you give
  them a description in the overrides file.
- The menu is two levels deep: groups, then bindings.
- While a level spans several pages, `Tab` and `Shift-Tab` page instead of running
  a binding on those keys. With a single page they run the binding as usual.
- With caching on, bindings created at runtime without a config reload only show
  up after `--clear-cache`.

## License

MIT
