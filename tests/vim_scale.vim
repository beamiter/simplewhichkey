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
#
# A sweep is the copy and an iteration is the read, and the two have to be
# budgeted separately: opening a snapshot pins the sweep count at 1 no matter
# how many times the code inside walks the table, so a sweep budget alone
# would have gone quiet over Setup() reading every mapping once per hooked
# prefix.  Registers get a budget of their own for the same reason -- what a
# register panel costs is bytes of register read, and nothing about the
# mapping table can see that.

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

# ------------------------------------------------------------ hook phases ---

# Taking the prefixes and giving them back used to ask the mapping table about
# each prefix on its own: 30 sweeps to install and 30 to remove, for the
# default set.  That is not only a startup cost -- :SimpleWhichKeyRefresh runs
# the same Setup(), and every panel the user dismisses ends in Restore(),
# which reinstalls the hooks of the modes it suspended.
before = simplewhichkey#Sweeps()
simplewhichkey#Setup()
assert_equal(2, simplewhichkey#Sweeps() - before,
  'Setup() must read the mapping table once per phase, not once per prefix')

before = simplewhichkey#Sweeps()
simplewhichkey#Disable()
assert_equal(1, simplewhichkey#Sweeps() - before,
  'removing the hooks must read the mapping table once')
before = simplewhichkey#Sweeps()
simplewhichkey#Enable()
assert_equal(1, simplewhichkey#Sweeps() - before,
  'installing the hooks must read the mapping table once')

# The hooks have to still be there afterwards: a snapshot held across the loop
# is only safe because each pass asks about one prefix and writes that same
# prefix, so a stale answer for a prefix nothing has touched cannot exist.
assert_match('simplewhichkey#Start', maparg('<Space>', 'n'))
assert_match('simplewhichkey#OperatorHook', maparg('g', 'o'))
assert_match('simplewhichkey#InsertHook', maparg("\<C-r>", 'c'))

# ------------------------------------------------------------- iterations ---

# Everything above is counted in sweeps, and a sweep budget stops counting the
# moment a snapshot is open: the walk below costs one sweep whether it reads
# the table once or a hundred times.  So the same operations are budgeted a
# second time in entries read.
const MAPPINGS = len(maplist())
assert_true(MAPPINGS > 676, 'the fixture must dominate the default hooks')

var iterated = simplewhichkey#Iterations()
assert_equal(26, len(simplewhichkey#Keys('n', '<leader>a')))
assert_equal(2 * MAPPINGS, simplewhichkey#Iterations() - iterated,
  'one level must read the mapping table twice: global mappings, then buffer-local')

# The subtree walk visits 27 levels, and every one of them reads the whole
# table twice.  One sweep says nothing about that; this is the real price of
# listing a subtree, and it is here so that it can only ever go down.
iterated = simplewhichkey#Iterations()
subtree = simplewhichkey#Tree('n', '<leader>')
assert_true(simplewhichkey#Iterations() - iterated <= 2 * 27 * MAPPINGS,
  'the subtree walk read the mapping table more than twice per level visited')

# Setup() is still one scan per prefix per phase -- the snapshot removed the
# copying, not the reading.  Budgeted so it cannot grow past that.
iterated = simplewhichkey#Iterations()
simplewhichkey#Setup()
assert_true(simplewhichkey#Iterations() - iterated <= 60 * MAPPINGS,
  'Setup() read the mapping table more than once per prefix per phase')

# -------------------------------------------------------- register panels ---

# The register panel has a scale of its own that no mapping count can see: a
# yanked file is megabytes, there are ~48 registers, and thirty characters of
# each is all a panel can draw.  This has been the same bug twice.  Flattening
# the whole register to produce those thirty characters cost 48 ms for seven
# 132 KB registers; taking the whole register in order to hand it to the
# flattening then cost 74 ms for seven 150 KB ones, which is why the counter
# now sits where the text is taken rather than where it is flattened.  Both
# times the panel drew exactly the same thirty characters.
#
# The budget is 48 registers and, from each, twice the 31 composed characters
# the preview can use -- thirty to draw and one to decide the ellipsis -- at
# four bytes to the widest character Vim counts as one.  Twice, because the
# head is taken a line at a time and the line that crosses the limit is taken
# up to the limit itself before the crossing is noticed.  Composed is the word
# that stops this being an absolute bound: a character carries its combining
# marks and there is no limit on how many of those there can be, so a register
# holding one letter under a megabyte of marks is still read in full.  That is
# the price of previewing it the same way as before, it is what the old code
# paid for every register, and no ordinary register comes near the number.  A
# run that inherits registers from a |viminfo-file| stays well inside it;
# either regression passes it by orders of magnitude on this fixture alone.
const REGISTER_BUDGET = 48 * 2 * 31 * 4
setreg('p', repeat('x', 400000))
setreg('q', repeat("y\n", 200000))
var scanned = simplewhichkey#builtin#Scanned()
assert_true(len(simplewhichkey#Keys('n', '"')) >= 2)
assert_true(simplewhichkey#builtin#Scanned() - scanned <= REGISTER_BUDGET,
  'a register panel read more of the registers than it could ever show')
setreg('p', '')
setreg('q', '')

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
