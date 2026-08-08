vim9script

# Unit level checks that need no terminal.
#
#   vim -N -u NONE -n -es -S tests/vim_smoke.vim

set nomore
set nocompatible

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

g:mapleader = ' '
g:maplocalleader = ','
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplewhichkey.vim')

# --------------------------------------------------------------- notation ---

assert_equal(' ', simplewhichkey#keys#Termcodes('<leader>'))
assert_equal(',', simplewhichkey#keys#Termcodes('<localleader>'))
assert_equal("\<C-w>", simplewhichkey#keys#Termcodes('<C-w>'))
assert_equal(' ff', simplewhichkey#keys#Termcodes('<leader>ff'))
assert_equal('g', simplewhichkey#keys#Termcodes('g'))
assert_equal('<C-W>', simplewhichkey#keys#Label("\<C-w>"))
assert_equal('<Space>', simplewhichkey#keys#Label(' '))

assert_equal(["\<C-w>", 'v'], simplewhichkey#keys#Split("\<C-w>v"))
assert_equal([' ', 'f', 'f'], simplewhichkey#keys#Split(' ff'))
assert_equal(["\<F3>"], simplewhichkey#keys#Split("\<F3>"))
assert_equal("\<C-w>", simplewhichkey#keys#First("\<C-w>gf"))

assert_true(simplewhichkey#keys#StartsWith(' ff', ' '))
assert_false(simplewhichkey#keys#StartsWith(' ', ' '))
assert_false(simplewhichkey#keys#StartsWith('gg', ' '))
assert_equal(-1, simplewhichkey#keys#ScrollDirection("\<ScrollWheelUp>"))
assert_equal(1, simplewhichkey#keys#ScrollDirection("\<ScrollWheelDown>"))
assert_equal(0, simplewhichkey#keys#ScrollDirection('x'))
assert_equal(-1, simplewhichkey#keys#PageDirection("\<PageUp>"))
assert_equal(1, simplewhichkey#keys#PageDirection("\<PageDown>"))
assert_equal(0, simplewhichkey#keys#PageDirection('x'))

# A bounded panel keeps overflow entries on pages instead of dropping them.
# Paging uses scroll events, which were already swallowed by the panel loop.
g:simplewhichkey_max_height = 1
var many: list<dict<any>> = []
for nr in range(20)
  add(many, {label: nr2char(char2nr('a') + nr), desc: 'entry-' .. nr, group: false})
endfor
simplewhichkey#panel#Show('Paging', many, "n\x01z")
var paging_popup = popup_list()[-1]
assert_match('Paging \[1/[2-9][0-9]* PgUp/PgDn\]',
  get(popup_getoptions(paging_popup), 'title', ''))
assert_true(simplewhichkey#panel#Scroll(1))
simplewhichkey#panel#Show('Paging', many, "n\x01z")
assert_match('Paging \[2/[2-9][0-9]* PgUp/PgDn\]',
  get(popup_getoptions(paging_popup), 'title', ''))
# Mode and raw sequence, not the rendered title, identify a level.
simplewhichkey#panel#Show('Paging', many, "x\x01z")
assert_match('Paging \[1/[2-9][0-9]* PgUp/PgDn\]',
  get(popup_getoptions(paging_popup), 'title', ''))
simplewhichkey#panel#Show('Paging', many, "n\x01z")
assert_match('Paging \[2/[2-9][0-9]* PgUp/PgDn\]',
  get(popup_getoptions(paging_popup), 'title', ''))
# A child level starts at its first page, and returning to the parent restores
# the page the user was scanning rather than jumping back to its beginning.
simplewhichkey#panel#Show('Paging child', [
  {label: 'x', desc: 'child entry', group: false},
], "n\x01zg")
assert_match('Paging child', get(popup_getoptions(paging_popup), 'title', ''))
simplewhichkey#panel#Show('Paging', many, "n\x01z")
assert_match('Paging \[2/[2-9][0-9]* PgUp/PgDn\]',
  get(popup_getoptions(paging_popup), 'title', ''))
assert_true(simplewhichkey#panel#Scroll(-1))
simplewhichkey#panel#Close()
g:simplewhichkey_max_height = 0

# A description is truncated to a display-column budget, not to a character
# count.  A double-width description that escapes truncation overflows its
# cell, drives the next column's padding negative and pushes the tail of the
# row off a popup that does not wrap.
g:simplewhichkey_max_desc_width = 12
var wide: list<dict<any>> = []
for nr in range(6)
  add(wide, {label: nr2char(char2nr('a') + nr), desc: repeat('宽', 20), group: false})
endfor
simplewhichkey#panel#Show('Wide', wide, "n\x01wide")
var wide_popup = popup_list()[-1]
var wide_lines = getbufline(winbufnr(wide_popup), 1, '$')
assert_true(len(wide_lines) > 0)
for line in wide_lines
  assert_true(strdisplaywidth(line) <= &columns - 6,
    printf('a wide description overflowed the panel: %d columns in %s',
      strdisplaywidth(line), string(line)))
endfor
# ASCII keeps working, and the ellipsis is still added.
simplewhichkey#panel#Show('Wide', [
  {label: 'a', desc: repeat('x', 40), group: false},
], "n\x01wide-ascii")
assert_match('x\{11}…',
  getbufline(winbufnr(popup_list()[-1]), 1, '$')[0])
simplewhichkey#panel#Close()
g:simplewhichkey_max_desc_width = 30

# The bottom panel stops above the statusline instead of covering it.
var saved_laststatus = &laststatus
&laststatus = 2
simplewhichkey#panel#Show('Bottom', [
  {label: 'a', desc: 'entry', group: false},
], "n\x01bottom")
var bottom = popup_getpos(popup_list()[-1])
assert_equal(&lines - &cmdheight - 1, bottom.line + bottom.height - 1,
  'the bottom panel covered the statusline')
&laststatus = 0
simplewhichkey#panel#Show('Bottom', [
  {label: 'a', desc: 'entry', group: false},
], "n\x01bottom-nostatus")
bottom = popup_getpos(popup_list()[-1])
assert_equal(&lines - &cmdheight, bottom.line + bottom.height - 1,
  'without a statusline the panel keeps that line')
# Vim's default 'laststatus' is 1, which draws a statusline only once the tab
# page holds a second window.  The compensation has to follow what is drawn,
# not what the option says, or a stock single-window Vim gets a blank row.
&laststatus = 1
simplewhichkey#panel#Show('Bottom', [
  {label: 'a', desc: 'entry', group: false},
], "n\x01bottom-ls1-one")
bottom = popup_getpos(popup_list()[-1])
assert_equal(&lines - &cmdheight, bottom.line + bottom.height - 1,
  'laststatus=1 with one window has no statusline to stay above')
split
simplewhichkey#panel#Show('Bottom', [
  {label: 'a', desc: 'entry', group: false},
], "n\x01bottom-ls1-two")
bottom = popup_getpos(popup_list()[-1])
assert_equal(&lines - &cmdheight - 1, bottom.line + bottom.height - 1,
  'laststatus=1 with a split does draw a statusline the panel must clear')
only
simplewhichkey#panel#Close()
&laststatus = saved_laststatus

# ------------------------------------------------------------------ hooks ---

nnoremap <silent> <leader>ff <Cmd>echo 'files'<CR>
nnoremap <silent> <leader>fr <Cmd>echo 'recent'<CR>
nmap <silent> <leader>e <Plug>(demo-toggle)
xnoremap <silent> <leader>fg <Cmd>echo 'grep'<CR>
simplewhichkey#Setup()

assert_match('simplewhichkey#Start', maparg('<Space>', 'n'))
assert_match('simplewhichkey#Start', maparg('<C-w>', 'n'))
assert_match('simplewhichkey#Start', maparg('g', 'n'))
assert_match('simplewhichkey#Start', maparg('<Space>', 'x'))
assert_match('simplewhichkey#OperatorHook', maparg('g', 'o'))
# Text objects live in Visual and Operator-pending mode only; in Normal mode
# i and a start Insert, so those slots must be left alone.
assert_match('simplewhichkey#OperatorHook', maparg('i', 'o'))
assert_match('simplewhichkey#OperatorHook', maparg('a', 'o'))
assert_match('simplewhichkey#Start', maparg('i', 'x'))
assert_match('simplewhichkey#Start', maparg('a', 'x'))
assert_equal('', maparg('i', 'n'))
assert_equal('', maparg('a', 'n'))

# A local mapping may shadow the plugin's global hook. Disable must still find
# and remove that hidden hook while retaining the local mapping.
enew
setlocal buftype=nofile bufhidden=hide noswapfile
silent file SimpleWhichKeyLocalShadow
var local_shadow_buf = bufnr()
onoremap <buffer> g iw
var shadow_health = split(execute('SimpleWhichKeyHealth'), "\n")
var operator_health = index(shadow_health, '  mode o')
assert_true(operator_health >= 0)
assert_match('g\s\+hooked', shadow_health[operator_health + 1],
  'Health reports global hook ownership below a local omap')
simplewhichkey#Disable()
assert_equal('iw', maparg('g', 'o'))
enew
setlocal buftype=nofile bufhidden=hide noswapfile
silent file SimpleWhichKeyGlobalProbe
var global_probe_buf = bufnr()
assert_notequal(local_shadow_buf, global_probe_buf)
assert_equal('', maparg('g', 'o'), 'disabled global hook was removed below a local omap')
execute 'buffer ' .. local_shadow_buf
assert_equal('iw', maparg('g', 'o'), 'Disable preserved the local omap')
ounmap <buffer> g
simplewhichkey#Enable()
assert_match('simplewhichkey#OperatorHook', maparg('g', 'o'))

# Conversely, a local mapping hiding a user-owned global mapping must not make
# Enable treat that global slot as free and overwrite it.
simplewhichkey#Disable()
onoremap g iw
onoremap <buffer> g aw
simplewhichkey#Enable()
assert_equal('aw', maparg('g', 'o'))
shadow_health = split(execute('SimpleWhichKeyHealth'), "\n")
operator_health = index(shadow_health, '  mode o')
assert_match('g\s\+taken by another mapping',
  shadow_health[operator_health + 1],
  'Health reports the hidden global user omap as taken')
execute 'buffer ' .. global_probe_buf
assert_equal('iw', maparg('g', 'o'), 'Enable preserved a hidden global user omap')
ounmap g
execute 'buffer ' .. local_shadow_buf
ounmap <buffer> g
simplewhichkey#Setup()
assert_match('simplewhichkey#OperatorHook', maparg('g', 'o'))
assert_equal(2, exists(':SimpleWhichKeyOperator'))
# Hooking a prefix must not disturb the mappings that live under it.
assert_equal("<Cmd>echo 'files'<CR>", maparg('<Space>ff', 'n'))

simplewhichkey#Disable()
assert_equal('', maparg('<Space>', 'n'))
assert_equal('', maparg('g', 'n'))
assert_equal('', maparg('g', 'o'))
assert_equal("<Cmd>echo 'files'<CR>", maparg('<Space>ff', 'n'))
simplewhichkey#Enable()
assert_match('simplewhichkey#Start', maparg('<Space>', 'n'))

# A mapping the user made on a prefix key wins; the hook stays away from it.
nnoremap <silent> Z <Cmd>echo 'mine'<CR>
simplewhichkey#Setup()
assert_equal("<Cmd>echo 'mine'<CR>", maparg('Z', 'n'))
nunmap Z
simplewhichkey#Setup()
assert_match('simplewhichkey#Start', maparg('Z', 'n'))

# An exact user operator mapping owns its prefix slot. Removing it and
# refreshing restores the default operator-pending hook.
simplewhichkey#Disable()
onoremap g iw
simplewhichkey#Enable()
assert_equal('iw', maparg('g', 'o'))
ounmap g
simplewhichkey#Setup()
assert_match('simplewhichkey#OperatorHook', maparg('g', 'o'))

# ------------------------------------------------------------------ level ---

var leader = simplewhichkey#Keys('n', '<leader>')
assert_equal(['e', 'f'], sort(keys(leader)))
assert_true(leader.f.group)
assert_false(leader.e.group)
# Without any registered description the right hand side has to speak.
assert_equal('demo-toggle', leader.e.desc)

var files = simplewhichkey#Keys('n', '<leader>f')
assert_equal(['f', 'r'], sort(keys(files)))
assert_equal('echo ''files''', files.f.desc)

var window = simplewhichkey#Keys('n', '<C-w>')
assert_equal('split-vertical', window.v.desc)
assert_equal('go-down', window.j.desc)
assert_true(window.g.group)
assert_equal('+goto', window.g.desc)
assert_equal('builtin', window.v.source)
# The Ctrl aliases of keys that are already listed are hidden by default.
assert_false(has_key(window, '<C-V>'))
g:simplewhichkey_hide_aliases = 0
assert_true(has_key(simplewhichkey#Keys('n', '<C-w>'), '<C-V>'))
g:simplewhichkey_hide_aliases = 1
# Naming a window command must not resurrect its Ctrl alias. Which keys are the
# same command is a fact about Vim's tables, not about the text on the node.
simplewhichkey#Describe({'<C-w>v': 'vertical split'})
window = simplewhichkey#Keys('n', '<C-w>')
assert_equal('vertical split', window.v.desc)
assert_false(has_key(window, '<C-V>'),
  'a described window command resurrected its Ctrl alias')
simplewhichkey#Forget()

var visual = simplewhichkey#Keys('x', '<leader>')
assert_equal(['f'], keys(visual))
assert_true(visual.f.group)

var operator_i = simplewhichkey#Keys('o', 'i')
assert_equal('inner-word', operator_i.w.desc)
assert_equal('inner-parenthesised', operator_i['('].desc)
assert_equal('inner-tag-block', operator_i.t.desc)
var visual_a = simplewhichkey#Keys('x', 'a')
assert_equal('a-word-with-white-space', visual_a.w.desc)
assert_equal('a-braced-block', visual_a.B.desc)
# Nothing hangs off Normal-mode i/a: text objects do not exist there.
assert_false(has_key(simplewhichkey#Keys('n', 'i'), 'w'))
assert_false(has_key(simplewhichkey#Keys('n', 'a'), 'w'))

var operator_g = simplewhichkey#Keys('o', 'g')
assert_equal('first-line', operator_g.g.desc)
assert_equal('previous-word-end', operator_g.e.desc)
assert_equal('last-screen-column', operator_g['$'].desc)

# Built-in commands and mappings share one panel.
nnoremap <silent> gh <Cmd>echo 'hunk'<CR>
var goto = simplewhichkey#Keys('n', 'g')
assert_equal('first-line', goto.g.desc)
assert_equal('echo ''hunk''', goto.h.desc)
assert_equal('map', goto.h.source)
nunmap gh

# ----------------------------------------------------------- descriptions ---

g:demo_map = {
  f: {
    name: '+file',
    f: 'find files',
    r: ['SimpleFinderRecent', 'recent files'],
  },
  e: 'file tree',
}
simplewhichkey#Register('<leader>', 'g:demo_map', 'n')
leader = simplewhichkey#Keys('n', '<leader>')
assert_equal('+file', leader.f.desc)
assert_equal('file tree', leader.e.desc)
files = simplewhichkey#Keys('n', '<leader>f')
assert_equal('find files', files.f.desc)
assert_equal('recent files', files.r.desc)

simplewhichkey#Forget()
simplewhichkey#Describe({'<leader>f': '+finder', '<leader>ff': 'files'})
leader = simplewhichkey#Keys('n', '<leader>')
assert_equal('+finder', leader.f.desc)
assert_equal('files', simplewhichkey#Keys('n', '<leader>f').f.desc)

# ------------------------------------------------------------------ delay ---

# One number still means the same wait everywhere.
g:simplewhichkey_delay = 120
assert_equal(120, simplewhichkey#ResolvedDelay('n', 'g'))
assert_equal(120, simplewhichkey#ResolvedDelay('o', '<leader>'))

# A table resolves 'mode:prefix', then 'prefix', then 'default'.  Prefix keys
# are compared after termcode expansion, so <leader> and <Space> are one key.
g:simplewhichkey_delay = {
  default: 200,
  '<leader>': 0,
  i: 80,
  'o:i': 40,
}
assert_equal(200, simplewhichkey#ResolvedDelay('n', 'g'))
assert_equal(0, simplewhichkey#ResolvedDelay('n', '<Space>'))
assert_equal(0, simplewhichkey#ResolvedDelay('x', '<leader>'))
assert_equal(80, simplewhichkey#ResolvedDelay('x', 'i'))
assert_equal(40, simplewhichkey#ResolvedDelay('o', 'i'))
# A mode-qualified entry says nothing about the other modes.
assert_equal(80, simplewhichkey#ResolvedDelay('n', 'i'))

# Garbage never reaches the panel loop as a wait.
g:simplewhichkey_delay = 'nope'
assert_equal(200, simplewhichkey#ResolvedDelay('n', 'g'))
g:simplewhichkey_delay = {g: 'nope'}
assert_equal(200, simplewhichkey#ResolvedDelay('n', 'g'))
g:simplewhichkey_delay = 200

# Health must survive a table where it used to printf('%d'), and report the
# delay each prefix resolves to -- with a table that is the only place the
# effective value can be seen.
g:simplewhichkey_delay = {default: 200, g: 250}
var delay_health = execute('SimpleWhichKeyHealth')
assert_match('delay\s*: {', delay_health)
assert_match('g\s\+hooked\s\+\d\+ mapping(s), \d\+ built-in(s), 250 ms',
  delay_health)
g:simplewhichkey_delay = 200
assert_match('delay\s*: 200 ms', execute('SimpleWhichKeyHealth'))

# ---------------------------------------------------------------- conflicts ---

# A mapping another mapping continues cannot dispatch until 'timeoutlen' has
# passed. The plugin already walks the whole tree, so it can say which ones.
nnoremap <leader>x <Cmd>echo 'x'<CR>
nnoremap <leader>xy <Cmd>echo 'xy'<CR>
assert_equal([{short: '<Space>x', long: '<Space>xy'}],
  filter(simplewhichkey#Conflicts('n'), (_, pair) => pair.short ==# '<Space>x'))
nunmap <leader>xy
assert_equal([],
  filter(simplewhichkey#Conflicts('n'), (_, pair) => pair.short ==# '<Space>x'))
nunmap <leader>x

# A description for a key nothing is mapped to is how a Describe() typo shows:
# it is silently ignored everywhere else.
simplewhichkey#Forget()
simplewhichkey#Describe({'<leader>zzz': 'typo', '<leader>ff': 'real'})
assert_true(index(simplewhichkey#Orphans('n'), '<Space>zzz') >= 0)
assert_true(index(simplewhichkey#Orphans('n'), '<Space>ff') < 0)
# A group name describes a prefix, so anything continuing it is coverage.
simplewhichkey#Describe({'<leader>f': '+file'})
assert_true(index(simplewhichkey#Orphans('n'), '<Space>f') < 0)
simplewhichkey#Forget()

var conflict_report = execute('SimpleWhichKeyConflicts')
assert_match('mode n', conflict_report)
assert_match('conflicts', execute('SimpleWhichKeyHealth'))

# ----------------------------------------------------------------- ignore ---

# A hidden key disappears from the panel but keeps working as a mapping.
simplewhichkey#Forget()
setreg('a', 'register-a-content')
g:simplewhichkey_ignore = ['<leader>e']
assert_false(has_key(simplewhichkey#Keys('n', '<leader>'), 'e'))
assert_equal('<Plug>(demo-toggle)', maparg('<Space>e', 'n'))

# The filter covers everything the panel shows, not only leaf mappings: a
# built-in command, ...
g:simplewhichkey_ignore = ['gs']
assert_false(has_key(simplewhichkey#Keys('n', 'g'), 's'),
  'a built-in command ignored the filter')
# ... a register listed from the live editor state, ...
g:simplewhichkey_ignore = ['"a']
assert_false(has_key(simplewhichkey#Keys('n', '"'), 'a'),
  'a dynamic register entry ignored the filter')
# ... and a group prefix, which takes its whole subtree with it.
g:simplewhichkey_ignore = ['<leader>f']
assert_false(has_key(simplewhichkey#Keys('n', '<leader>'), 'f'),
  'a group prefix ignored the filter')

# What a group advertises must not count what it will not show.
g:simplewhichkey_ignore = []
assert_equal('+2 keys', simplewhichkey#Keys('n', '<leader>').f.desc)
g:simplewhichkey_ignore = ['<leader>fr']
assert_equal('+1 keys', simplewhichkey#Keys('n', '<leader>').f.desc,
  'a group counted a child it had already hidden')

# A trailing '**' and a /regexp/ are matched against the notation label.
g:simplewhichkey_ignore = ['<leader>f**']
assert_false(has_key(simplewhichkey#Keys('n', '<leader>'), 'f'))
g:simplewhichkey_ignore = ['/^<Space>[ef]$/']
var filtered = simplewhichkey#Keys('n', '<leader>')
assert_false(has_key(filtered, 'e'))
assert_true(has_key(filtered, 'f'),
  'an anchored regexp matched a leaf, so the group must survive')
# An unusable regexp is a configuration mistake, not a broken keystroke.
g:simplewhichkey_ignore = ['/\(/']
assert_equal(['e', 'f'], sort(keys(simplewhichkey#Keys('n', '<leader>'))),
  'a bad ignore regexp escaped into the panel loop')
g:simplewhichkey_ignore = []

# '*' is a real key and a real register, so one trailing star stays literal:
# hiding '<leader>*' or the '*' register must not swallow their siblings.
nnoremap <silent> <leader>* <Cmd>echo 'star'<CR>
g:simplewhichkey_ignore = ['<leader>*']
assert_equal(['e', 'f'], sort(keys(simplewhichkey#Keys('n', '<leader>'))),
  'a literal trailing * was read as a glob and hid its siblings')
var quoted = sort(keys(simplewhichkey#Keys('n', '"')))
g:simplewhichkey_ignore = ['"+', '"*']
assert_equal(quoted, sort(keys(simplewhichkey#Keys('n', '"'))),
  'hiding the clipboard registers emptied the whole register panel')
# Two stars is the glob, and it still reaches the sibling one star left alone.
g:simplewhichkey_ignore = ['<leader>**']
assert_equal([], sort(keys(simplewhichkey#Keys('n', '<leader>'))),
  'the ** glob did not match')
nunmap <leader>*
g:simplewhichkey_ignore = []

if !empty(v:errors)
  for error in v:errors
    echomsg error
  endfor
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
echomsg '[SimpleWhichKey] smoke tests passed'
qall!
