vim9script

# CTRL-C during the quiet delay used to escape before SelectSequence() entered
# its try/finally.  That left both `active` and one mapping snapshot pinned, so
# every later panel was disabled and mappings added afterwards stayed invisible.

set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

g:simplewhichkey_delay = 500
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplewhichkey.vim')

timer_start(20, (_) => interrupt())
try
  simplewhichkey#Start('g', 'n')
catch /^Vim:Interrupt$/
  # The broken version escapes here.  Continue so the assertions can inspect
  # the state it leaked; the fixed version consumes the interrupt as cancel.
endtry

nnoremap <silent> g<C-K> <Cmd>let g:simplewhichkey_interrupt_hit = 1<CR>
var keys = simplewhichkey#Keys('n', 'g')
assert_true(has_key(keys, '<C-K>'),
  'an interrupt pinned a stale mapping snapshot')

# A leaked `active` flag makes the public entry point immediately replay its
# prefix instead of opening a session.  The health report exposes that flag
# without adding a test-only API.
assert_match('active\s*:\s*no', execute('SimpleWhichKeyHealth'),
  'an interrupt left the panel permanently active')

if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
