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

var visual = simplewhichkey#Keys('x', '<leader>')
assert_equal(['f'], keys(visual))
assert_true(visual.f.group)

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

# A hidden key disappears from the panel but keeps working as a mapping.
g:simplewhichkey_ignore = ['<leader>e']
assert_false(has_key(simplewhichkey#Keys('n', '<leader>'), 'e'))
assert_equal('<Plug>(demo-toggle)', maparg('<Space>e', 'n'))
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
