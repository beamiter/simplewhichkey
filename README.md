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
maintain. The same hints now stay available after an operator: pause in `dg`,
`d[` or `d]` and choose the motion without losing the pending operator or
count. Named registers and Vim's current default-register behavior are carried
through the replay as well.

Text objects get the same treatment, and they need it most: they exist only in
Visual and Operator-pending mode, so pressing `d` cannot show them and nothing
in Vim can enumerate them. Pause in `di`, `ca` or `va` and the panel lists
every text object — `iw`, `ip`, `i(`, `at`, `i"` and the rest — alongside any
`i%`-style object your plugins install. `d2i(` keeps its count and `.` repeats
what you chose, because the pending operator is never cancelled.

```
╭─ i ─────────────────────────────────────────────────────────────────────────╮
│ " → inner-double-quoted   [ → inner-bracketed   b → inner-parenthesised      │
│ ' → inner-single-quoted   ] → inner-bracketed   p → inner-paragraph          │
│ ( → inner-parenthesised   B → inner-braced      s → inner-sentence           │
│ ) → inner-parenthesised   W → inner-WORD        t → inner-tag-block          │
╰─────────────────────────────────────────────────────────────────────────────╯
```

The same is true while you type. `<C-r>` in Insert mode or on the command line
lists every register that holds something, with a preview of its contents, so
the choice is made by reading rather than by remembering which letter you
yanked into; `<C-r><C-r>`, `<C-r><C-o>` and `<C-r><C-p>` lead to the same list.
`<C-x>` lists the completion kinds nobody remembers more than two of — whole
lines, file names, tags, omni, dictionary, thesaurus. Both return the chosen
keys from an `<expr>` mapping instead of feeding them, so the text typed so far
and the half-written command line are Vim's own throughout; the panel stands
aside while a completion menu is open, while a register is being executed, and
while more keys are already queued behind the prefix, and `<Esc>` dismisses it
without leaving Insert mode.

```
╭─ <C-R> ─────────────────────────────────────────────────────────────────────╮
│ " → the last yank         0 → the last yank      a → register-a-content     │
│ % → README.md             : → SimpleWhichKeyHea  <C-O> → +insert-as-typed   │
│ = → expression-register   / → whichkey           <C-R> → +insert-literally  │
╰─────────────────────────────────────────────────────────────────────────────╯
```

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

1. Normal/Visual prefixes enter `Start()` through `<Cmd>`; operator prefixes use
   a recursive `<expr>` hook that leaves Vim's pending operator live.
2. The selector waits `g:simplewhichkey_delay` milliseconds. If the next key
   arrives while waiting, nothing is drawn — muscle memory is never interrupted.
3. Otherwise the panel opens and keys are read until the sequence stops being a
   prefix.
4. Normal/Visual sequences are replayed with `feedkeys()`. An operator motion is
   returned directly from its expression mapping. Hooks are suspended for both
   paths so replay cannot re-enter the panel.

Step 4 is why mappings keep behaving exactly as they would without the plugin:
the keys are handed back to Vim as typed rather than interpreted here, so
`<expr>`, `<ScriptCmd>`, `<Plug>`, recursive, buffer-local and silent mappings,
counts and registers all work — Vim resolves them, not this plugin. Operator
selection never cancels or reconstructs the pending state, so `g@` callbacks
and `unnamed`/`unnamedplus` mirroring remain native too.

When a prefix has other mappings under it, Vim already waits `'timeoutlen'`
before dispatching, so the panel opens with no further delay. `set timeoutlen=400`
is a good companion setting.

Different prefixes want different waits, so `g:simplewhichkey_delay` also
accepts a table keyed by prefix — optionally scoped to a mode — with a
`default` for the rest:

```vim
let g:simplewhichkey_delay = {
      \ 'default': 200,
      \ '<leader>': 0,
      \ 'o:g': 250,
      \ 'i:<C-r>': 120,
      \ }
```

The mode scopes are `n:`, `x:`, `o:`, `i:` and `c:`. `<C-r>` is a prefix in
Insert mode and on the command line both, so those last two scopes are the
only way to give it different waits in the two.

`:SimpleWhichKeyHealth` prints the delay every hooked prefix resolves to.

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
      \ 'x': ['<leader>', '<localleader>', 'g', 'z', '[', ']', '"', "'", '`', 'i', 'a'],
      \ 'o': ['g', '[', ']', 'i', 'a'],
      \ 'i': ['<C-r>', '<C-x>'],
      \ 'c': ['<C-r>'],
      \ }

let g:simplewhichkey_delay = 200        " ms before the panel opens
let g:simplewhichkey_position = 'bottom' " bottom | top | center | cursor
let g:simplewhichkey_width = 0          " 0 = full width | columns | 'fit'
let g:simplewhichkey_separator = ' → '
let g:simplewhichkey_max_height = 0     " 0 = half the screen
let g:simplewhichkey_max_desc_width = 30
let g:simplewhichkey_list_depth = 4     " levels :SimpleWhichKeyList descends
let g:simplewhichkey_sort = 'key'       " key | group (groups first)
let g:simplewhichkey_border = 1
let g:simplewhichkey_show_builtins = 1  " Vim's own <C-w>, g, z, [, ] commands
let g:simplewhichkey_derive = 1         " work harder at unnamed mappings
let g:simplewhichkey_hide_aliases = 1   " hide <C-w><C-v> when <C-w>v is listed
" Hidden from the panel, still working as keys.  Entries hide the sequence and
" everything below it; '<leader>1**' globs the label and '/regexp/' matches it.
" One trailing star stays literal, so '"*' hides the * register on its own.
let g:simplewhichkey_ignore = ['<leader>1', '<leader>2']
```

Prefix tables are normalized by supported mode and non-empty string entry. If
nothing usable remains, the complete default table is restored instead of
silently installing no hooks.

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
`Describe()` takes one more: with `v:true` the names live on the current
buffer, which is what an ftplugin wants — the same key means something else in
another filetype, and one global registry cannot say so.

```vim
call simplewhichkey#Describe({'<leader>r': 'cargo run'}, 'n', v:true)
```

A third form names what a mapping *does* rather than the keys that do it:

```vim
call simplewhichkey#DescribePlug({
      \ '<Plug>(simpleremote-open)':    'remote workspaces',
      \ '<Plug>(simpleremote-connect)': 'connect',
      \ })
```

Every mapping onto that target — in any mode, under any prefix, however you
spelt `<Plug>` — reads as the name. This is the form a plugin uses to name its
own `<Plug>` mappings once, since it knows those and nothing about the keys you
will put on them; any right hand side works, not only a `<Plug>`, and an empty
description drops the entry. The registries stack by how much each knows: a
buffer name beats a global name for the keys, which beats a name for the
target, which beats anything derived.

A right hand side written with `<Leader>` or `<LocalLeader>` is stored under
the leader in force when you register it — Vim leaves those words alone on the
right hand side, so the panel reads them with the leader in force when it
draws. Change `mapleader` and such a name has to be registered again, as the
prefixes do (`:SimpleWhichKeyRefresh`); the panel never answers with the leader
of an earlier lookup.

Most of the time you should not need any of this. A mapping onto one of Vim's
own commands takes that command's name — `<leader>w=` mapped to `<C-w>=` reads
as `equalize-sizes`, an `omap` onto `iw` as `inner-word` — and a group nobody
named is named after its children when they agree: three mappings to
`:SimpleGitStatus`, `:SimpleGitDiff` and `:SimpleGitLog` make the group
`+SimpleGit` rather than `+3 keys`. That second rule is deliberately hard to
satisfy, because a group should be named after what its keys are about and not
after a word they happen to start with; `g:simplewhichkey_derive = 0` turns
both off.

### Other plugins

Nothing else is required, but the panel lists what other plugins install and
they can name it:

- Buffer-local mappings are collected on every panel open, so a plugin buffer
  that maps its own keys with `nnoremap <silent><buffer>` has them listed in
  that buffer — SimpleRemote's tree buffer maps `gs`, `gm`, `gM`, `gy`, `gd`,
  `gu`, `]f`, `[f`, `]b` and `[b`, and they show up under `g`, `]` and `[`
  there. Calling `simplewhichkey#Describe(..., 'n', v:true)` while that buffer
  is current turns the derived `call g:SimpleRemoteTreeSortReverse()` into
  `reverse sort`, and the names go with the buffer, as the mappings do. A
  buffer mapping on a hooked prefix itself (the tree's `z` and `'`) simply
  wins in that buffer: no panel opens for it there, and the global hook stays
  underneath.
- `<Plug>` mappings are named once with `simplewhichkey#DescribePlug()`;
  whatever keys you map onto them show that name. Both are ordinary autoload
  calls, so a plugin guards them with `exists('*simplewhichkey#DescribePlug')`
  — which is 0 until this plugin's autoload has been sourced from
  `plugin/simplewhichkey.vim` at startup, so a plugin file sourced before it
  should defer the call to `VimEnter`.

Selection replays the chosen keys with `feedkeys()`, so a plugin's mapping keeps
its own semantics whether it is `<silent>`, `<buffer>`, `<Cmd>` or `<Plug>`.

## Commands

| Command | Effect |
| --- | --- |
| `:SimpleWhichKey [prefix]` | open the panel for a prefix, default the leader |
| `:SimpleWhichKeyVisual [prefix]` | the same for visual mode mappings; browses when no selection is live |
| `:SimpleWhichKeyOperator [prefix]` | browse operator mappings/motions; defaults to `g` |
| `:SimpleWhichKeyList [mode]` | the whole key tree in a scratch buffer you can search; `!` fills the quickfix list |
| `:SimpleWhichKeyRefresh` | re-take the prefixes, e.g. after changing the leader |
| `:SimpleWhichKeyToggle` | hints on/off |
| `:SimpleWhichKeyHealth` | which prefixes are hooked, what they hold, what they wait |
| `:SimpleWhichKeyConflicts` | which mappings wait for a longer one, and which descriptions name nothing |

`simplewhichkey#Keys('n', '<C-w>')` returns what the panel would list, which is
the quickest way to check a configuration without pressing anything.
`simplewhichkey#Tree('n')` returns the whole tree the same way — the panel
answers one level at a time, which is right while typing and wrong while
configuring, because a popup cannot be searched:

```
<Space>       +6 keys           prefix
<Space>f      +file             map
<Space>ff     find files        map
<Space>fr     recent files      map
<C-W>         +38 keys          prefix
<C-W>v        split-vertical    builtin
```

`:SimpleWhichKeyConflicts` answers three questions nothing else in the
ecosystem answers for Vim, because the plugin already walks the whole mapping
tree: which of your mappings cannot dispatch until `'timeoutlen'` has passed
because a longer mapping continues them (the usual reason a key feels slow),
which descriptions you registered point at keys that do not exist, and which
hooked prefixes list nothing. `simplewhichkey#Conflicts()` and
`simplewhichkey#Orphans()` return the same data structurally.

## Highlight groups

`SimpleWhichKeyNormal`, `SimpleWhichKeyBorder`, `SimpleWhichKeyKey`,
`SimpleWhichKeyDesc`, `SimpleWhichKeyGroup`, `SimpleWhichKeySeparator`.

## Limits

- A prefix you have mapped yourself is left alone; `:SimpleWhichKeyHealth` says
  which ones those are.
- `:normal <C-w>v` in a script (with mappings, no `!`) goes through the panel's
  replay, so those keys run after the `:normal` finishes instead of inside it.
  Script code should use `:normal!` anyway.
- Vim reports keys that are still queued, not where a key came from, so a
  mapping or a `feedkeys()` whose *last* key is `<C-r>` or `<C-x>` is
  indistinguishable from a person pressing it and does open the panel. Vim's
  own `<C-r>` waits for the next key there either way; only the delay is new.
  Executing a register (`@q`) is the one origin Vim does report, and that one
  keeps its native speed to its last key.
- Insert and command-line mode are hooked for `<C-r>` and `<C-x>` only; no
  other prefix there is a Vim command that could be listed. Operator-pending
  mode defaults to `g`, `[`, `]`, `i` and `a`; remove the `o`, `i` or `c` entry
  from `g:simplewhichkey_prefixes` to disable those hints.
- The operator keys themselves (`d`, `c`, `y`) are not hooked: hinting them
  would mean listing every motion after the most-used key in Vim. `i` and `a`
  are hot enough that they get their own entry in the delay table if the
  panel gets in your way.

## Tests

```sh
make check
```

## License

MIT
