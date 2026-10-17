# Keyboard shortcuts

mymd is driven from the keyboard, vim/zathura style. Press `⌘?` to open this page.

## Scrolling

| Keys                                        | Action                    |
|---------------------------------------------|---------------------------|
| `j` `k` · `↓` `↑` · `⌃e` `⌃y`               | scroll a little           |
| `d` `u` · `⌃d` `⌃u`                         | half a page               |
| `space` `⇧space` · `J` `K` · `⌃f` `⌃b`      | a full page               |
| `PageDown` `PageUp`                         | a full page               |
| `gg` · `Home`                               | top of the document       |
| `G` · `End`                                 | bottom of the document    |

## Search

| Keys        | Action                                                     |
|-------------|------------------------------------------------------------|
| `/` · `⌘F`  | search forward (results update as you type)                |
| `?`         | search backward                                            |
| `return`    | jump to the match and close the search bar                 |
| `esc`       | cancel the search                                          |
| `n` `N`     | next / previous match                                      |

Search ignores case unless the query contains a capital letter.

## Links

| Keys                  | Action                                            |
|-----------------------|---------------------------------------------------|
| `f`                   | number every visible link                         |
| digits                | follow the link with that number                  |
| `esc`                 | hide the numbers                                  |
| `⌃o` · `backspace`    | go back after following a link or `#anchor`       |

Links to other markdown files open in the same window; web links open in your browser.

## View

| Keys            | Action                          |
|-----------------|---------------------------------|
| `+` `=` · `⌘=`  | zoom in                         |
| `-` · `⌘-`      | zoom out                        |
| `0` · `⌘0`      | reset zoom                      |
| `i` · `⌃r` · `⇧⌘D` | toggle dark / light          |
| `⌃n` · `⇧⌘B`    | toggle the status bar           |
| `esc`           | clear the selection             |

## Files and windows

| Keys        | Action                                                   |
|-------------|----------------------------------------------------------|
| `o` · `⌘O`  | open a file                                              |
| `r` · `⌘R`  | reload (files also reload automatically when saved)      |
| `q` · `⌘W`  | close the window                                         |
| `⌘C`        | copy the selected text                                   |
| `⌘A`        | select all                                               |
| `⌘M`        | minimize                                                 |
| `⌘Q`        | quit                                                     |

From a terminal: `mymd file.md`. Recent files are under **File → Open Recent**.
