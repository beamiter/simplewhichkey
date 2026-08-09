vim9script

# Where the panel must tell a person apart from a replay.
#
#   script -qec "vim -N -u NONE -n -i NONE -S tests/vim_keys_macro.vim" /dev/null
#
# This needs a real terminal: the whole question is whether the Insert-mode
# hook blocks in getcharstr() waiting for a key nobody is going to press, and
# under -es there is always an end of file to read instead.
#
# Vim reports keys that are still queued (|state()| "m"), not where the keys
# came from, so a register whose last key is a hooked prefix looks exactly like
# a person who just pressed it.  reg_executing() is the one origin Vim does
# report, and a register is never a person pausing to think.

set nomore
set nocompatible

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

g:simplewhichkey_delay = 50
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplewhichkey.vim')

def PanelVisible(): bool
  return !empty(popup_list())
enddef

def InsertHooked(): bool
  return maparg('<C-r>', 'i') =~# 'simplewhichkey#InsertHook'
enddef

def WaitFor(Cond: func(): bool, ms: number = 1000): bool
  var waited = 0
  while waited < ms
    if Cond()
      return true
    endif
    sleep 10m
    waited += 10
  endwhile
  return Cond()
enddef

def Type(keys: string)
  feedkeys(keys, 't')
enddef

setline(1, ['prefix-'])
setreg('a', 'register-a-content')
# The last key of the register is the hooked prefix, so nothing is queued
# behind it by the time the hook runs.
setreg('q', "A\<C-r>")

var steps = [
  () => {
    assert_true(WaitFor(() => InsertHooked()), 'insert hooks were not installed')
    cursor(1, 1)
    Type('@q')
  },
  () => {
    assert_false(PanelVisible(),
      'a register being replayed must not open the panel')
    # Vim's own CTRL-R is waiting for the register name, exactly as it would
    # without the plugin loaded.
    Type('a')
  },
  () => {
    assert_true(WaitFor(() => getline(1) ==# 'prefix-register-a-content'),
      'the replayed CTRL-R inserted the register natively: ' .. getline(1))
    assert_false(PanelVisible(), 'the replay opened a panel after all')
    Type("\<Esc>")
  },
  () => assert_true(WaitFor(() => mode(1) =~# '^n' && InsertHooked()),
    'insert hooks restored after the replay'),

  # Recording is a person typing, so the guard must not swallow that too.
  () => {
    deletebufline(bufnr(), 1, '$')
    setline(1, ['keep'])
    cursor(1, 1)
    Type("qxA\<C-r>")
  },
  () => {
    assert_true(PanelVisible(), 'recording a register still shows the panel')
    Type("\<Esc>")
  },
  () => {
    assert_false(PanelVisible(), 'Esc dismissed the panel while recording')
    Type("\<Esc>q")
  },
  () => {
    assert_true(WaitFor(() => mode(1) =~# '^n' && empty(reg_recording())),
      'recording did not stop')
    assert_equal('keep', getline(1), 'the dismissed prefix inserted nothing')
  },
]

var index = 0
# A pty swallows anything written to stderr, so the verdict goes to a file the
# runner can read: $SIMPLEWHICHKEY_TEST_OUT, or tests/.keys-macro-result.
const REPORT = empty($SIMPLEWHICHKEY_TEST_OUT)
  ? ROOT .. '/tests/.keys-macro-result'
  : $SIMPLEWHICHKEY_TEST_OUT

def Finish()
  if !empty(v:errors)
    writefile(['FAIL'] + v:errors, REPORT)
    cquit 1
  endif
  writefile(['PASS macro'], REPORT)
  qall!
enddef

def Tick(_: number)
  if index >= len(steps)
    Finish()
    return
  endif
  var Step = steps[index]
  index += 1
  try
    Step()
  catch
    add(v:errors, printf('step %d threw: %s', index, v:exception))
    Finish()
    return
  endtry
  # One-shot rearming keeps an overdue repeating timer from nesting inside the
  # wait the keystroke this callback just queued is about to start.
  timer_start(300, Tick)
enddef

timer_start(300, Tick)
