vim9script

set nocompatible nomore
var root = fnamemodify(expand('<sfile>'), ':p:h:h')
execute 'set runtimepath^=' .. fnameescape(root)

# A dictionary containing only unknown modes used to survive Prefixes() as
# non-empty, then Setup() discarded it and installed no hooks.  An unusable
# configuration should fall back as a whole, just like a wrong top-level type.
g:simplewhichkey_prefixes = {bad: [42, 'x']}
g:simplewhichkey_delay = {default: 'slow'}
g:simplewhichkey_position = 'somewhere'
g:simplewhichkey_width = 'wide'
g:simplewhichkey_ignore = 'not-a-list'
execute 'source ' .. fnameescape(root .. '/plugin/simplewhichkey.vim')

assert_true(has_key(g:simplewhichkey_prefixes, 'n'))
assert_true(index(g:simplewhichkey_prefixes.n, '<leader>') >= 0)
assert_false(has_key(g:simplewhichkey_prefixes, 'bad'))
assert_equal(200, g:simplewhichkey_delay)
assert_equal('bottom', g:simplewhichkey_position)
assert_equal(0, g:simplewhichkey_width)
assert_equal([], g:simplewhichkey_ignore)
assert_match('simplewhichkey#Start', maparg('g', 'n'))

g:simplewhichkey_enable = v:false
simplewhichkey#Setup()
assert_equal('', maparg('g', 'n'),
  'a bool g:simplewhichkey_enable = v:false was ignored')
g:simplewhichkey_enable = v:true
simplewhichkey#Setup()
assert_match('simplewhichkey#Start', maparg('g', 'n'))

g:simplewhichkey_delay = 99999
assert_equal(5000, simplewhichkey#ResolvedDelay('n', 'g'),
  'a delay past 5000 ms was not clamped')
g:simplewhichkey_delay = {default: 8000, 'n:g': 9000}
assert_equal(5000, simplewhichkey#ResolvedDelay('n', 'g'))
g:simplewhichkey_delay = 200

if !empty(v:errors)
  writefile(v:errors, root .. '/tests/config-errors.log')
  cquit!
endif
delete(root .. '/tests/config-errors.log')
qall!
