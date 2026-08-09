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
# Measure against the text area the popup really has rather than against a
# constant that only happened to match the old frame arithmetic.
var wide_pos = popup_getpos(wide_popup)
for line in wide_lines
  assert_true(strdisplaywidth(line) <= wide_pos.core_width,
    printf('a wide description overflowed the panel: %d columns in %d',
      strdisplaywidth(line), wide_pos.core_width))
endfor
# ASCII keeps working, and the ellipsis is still added.
simplewhichkey#panel#Show('Wide', [
  {label: 'a', desc: repeat('x', 40), group: false},
], "n\x01wide-ascii")
assert_match('x\{11}…',
  getbufline(winbufnr(popup_list()[-1]), 1, '$')[0])
simplewhichkey#panel#Close()
g:simplewhichkey_max_desc_width = 30

# The border and the padding are part of the popup's width.  Vim sizes
# minwidth/maxwidth from the text alone, so a panel that claims the whole
# screen and then draws a frame on top of it is wider than the terminal and
# Vim clips its right border off-screen -- which is what an 80 column Vim used
# to get from a default panel: an 82 column frame.
for border_setting in [1, 0]
  g:simplewhichkey_border = border_setting
  simplewhichkey#panel#Show('Frame', [
    {label: 'a', desc: 'entry', group: false},
  ], "n\x01frame" .. border_setting)
  var framed = popup_getpos(popup_list()[-1])
  assert_true(framed.col + framed.width - 1 <= &columns,
    printf('the panel ran off the screen with border=%d: col %d width %d of %d',
      border_setting, framed.col, framed.width, &columns))
  assert_equal(&columns, framed.col + framed.width - 1,
    printf('the panel left screen columns unused with border=%d', border_setting))
endfor
g:simplewhichkey_border = 1
simplewhichkey#panel#Close()

# The full-width bar stays the default (asserted just above), but a panel can
# be fitted to what it drew or pinned to a width.
const NARROW = [
  {label: 'a', desc: 'one', group: false},
  {label: 'b', desc: 'two', group: false},
]
g:simplewhichkey_width = 'fit'
simplewhichkey#panel#Show('Fit', NARROW, "n\x01fit")
var fit_popup = popup_list()[-1]
var fitted = popup_getpos(fit_popup)
var fitted_widest = max(mapnew(
  getbufline(winbufnr(fit_popup), 1, '$'), (_, line) => strdisplaywidth(line)))
assert_true(fitted.width < &columns,
  printf('a fitted panel still claimed the screen: %d of %d columns',
    fitted.width, &columns))
assert_true(fitted.core_width >= fitted_widest,
  printf('a fitted panel is narrower than its own rows: %d < %d',
    fitted.core_width, fitted_widest))
# It never shrinks below its title, which is where the page counter lives.
assert_true(fitted.core_width >= strdisplaywidth(' Fit ') + 2,
  printf('a fitted panel cut its own title: %d columns', fitted.core_width))
assert_true(fitted.core_width <= max([fitted_widest, strdisplaywidth(' Fit ') + 2]),
  printf('a fitted panel kept slack: %d columns for %d of text',
    fitted.core_width, fitted_widest))

g:simplewhichkey_width = 30
simplewhichkey#panel#Show('Pinned', NARROW, "n\x01pinned")
assert_equal(30, popup_getpos(popup_list()[-1]).core_width,
  'a pinned width is not the width the panel got')
# A width wider than the screen is clamped rather than clipped.
g:simplewhichkey_width = 500
simplewhichkey#panel#Show('Pinned', NARROW, "n\x01pinned-wide")
var clamped = popup_getpos(popup_list()[-1])
assert_equal(&columns, clamped.col + clamped.width - 1,
  'an oversized width escaped the screen')
g:simplewhichkey_width = 0
simplewhichkey#panel#Close()

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
# Insert and command-line mode carry two prefixes nothing else can enumerate:
# the register CTRL-R takes, and the completion kind CTRL-X picks.
assert_match('simplewhichkey#InsertHook', maparg('<C-r>', 'i'))
assert_match('simplewhichkey#InsertHook', maparg('<C-x>', 'i'))
assert_match('simplewhichkey#InsertHook', maparg('<C-r>', 'c'))
assert_equal('', maparg('<C-x>', 'c'), 'CTRL-X completion is Insert mode only')

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
# Naming the Ctrl form itself is the opposite request: it says this key is
# wanted.  Accepting the description and then dropping the node with it would
# make a deliberate registration disappear without a word.
simplewhichkey#Describe({'<C-w><C-v>': 'my own ctrl-v split'})
window = simplewhichkey#Keys('n', '<C-w>')
assert_true(has_key(window, '<C-V>'),
  'a description registered for the alias itself was discarded with the node')
assert_equal('my own ctrl-v split', window['<C-V>'].desc)
assert_true(has_key(window, 'v'), 'the plain key must survive alongside it')
simplewhichkey#Forget()
assert_false(has_key(simplewhichkey#Keys('n', '<C-w>'), '<C-V>'),
  'forgetting the description must hide the alias again')

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

# CTRL-X completion kinds, which nobody remembers more than two of.
var completion = simplewhichkey#Keys('i', '<C-x>')
assert_equal('omni-completion', completion['<C-O>'].desc)
assert_equal('file-names', completion['<C-F>'].desc)
assert_equal('spelling-suggestions', completion.s.desc)
assert_false(has_key(completion, '<C-S>'),
  'the Ctrl alias of a plain completion key is a duplicate here too')

# CTRL-R ends in a register name, in Insert and on the command line alike, and
# its three CTRL sub-forms take one as well.
setreg('a', 'register-a-content')
var insert_registers = simplewhichkey#Keys('i', '<C-r>')
assert_equal('register-a-content', insert_registers.a.desc)
assert_equal('dynamic', insert_registers.a.source)
assert_true(insert_registers['<C-R>'].group)
assert_equal('expression-register', insert_registers['='].desc)
assert_equal('register-a-content',
  simplewhichkey#Keys('i', '<C-r><C-r>').a.desc)
assert_equal('register-a-content', simplewhichkey#Keys('c', '<C-r>').a.desc)
# While typing, '"' and the mark keys are ordinary text, so nothing hangs off
# them, and CTRL-X means nothing on the command line.
assert_equal({}, simplewhichkey#Keys('i', "'"))
assert_equal({}, simplewhichkey#Keys('i', '"'))
assert_equal({}, simplewhichkey#Keys('c', '<C-x>'))

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
simplewhichkey#Forget()

# ---------------------------------------------------------------- derived ---

# A mapping onto one of Vim's own prefixed commands already has a name in the
# built-in tables, and that name beats repeating its keys.
nnoremap <silent> <leader>w= <C-w>=
nnoremap <silent> <leader>wv <C-w>v
assert_equal('equalize-sizes', simplewhichkey#Keys('n', '<leader>w')['='].desc)
assert_equal('split-vertical', simplewhichkey#Keys('n', '<leader>w').v.desc)
# The lookup follows the mode, so an omap onto a text object is named as one.
onoremap gy iw
assert_equal('inner-word', simplewhichkey#Keys('o', 'g').y.desc)
ounmap gy
g:simplewhichkey_derive = 0
assert_equal('<C-w>=', simplewhichkey#Keys('n', '<leader>w')['='].desc,
  'turning derivation off must restore the plain right hand side')
g:simplewhichkey_derive = 1
nunmap <leader>w=
nunmap <leader>wv

# An unnamed group says how much is behind the key and nothing about what.
# When every mapping under it is named after the same thing, that shared
# beginning is the name a user would have written by hand.
nnoremap <silent> <leader>gs <Cmd>SimpleGitStatus<CR>
nnoremap <silent> <leader>gd <Cmd>SimpleGitDiff<CR>
nnoremap <silent> <leader>gl <Cmd>SimpleGitLog<CR>
assert_equal('+SimpleGit', simplewhichkey#Keys('n', '<leader>').g.desc)
g:simplewhichkey_derive = 0
assert_equal('+3 keys', simplewhichkey#Keys('n', '<leader>').g.desc)
g:simplewhichkey_derive = 1
# A registered name still wins over anything derived.
simplewhichkey#Describe({'<leader>g': '+git'})
assert_equal('+git', simplewhichkey#Keys('n', '<leader>').g.desc)
simplewhichkey#Forget()
# A shared beginning that does not dominate its children is not a subject:
# 'echo' in front of two different :echo commands names nothing.
assert_equal('+2 keys', simplewhichkey#Keys('n', '<leader>').f.desc)
# Neither is a half word: the cut lands on a word boundary or nowhere.
# SimpleGitStatus and SimpleGitStash share 'SimpleGitSta', which is half of
# both, so the name falls back to the boundary below it.
nunmap <leader>gd
nunmap <leader>gl
nnoremap <silent> <leader>gl <Cmd>SimpleGitStash<CR>
assert_equal('+SimpleGit', simplewhichkey#Keys('n', '<leader>').g.desc,
  'a shared beginning that stops mid word must cut back to a boundary')
# A shared beginning that is the whole of one name is already a boundary, and
# the name is all of it: two keys onto the same command are named after that
# command, not after its first word.
nunmap <leader>gl
nnoremap <silent> <leader>gl <Cmd>SimpleGitStatus<CR>
assert_equal('+SimpleGitStatus', simplewhichkey#Keys('n', '<leader>').g.desc,
  'a name the others begin with must not be cut short')
nunmap <leader>gs
nunmap <leader>gl

# ------------------------------------------------------- buffer-local names -

# The same key means something else in another filetype, and a global registry
# cannot say so.
simplewhichkey#Describe({'<leader>e': 'global name'})
assert_equal('global name', simplewhichkey#Keys('n', '<leader>').e.desc)
simplewhichkey#Describe({'<leader>e': 'this buffer only', '<leader>f': '+here'},
  'n', true)
assert_equal('this buffer only', simplewhichkey#Keys('n', '<leader>').e.desc)
assert_equal('+here', simplewhichkey#Keys('n', '<leader>').f.desc)
new
assert_equal('global name', simplewhichkey#Keys('n', '<leader>').e.desc,
  'a buffer-local name escaped its buffer')
bwipe!
# Forget() drops the global registry; the buffer keeps its own.
simplewhichkey#Forget()
assert_equal('this buffer only', simplewhichkey#Keys('n', '<leader>').e.desc)
unlet b:simplewhichkey_descriptions
unlet b:simplewhichkey_groups

# There is no buffer-scoped Forget(), so :unlet is how an ftplugin resets its
# own names -- and it may unlet one of the two dicts and not the other.  The
# next call must rebuild whichever is missing rather than throw.
simplewhichkey#Describe({'<leader>e': 'this buffer only'}, 'n', true)
unlet b:simplewhichkey_groups
var describe_error = ''
try
  simplewhichkey#Describe({'<leader>f': '+here'}, 'n', true)
catch
  describe_error = v:exception
endtry
assert_equal('', describe_error,
  'describing after one of the two buffer dicts was unlet must not throw')
assert_equal('+here', simplewhichkey#Keys('n', '<leader>').f.desc,
  'a group named after one dict was unlet must still land')
unlet b:simplewhichkey_descriptions
simplewhichkey#Describe({'<leader>e': 'back again'}, 'n', true)
assert_equal('back again', simplewhichkey#Keys('n', '<leader>').e.desc)
assert_equal('+here', simplewhichkey#Keys('n', '<leader>').f.desc,
  'the dict that was left alone must keep its names')
unlet b:simplewhichkey_descriptions
unlet b:simplewhichkey_groups

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

# Insert mode and the command line share a prefix and want different waits,
# so they scope like the others.
g:simplewhichkey_delay = {
  default: 200,
  '<C-r>': 90,
  'i:<C-r>': 30,
  'c:<C-r>': 60,
  'i:<C-x>': 50,
}
assert_equal(30, simplewhichkey#ResolvedDelay('i', '<C-r>'))
assert_equal(60, simplewhichkey#ResolvedDelay('c', '<C-r>'))
assert_equal(50, simplewhichkey#ResolvedDelay('i', '<C-x>'))
# The unscoped entry still answers for the mode nobody scoped.
assert_equal(90, simplewhichkey#ResolvedDelay('n', '<C-r>'))
assert_equal(200, simplewhichkey#ResolvedDelay('c', '<C-x>'))

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

# ------------------------------------------------------------------- tree ---

# The panel answers one level at a time, which is the right question while
# typing and the wrong one while configuring: a popup cannot be searched.
simplewhichkey#Forget()
simplewhichkey#Describe({'<leader>f': '+file', '<leader>ff': 'files'})
var tree = simplewhichkey#Tree('n', '<leader>')
# Depth first, and every level in the order the panel would draw it, so the
# two views of one key map never disagree.
assert_equal(['<Space>e', '<Space>f', '<Space>ff', '<Space>fr'],
  mapnew(tree, (_, row) => row.keys))
assert_equal('+file', tree[1].desc)
assert_true(tree[1].group)
assert_equal('files', tree[2].desc)
assert_equal('map', tree[2].source)

# The walk is bounded: a mistaken group could otherwise recurse as deep as a
# key sequence can grow.
assert_equal(['<Space>e', '<Space>f'],
  mapnew(simplewhichkey#Tree('n', '<leader>', 1), (_, row) => row.keys))

# With no prefix, every hooked prefix of that mode, each introduced by a row
# of its own so the output reads as a tree.
var whole = simplewhichkey#Tree('n')
var roots = filter(copy(whole), (_, row) => row.source ==# 'prefix')
assert_true(index(mapnew(roots, (_, row) => row.keys), '<Space>') >= 0)
assert_true(index(mapnew(roots, (_, row) => row.keys), '<C-W>') >= 0)
assert_true(index(mapnew(whole, (_, row) => row.keys), '<Space>ff') >= 0)

# What is hidden from the panel is hidden from the listing too: one filter,
# not two.
g:simplewhichkey_ignore = ['<leader>f']
assert_equal(['<Space>e'],
  mapnew(simplewhichkey#Tree('n', '<leader>'), (_, row) => row.keys))
g:simplewhichkey_ignore = []

# Insert mode has a tree of its own, and CTRL-R's sub-forms lead back to the
# register list rather than dead-ending.
setreg('a', 'register-a-content')
var insert_tree = mapnew(simplewhichkey#Tree('i', '<C-r>'), (_, row) => row.keys)
assert_true(index(insert_tree, '<C-R>a') >= 0)
assert_true(index(insert_tree, '<C-R><C-R>a') >= 0)

assert_equal(['n', 'x', 'o', 'i', 'c'], simplewhichkey#CompleteMode('', '', 0))
assert_equal(['n'], simplewhichkey#CompleteMode('n', '', 0))

SimpleWhichKeyList
assert_equal('simplewhichkeylist', &filetype)
assert_equal('nofile', &buftype)
var listed = join(getline(1, '$'), "\n")
assert_match('^" SimpleWhichKey: mode n, \d\+ sequences, depth \d\+', listed)
assert_match('<Space>ff\s\+files\s\+map', listed)
assert_match('<Space>f\s\++file\s\+map', listed)
bwipe!

SimpleWhichKeyList!
assert_equal('SimpleWhichKey n', getqflist({title: 1}).title)
assert_true(!empty(filter(getqflist(), (_, item) => item.text =~# '<Space>ff')),
  'the quickfix form must carry the same rows')
# The two columns are separated by a tab, not by the two characters a
# single-quoted '\t' would leave in every row.
var qf_row = filter(getqflist(), (_, item) => item.text =~# '<Space>ff')[0]
assert_equal("<Space>ff\tfiles", qf_row.text)
assert_false(qf_row.text =~# '\\t',
  'a literal backslash-t must not reach the quickfix list')
cclose
call setqflist([], 'r')
simplewhichkey#Forget()

if !empty(v:errors)
  for error in v:errors
    echomsg error
  endfor
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
echomsg '[SimpleWhichKey] smoke tests passed'
qall!
