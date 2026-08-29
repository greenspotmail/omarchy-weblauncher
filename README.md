# Web Launcher

A slide-down launcher for [Omarchy](https://omarchy.org/): web search / direct
URL launcher and a bookmarks picker, sharing one panel with a bar icon.

## Features

- **Web search** — type a query and it opens your chosen search engine, or
  paste/type a URL and it opens directly. Works through `xdg-open`, so it
  always respects whatever your system default browser is.
- **Search engine picker** — DuckDuckGo, Google, Bing, or Startpage, shown
  with their favicons. Your choice is remembered.
- **Bookmarks** — reads a plain-text bookmarks file organized into
  `Category/Subcategory` sections, and lets you browse it as a folder tree
  (alphabetical, arrow-key navigable) or flat-search across everything by
  typing.
- **Add bookmarks** from the panel itself, with autocomplete against your
  existing categories/subcategories so you don't fat-finger a near-duplicate
  category.
- **Edit bookmarks** in your `$EDITOR` (falls back to `nvim`) for anything
  the quick-add flow doesn't cover.
- A bar icon: left-click opens Search, right-click opens Bookmarks.

## Requirements

- `jq`
- `xdg-open` and `xdg-terminal-exec` (both ship with Omarchy by default)
- A terminal-based editor available as `$EDITOR` (or `nvim` installed, which
  is the fallback if `$EDITOR`/`$VISUAL` aren't set)

## Install

```
omarchy plugin add git@gitlab.com:thegreenspot1/omarchy-weblauncher.git --enable
```

Or manually: clone/copy this folder to
`~/.config/omarchy/plugins/weblauncher/`, then:

```
omarchy plugin enable weblauncher --section center
```

## Keybindings

Add to `~/.config/hypr/bindings.lua` (adjust keys to taste — these override
the previous SUPER+SHIFT+B "launch browser" default, so `hl.unbind` it
first):

```lua
hl.unbind("SUPER + SHIFT + B")
o.bind("SUPER + B", "Web search", "omarchy-shell shell summon weblauncher '{\"mode\":\"search\"}'")
o.bind("SUPER + SHIFT + B", "Bookmarks", "omarchy-shell shell summon weblauncher '{\"mode\":\"bookmarks\"}'")
```

Within the panel:

| Key | Action |
|---|---|
| `Enter` | Open the search result / selected bookmark / drill into a folder |
| `Up` / `Down` | Move selection |
| `Right` | Drill into the selected folder (bookmarks mode) |
| `Left` / `Backspace` (on empty field) | Go up one folder level |
| `Tab` | Open "Add bookmark" (bookmarks mode) |
| `Shift+Tab` | Open "Edit bookmarks" in your editor (bookmarks mode) |
| `Escape` | Clear the field, then close the panel |

## Bookmarks file format

Default location: `~/Documents/bookmarks/bookmarks.txt` (configurable — see
Settings below). Plain text:

```
# Lines starting with # are decorative comments, ignored by the parser.
[Vehicles/Parts]
Cascade German - TDI    | https://cascadegerman.com/
Yota Mafia               | https://yotamafia.com/

[Distros]
Arch Linux               | https://archlinux.org/
```

- `[Category]` or `[Category/Subcategory]` headers start a section (any
  depth of `/`-nesting works).
- Each entry is `Name | URL` — the padding before `|` is cosmetic.
- Blank lines are ignored.

## Settings

Stored at `~/.local/state/omarchy/settings/weblauncher.json`:

```json
{ "engine": "duckduckgo", "bookmarksFile": "~/Documents/bookmarks/bookmarks.txt" }
```

Edit by hand, or just use the search-engine chips in the panel (the
bookmarks file path currently isn't exposed in the UI — edit the JSON
directly to change it).

## License

MIT — see [LICENSE](LICENSE).
