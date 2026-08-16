# Changelog

All notable changes to SimpleWhichKey are documented here.

## Unreleased - 2026-08-07

### Added

- `simplewhichkey#DescribePlug()` names what a mapping does rather than the
  keys that do it: `{'<Plug>(simpleremote-open)': 'remote workspaces'}`, and
  every mapping onto that target — in any mode, under any prefix, however
  `<Plug>` was spelt — reads as the name in the panel. Descriptions were keyed
  by key sequence only, so a plugin, which knows its `<Plug>` targets and
  nothing about the keys a user puts on them, had no way to name its own
  mappings; the panel showed `simpleremote-open` derived from the right hand
  side. Any right hand side may be named this way, an empty description drops
  the entry, and `Forget()` clears these along with the other global names.
  A name for the keys themselves (`Describe()`) still wins, a buffer name over
  both, and a group nobody named is still named after what its keys point at,
  so mappings onto `<Plug>(simpleremote-*)` stay `+simpleremote` whatever each
  was named. `:SimpleWhichKeyHealth` counts them next to the other
  descriptions. A right hand side spelt with `<Leader>` or `<LocalLeader>` is
  the one whose canonical form is not the text itself — Vim leaves those words
  alone on a right hand side, so the plugin expands them with the leader of the
  moment. Such a name is stored under the leader in force when it is registered
  and read with the leader in force when the panel draws; changing `mapleader`
  and registering it again therefore takes effect, and no name from before the
  change answers afterwards.

- The help and README say what another plugin's buffer gets for free and how
  it names it: buffer-local mappings are listed in their buffer with a derived
  description, and `simplewhichkey#Describe(..., 'n', v:true)` while that
  buffer is current names them — the shape SimpleRemote's tree buffer uses for
  `gs`, `gm`, `gM`, `gy`, `gd`, `gu`, `]f`, `[f`, `]b` and `[b`. The tests
  now cover exactly that shape: the names show under `g`, `]` and `[` in that
  buffer only, a key chosen from the real panel runs the buffer-local mapping,
  the built-in `gs`/`]f` come back outside the buffer, and the names die with
  it.

### Fixed

- The register panel no longer reads whole registers to show thirty
  characters of them. `"` lists every register that has anything in it, and
  each preview ran three `substitute()` passes over the entire body before
  cutting it down: with seven registers holding 132 KB apiece, one `"` cost
  48 ms of regexp to produce 30 characters per register. The cut happens
  first now, and it counts composed characters, so a base character is never
  separated from its combining marks — the regexp engine replaces the two
  together, and cutting between them would have shortened the preview and
  dropped the ellipsis that says there is more.

  Cutting first only moved the cost, though: the register still had to be
  joined into one string to be handed over, so a multi-line register was
  copied in full to produce thirty characters of it. Seven registers of
  60 000 lines cost 74 ms that way. The head is now taken a line at a time
  and stops at the first line that crosses the width, so the same panel
  costs 7 ms — the rest of which is Vim building the register list itself.
  The same bytes come out as before for every register, and `test-scale`
  budgets what a panel is allowed to take out of the registers so that
  neither half of this can come back.

- A multi-line register previews with the `⏎` glyph it was always meant to
  have. The lines were joined with a single-quoted `'\n'`, which is a
  backslash and an "n", so a two-line register read as `first\nsecond`; and
  because no newline ever reached the preview, the pass that draws the glyph —
  and the control-character pass behind it — had nothing to match for any
  register at all.

- Taking the prefixes and giving them back reads the mapping table once per
  phase instead of once per prefix. `Setup()` asked `maplist()` about each of
  the 30 default prefixes twice over, 60 full copies of every mapping in the
  editor — and `Setup()` is not only startup: `:SimpleWhichKeyRefresh` runs
  it, and every panel the user dismisses ends in a `Restore()` that
  reinstalls the hooks of the modes it suspended. At 531 mappings that was
  49 ms per refresh and 15 ms per dismissed panel; both phases now take one
  sweep each, for 18 ms and 8 ms. One snapshot is safe across a phase because
  every pass asks about one prefix and writes at most that same prefix.

- Turning a page of an overflowing panel no longer rebuilds the level. Paging,
  scrolling and stray mouse events do not move the key sequence, so what may
  follow it cannot have changed, but the panel loop rebuilt it on every pass —
  a read of every mapping in the editor for each page turn, with the panel
  already on screen. The snapshot had made that free of *sweeps* without
  making it any cheaper, which is also why `simplewhichkey#Iterations()` now
  exists next to `simplewhichkey#Sweeps()`: a sweep is the copy, an iteration
  is the read, and `test-scale` budgets both, plus the bytes of register text
  a `"` panel is allowed to touch.

- `g:simplewhichkey_delay` accepts `i:` and `c:` scopes. The table's mode
  scopes were still matched against `n`, `x` and `o` only, so an `'i:<C-r>'`
  or `'c:<C-r>'` entry was read as a prefix named `i:<C-r>`, matched nothing
  and was silently dropped — and `<C-r>`, which is a prefix in Insert mode and
  on the command line both, could not be given different waits in the two.

- A derived group name is no longer cut short when the shared beginning is the
  whole of one description. Two mappings to `:SimpleGit` and
  `:SimpleGitStatusExtra` were named `+Simple`, because the search for a word
  boundary ran on past the end of the shorter name and threw it away. The end
  of the *shortest* description is a boundary, and the name is now all of it.
  The boundary was at first measured against whichever description Vim's
  mapping table listed first instead, so `:lopen` and `:lopen 20` under one
  prefix derived `+lopen` or `+2 keys` depending on which of the two had been
  mapped most recently — an order the user cannot see and that changes
  whenever an ftplugin remaps a key.

- `simplewhichkey#Describe()` with `{buffer}` rebuilds whichever of
  `b:simplewhichkey_descriptions` and `b:simplewhichkey_groups` is missing.
  It decided both had an entry for the mode by testing the first, so an
  ftplugin that reset its own names by unletting one of them — the only way to
  reset them, there being no buffer-scoped `Forget()` — got `E716` from the
  next call.

- `:SimpleWhichKeyList!` separates its two quickfix columns with a tab. The
  separator was written `'%s\t%s'` in a single-quoted string, which is a
  backslash and a "t", so every row in the quickfix list carried those two
  characters instead.

- A register being executed keeps its native speed to its last key. The
  Insert/command-line hook stood aside on `state('m')` alone, which reports
  keys that are still *queued* rather than where a key came from: a register
  whose last key was `<C-r>` fell through the guard, so `@q` paused for
  `g:simplewhichkey_delay` and opened a panel in the middle of a replay.
  `reg_executing()` is the one origin Vim does report and is now part of the
  guard. The documentation claimed the same exemption for a mapping, a
  `:normal` or a `feedkeys()` whose last key is the prefix, which Vim gives no
  way to detect; it now says what the code tests, and the case is listed under
  the limits.

- The panel fits on the screen. Vim's `minwidth`/`maxwidth` size a popup's text
  area alone, and the panel asked for `&columns - 2` columns of text and then
  drew a border and padding on top of that: on an 80 column terminal the frame
  came to 82 columns and Vim clipped the right border away off-screen. The
  frame is now subtracted before the grid is laid out, which also hands the
  columns two more cells of real estate than they used to get.

- A bottom-positioned panel no longer covers the statusline. The ternary meant
  to compensate for `'laststatus'` had two identical branches and did nothing.
  The compensation follows the statusline that is actually drawn rather than
  the option value, so Vim's default `laststatus=1` with a single window — where
  there is no statusline — does not leave a blank row above the command line.

- Descriptions are truncated to a display-column budget instead of a character
  count. A CJK or emoji description escaped truncation at twice its real size,
  overflowed its cell, drove the next column's padding negative and pushed the
  tail of the row off a popup that does not wrap — so those keys became
  invisible.

- `g:simplewhichkey_ignore` is a real filter. It was consulted only for leaf
  mappings, so it could not hide a built-in command, a register or mark listed
  from the live state, or a group prefix — three of the four things the panel
  shows — and a group still counted the children it hid. It is now applied to
  every contribution, against the whole sequence, so naming a group hides its
  subtree and `+N keys` tells the truth. Entries also accept a trailing `**`
  glob and a `/regexp/` form over the notation label. The glob marker is two
  stars because one is a real key and a real register: `'"*'` still hides the
  `*` register alone and `'<leader>*'` still hides only that mapping, instead
  of being reinterpreted as a hidden subtree.

- `g:simplewhichkey_hide_aliases` survives being given descriptions. Alias
  detection compared description *text* and ran after registered descriptions
  had replaced it, so naming a single window command (`<C-w>v`) brought its
  Ctrl variant back, and naming all of them filled the panel with the ten
  phantom duplicates the option exists to remove. It now runs on Vim's own
  table wording, before the overlay — but a description registered for the
  Ctrl form itself (`<C-w><C-v>`) still keeps that key listed. Running first
  had made such a registration disappear along with its node, accepted and
  then thrown away with no diagnostic.

- `:SimpleWhichKeyOperator` no longer replays the chosen sequence into Normal
  mode. Nothing is pending behind a command line, so an operator-pending
  motion means nothing on its own and the same keys are a different command in
  Normal mode: with `onoremap gx iw` the panel advertised a text object and
  choosing it opened the URL under the cursor. The command now browses and
  reports the sequence. `:SimpleWhichKeyOperator i` is the way to read the
  text object list without pressing an operator.

- `:SimpleWhichKeyVisual` no longer replays the chosen sequence into Normal
  mode either. Typing `:` leaves Visual mode, so there is no selection behind
  the command: with `xnoremap gp …` next to `nnoremap gp …` the panel listed
  the x-mode mapping and choosing it ran the Normal-mode one. It browses when
  no selection is live, and still replays as listed when it is reached with
  `<Cmd>` from a Visual mapping.

### Panel evolution

- `g:simplewhichkey_position` accepts `'cursor'`: the panel opens under the
  cursor, and above it when there is no room below. That is where an
  insert-mode hint for `<C-r>` or `<C-x>` belongs — on a tall terminal a bar
  along the bottom edge is nowhere near the word being typed. A cursor-relative
  panel fits itself to its content unless a width is asked for, since a
  full-width popup at the cursor is pushed back to the left edge and buries the
  line it is hinting.

- `g:simplewhichkey_width` decides how wide the panel is: `0` (the default)
  keeps the full-width bar, a number pins the text area to that many columns,
  and `'fit'` shrinks the popup to the widest row it drew — never narrower than
  its own title, which is where the page counter lives. A pinned or fitted
  width is still clamped to the terminal.

- One read of the mapping table per operation instead of one per level. What a
  panel costs is how many times `maplist()` is swept times how many mappings
  are in it, and the tree walk swept once per group: listing a 676-mapping
  keymap took 99 sweeps, `:SimpleWhichKeyHealth` took 71, one panel level took
  3. Each is now exactly 1 — a snapshot is opened for the duration of a bounded
  operation and closed before anything installs or removes a mapping, so
  nothing can go stale. `simplewhichkey#Sweeps()` reports the running total,
  and `make check` now runs a `test-scale` target that asserts the budget in
  sweeps rather than in seconds a loaded machine can invent.

- Derived descriptions try harder, so fewer of them need writing by hand. A
  mapping whose right hand side is one of Vim's own prefixed commands now takes
  that command's name — `<leader>w=` mapped to `<C-w>=` reads as
  `equalize-sizes`, an `omap` onto `iw` as `inner-word` — and a group nobody
  named is named after its children when they agree, so three mappings to
  `:SimpleGitStatus`, `:SimpleGitDiff` and `:SimpleGitLog` make `+SimpleGit`
  instead of `+3 keys`. The group rule is deliberately hard to satisfy: the
  shared beginning must end on a word boundary and cover at least half of the
  shortest description under the key, because a group should be named after
  what its keys are about and not after a word they happen to start with. Both
  are behind the new `g:simplewhichkey_derive` (default 1).

- `simplewhichkey#Describe()` takes a third argument: with it true the names
  live on the current buffer instead of globally, which is what an ftplugin
  wants — the same key means something else in another filetype, and one
  global registry cannot say so. Buffer names win for that buffer and die with
  it; `Forget()` drops the global registry only.

- New `:SimpleWhichKeyList [mode]`, backed by `simplewhichkey#Tree()`. The
  panel answers one level at a time — right while typing, wrong while
  configuring, because a popup cannot be searched. The listing renders the
  whole tree into a scratch buffer with its own `filetype` and syntax, three
  columns wide: the key sequence, its description, and whether that came from
  a built-in table, a mapping, the live editor state or a hooked prefix.
  `:SimpleWhichKeyList!` fills the quickfix list instead, so `:cfilter`
  composes with it. Every level is ordered exactly as the panel would draw it,
  `g:simplewhichkey_ignore` applies identically, and the walk is bounded by
  the new `g:simplewhichkey_list_depth` (default 4) because the tree is not
  bounded by itself.

- Insert mode and the command line are hinted. `<C-r>` lists every register
  that holds something, with a preview, in both modes — as do its `<C-r>`,
  `<C-o>` and `<C-p>` sub-forms — and Insert-mode `<C-x>` lists the completion
  kinds. Both are built-in commands no `maplist()` sweep can find. They go
  through the same `<expr>` hook as the operator prefixes, so the text typed so
  far, the cursor and the half-written command line are never reconstructed.
  The hook stands aside while a completion menu is open, while a register is
  being executed, and while more keys are already queued behind the prefix, and
  `<Esc>` dismisses the panel without leaving Insert mode or abandoning the
  command line. Configured through the new `i` and `c` entries of
  `g:simplewhichkey_prefixes`.

- Text objects are hinted: `i` and `a` are hooked in Visual and
  Operator-pending mode by default, so pausing in `di`, `ca` or `va` lists
  every built-in text object plus any `i%`-style object a plugin installs.
  Operator-pending `i`/`a` use the same expression hook as `g`, so `d2i(`
  keeps its count and `.` repeats the choice; Visual `i`/`a` keep the live
  selection. Normal-mode `i`/`a` are untouched — they start Insert.

- New `:SimpleWhichKeyConflicts`, backed by `simplewhichkey#Conflicts()` and
  `simplewhichkey#Orphans()`. It reports which of your mappings cannot
  dispatch until `'timeoutlen'` has passed because a longer mapping continues
  them, which registered descriptions name a key nothing is mapped to, and
  which hooked prefixes list nothing — plus warnings for `'notimeout'` and a
  `'timeoutlen'` above one second. `:SimpleWhichKeyHealth` carries a one line
  summary of it.

- `g:simplewhichkey_delay` now also accepts a dictionary keyed by prefix
  notation, optionally scoped to a mode (`o:g`), with a `default` entry. A
  prefix that other mappings extend has already cost a full `'timeoutlen'` and
  wants `0`; one Vim dispatches instantly wants a real pause. The plain number
  form is unchanged. `:SimpleWhichKeyHealth` now prints the delay every hooked
  prefix resolves to, next to its mapping and built-in counts.

- Operator-pending mode is now first-class: `g`, `[` and `]` are hinted by
  default after operators, and `:SimpleWhichKeyOperator` exposes the mode
  explicitly. The expression hook leaves Vim's original operator, multiplied
  count and register live while a motion is selected, preserving `g@`, dot
  repeat and clipboard semantics. Exact prefix omaps still win; discovered
  recursive, `<Plug>` and expr omaps continue to execute after slow selection.

- Page position is now remembered per visited level for the lifetime of one
  key sequence. Entering a group from an overflow page and pressing `<BS>`
  returns to that page instead of resetting the parent to page one.
- Overflow entries are now retained on numbered pages instead of being
  replaced by an inert "N more" row. The popup title reports the current page,
  and the mouse wheel moves through pages.
- `<PageUp>` / `<PageDown>` provide a terminal-safe fallback when `'mouse'` is
  disabled. The title advertises the controls, while an explicit mapping for
  either Page key always takes precedence at that level.
- Added regression coverage for page layout, page navigation, and scroll-event
  classification.

## 0.1.0

- Initial Vim9 release: live hints for configured prefixes, Vim built-in
  command tables, mapping discovery, dynamic registers/marks, descriptions,
  popup layout, and transparent key replay.
