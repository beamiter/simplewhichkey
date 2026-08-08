vim9script

# Scale guard.
#
#   vim -N -u NONE -n -es -S tests/vim_scale.vim
#
# What a panel costs is the number of times the mapping table is read
# multiplied by how many mappings are in it.  maplist() copies every mapping,
# and Level() used to call it once to decide whether a prefix has anything to
# show, again for the first panel, again per descending keystroke, and once per
# group when the whole tree is listed.
#
# Timing assertions are worthless here -- a loaded machine makes them lie in
# both directions -- so the budget is expressed as the thing that actually
# scales: how many sweeps one operation takes.  These assertions go red the
# moment a sweep is added back, whatever the machine is doing.

set nomore
set nocompatible

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

g:mapleader = ' '
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplewhichkey.vim')

const LETTERS = split('abcdefghijklmnopqrstuvwxyz', '\zs')
for group in LETTERS
  for leaf in LETTERS
    execute printf('nnoremap <silent> <leader>%s%s <Cmd>echo ''%s%s''<CR>',
      group, leaf, group, leaf)
  endfor
endfor
simplewhichkey#Setup()

# The fixture has to be big enough that a per-group sweep would be obvious.
assert_equal(26, len(simplewhichkey#Keys('n', '<leader>')))

# One level, one sweep.
var before = simplewhichkey#Sweeps()
assert_equal(26, len(simplewhichkey#Keys('n', '<leader>a')))
assert_equal(1, simplewhichkey#Sweeps() - before,
  'listing one level must read the mapping table exactly once')

# One subtree, still one sweep: the walk visits 27 groups.
before = simplewhichkey#Sweeps()
var subtree = simplewhichkey#Tree('n', '<leader>')
assert_equal(1, simplewhichkey#Sweeps() - before,
  'walking a subtree must not read the mapping table once per group')
assert_equal(26 + 26 * 26, len(subtree),
  'the walk has to be complete, not merely cheap')

# The whole keymap of a mode, still one sweep.
before = simplewhichkey#Sweeps()
var whole = simplewhichkey#Tree('n')
assert_equal(1, simplewhichkey#Sweeps() - before,
  'listing every hooked prefix must not read the mapping table per prefix')
assert_true(len(whole) > len(subtree))

# The reports walk the same tree and pay the same once.
before = simplewhichkey#Sweeps()
var health = execute('SimpleWhichKeyHealth')
assert_equal(1, simplewhichkey#Sweeps() - before,
  'Health must read the mapping table once, not once per hooked prefix')

before = simplewhichkey#Sweeps()
var conflicts = execute('SimpleWhichKeyConflicts')
assert_equal(1, simplewhichkey#Sweeps() - before,
  'the conflict report must read the mapping table once')

# A snapshot must never outlive the operation that opened it, or a mapping
# added afterwards would be invisible.
nnoremap <silent> <leader>z1 <Cmd>echo 'late'<CR>
assert_equal(27, len(simplewhichkey#Keys('n', '<leader>z')),
  'a mapping added after the last panel was missing from the next one')

if !empty(v:errors)
  for error in v:errors
    echomsg error
  endfor
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
echomsg '[SimpleWhichKey] scale tests passed'
qall!
