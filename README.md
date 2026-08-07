# SimpleWhichKey

Live key hints for Vim 9 — for every prefix, not just the leader.

Pause after `<C-w>` and a panel lists every window command. Pause after `g`, `z`,
`[`, `]`, `"` or `` ` `` and the same happens: built-in commands, your mappings,
your plugins' mappings, the registers that actually hold something, the marks
that are actually set. Keep typing at your usual speed and nothing appears at
all.

```
╭─ <C-W> ─────────────────────────────────────────────────────────────────────╮
│ b → go-bottom-right   j → go-down          r → rotate-downwards  - → …      │
│ c → close-window      K → move-window-far  S → split-horizontal  : → …      │
│ g → +goto             k → go-up            v → split-vertical    = → …      │
╰─────────────────────────────────────────────────────────────────────────────╯
```

Like the rest of the `simple*` suite this is Vim9script only: no Python, no
daemon, no dependencies.

## Why another which-key

`vim-which-key` shows what you registered, under the prefixes you registered it
for. Vim's own prefixed commands — `<C-w>v`, `gU`, `zt` — are not mappings, so
nothing can enumerate them; and a prefix nobody registered shows an empty panel.
SimpleWhichKey carries description tables for Vim's built-in prefixes, discovers
mappings with `maplist()` on the fly, and derives a description from the right
hand side when you have not written one. A fresh configuration is useful
immediately, and stays useful as you add mappings, without a second list to
maintain.

On narrow terminals or deliberately short panels, choices that do not fit are
kept on numbered pages instead of being discarded. Scroll the mouse wheel while
the panel is open, or use `<PageUp>` / `<PageDown>`, to move between pages.
An explicit mapping for either Page key still wins at that level. Each group
remembers its page for the current key sequence, so entering a child and using
`<BS>` returns to the same part of the parent instead of page one.

## Install

With [SimplePlug](https://github.com/beamiter/simpleplug), vim-plug, or any
plugin manager:

```vim
Plug 'beamiter/simplewhichkey'
```

Or by hand:

```sh
git clone https://github.com/beamiter/simplewhichkey ~/.vim/pack/plugins/start/simplewhichkey
```

Nothing to build. Requires Vim 9.1 with `+popupwin`, `+textprop` and `+timers`.

## How it works

1. Each configured prefix is mapped to `<Cmd>call simplewhichkey#Start(...)<CR>`.
2. `Start()` waits `g:simplewhichkey_delay` milliseconds. If the next key arrives
   while waiting, nothing is drawn — muscle memory is never interrupted.
3. Otherwise the panel opens and keys are read until the sequence stops being a
   prefix.
4. The collected sequence is replayed with `feedkeys()`, with the hooks removed
   for the duration so the replay cannot re-enter the panel.

Step 4 is why mappings keep behaving exactly as they would without the plugin:
the keys are handed back to Vim as typed rather than interpreted here, so
`<expr>`, `<ScriptCmd>`, `<Plug>`, buffer-local and silent mappings, counts and
registers all work — Vim resolves them, not this plugin.

When a prefix has other mappings under it, Vim already waits `'timeoutlen'`
before dispatching, so the panel opens with no further delay. `set timeoutlen=400`
is a good companion setting.

## Keys inside the panel

| Key | Action |
| --- | --- |
| any listed key | choose it; groups open the next level |
| any unlisted key | replayed as typed, so nothing is ever blocked |
| `<BS>` | back one level, restoring that level's previous page |
| `<PageUp>` / `<PageDown>` | previous/next overflow page, unless explicitly mapped |
| mouse wheel | previous/next page when the current level overflows |
| `<Esc>` / `<C-c>` | close, run nothing |

## Configuration

```vim
" Which prefixes get a panel.  This is the default.
let g:simplewhichkey_prefixes = {
      \ 'n': ['<leader>', '<localleader>', 'g', 'z', 'Z', '<C-w>', '[', ']', '"', "'", '`'],
      \ 'x': ['<leader>', '<localleader>', 'g', 'z', '[', ']', '"', "'", '`'],
      \ }

let g:simplewhichkey_delay = 200        " ms before the panel opens
let g:simplewhichkey_position = 'bottom' " bottom | top | center
let g:simplewhichkey_separator = ' → '
let g:simplewhichkey_max_height = 0     " 0 = half the screen
let g:simplewhichkey_max_desc_width = 30
let g:simplewhichkey_sort = 'key'       " key | group (groups first)
let g:simplewhichkey_border = 1
let g:simplewhichkey_show_builtins = 1  " Vim's own <C-w>, g, z, [, ] commands
let g:simplewhichkey_hide_aliases = 1   " hide <C-w><C-v> when <C-w>v is listed
let g:simplewhichkey_ignore = ['<leader>1', '<leader>2']
```

### Better descriptions

Descriptions are optional — `<Cmd>SimpleGitDiff<CR>` reads as `SimpleGitDiff` on
its own. To name things properly, either use the flat form:

```vim
call simplewhichkey#Describe({
      \ '<leader>f':  '+file',
      \ '<leader>ff': 'find files',
      \ '<leader>fr': 'recent files',
      \ })
```

or register a nested dictionary in vim-which-key's shape, so an existing
`g:which_key_map` can be reused as it is:

```vim
let g:which_key_map = {
      \ 'f': {'name': '+file', 'f': 'find files', 'r': 'recent files'},
      \ }
call simplewhichkey#Register('<leader>', 'g:which_key_map', 'n')
```

Both take a mode as their last argument (`'n'` by default, `'x'` for visual).

## Commands

| Command | Effect |
| --- | --- |
| `:SimpleWhichKey [prefix]` | open the panel for a prefix, default the leader |
| `:SimpleWhichKeyVisual [prefix]` | the same for visual mode mappings |
| `:SimpleWhichKeyRefresh` | re-take the prefixes, e.g. after changing the leader |
| `:SimpleWhichKeyToggle` | hints on/off |
| `:SimpleWhichKeyHealth` | which prefixes are hooked, and what they hold |

`simplewhichkey#Keys('n', '<C-w>')` returns what the panel would list, which is
the quickest way to check a configuration without pressing anything.

## Highlight groups

`SimpleWhichKeyNormal`, `SimpleWhichKeyBorder`, `SimpleWhichKeyKey`,
`SimpleWhichKeyDesc`, `SimpleWhichKeyGroup`, `SimpleWhichKeySeparator`.

## Limits

- A prefix you have mapped yourself is left alone; `:SimpleWhichKeyHealth` says
  which ones those are.
- `:normal <C-w>v` in a script (with mappings, no `!`) goes through the panel's
  replay, so those keys run after the `:normal` finishes instead of inside it.
  Script code should use `:normal!` anyway.
- Insert and command-line mode are not hooked.

## Tests

```sh
make check
```

## License

MIT
