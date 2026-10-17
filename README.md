# mymd

A minimal, native macOS markdown viewer in the spirit of zathura: no toolbar, no
title bar, no web view. Plain AppKit + TextKit, zero dependencies, ~1k lines of Swift.

## Build

    make            # -> build/mymd.app
    make install    # copies to /Applications (PREFIX=~/Applications to change)

Open files with `open -a mymd file.md`, Finder's "Open With", or run the binary
directly: `build/mymd.app/Contents/MacOS/mymd file.md`.
Handy shell alias: `alias md='open -a mymd'`.

## Keys

| key                         | action                         |
|-----------------------------|--------------------------------|
| `j` `k` / arrows            | scroll                         |
| `d` `u` / `C-d` `C-u`       | half page                      |
| `space` `S-space` / `J` `K` / `C-f` `C-b` | full page        |
| `gg` `G`                    | top / bottom                   |
| `/` `?` then `n` `N`        | search (smart case, incremental) |
| `f` + number                | follow link by hint            |
| `C-o` / `backspace`         | jump back (links, anchors)     |
| `+` `-` `0`                 | zoom in / out / reset          |
| `i` / `C-r`                 | toggle dark / light            |
| `C-n`                       | toggle status bar              |
| `r`                         | reload (also auto-reloads on save) |
| `o`                         | open file                      |
| `q`                         | close window                   |

Mouse selection + `⌘C` copies text. Clicking links works too.

## Supports

CommonMark + GFM: headings, emphasis, strikethrough, inline/fenced code, block
quotes (nested), ordered/unordered/nested lists, task lists, tables with column
alignment, thematic breaks, links (web, relative `.md` files, `#heading` anchors),
local and remote images (incl. SVG), footnotes, YAML front matter, and the common
README HTML subset (`<img width>`, `<p align=center>`, `<br>`, `<b>`, `<a>`, `<sup>`, `<details>`…).

Not supported: syntax highlighting, math, mermaid.
