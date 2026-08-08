vim9script

# Clipboard/operator replay needs a fresh Vim for each default register.  In a
# long PTY scenario v:register intentionally describes the command/mapping in
# flight and can retain the previous clipboard choice long enough to make a
# later "native baseline" meaningless.

set nomore
set nocompatible

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

const SETTING = $SIMPLEWHICHKEY_TEST_CLIPBOARD
const REPORT = $SIMPLEWHICHKEY_TEST_OUT
if index(['unnamedplus', 'unnamed'], SETTING) < 0 || empty(REPORT)
  cquit 2
endif

g:mapleader = ' '
g:simplewhichkey_delay = 50
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplewhichkey.vim')

var clipboard_register = SETTING ==# 'unnamedplus' ? '+' : '*'
var original_prefixes = deepcopy(g:simplewhichkey_prefixes)
var memory_provider = false

# Keep the regression independent of an X11/Wayland session and avoid touching
# the user's desktop clipboard. Vim's provider still exercises the real +/*
# register and 'clipboard' mirroring code paths.
g:simplewhichkey_clipboard_store = {
  '+': ['v', []],
  '*': ['v', []],
}

def g:SimpleWhichKeyClipboardAvailable(): bool
  return true
enddef

def g:SimpleWhichKeyClipboardCopy(
    register: string,
    regtype: string,
    lines: list<string>)
  g:simplewhichkey_clipboard_store[register] = [regtype, copy(lines)]
enddef

def g:SimpleWhichKeyClipboardPaste(register: string): list<any>
  return deepcopy(g:simplewhichkey_clipboard_store[register])
enddef

if exists('v:clipproviders') && exists('+clipmethod')
  v:clipproviders['simplewhichkey-test'] = {
    available: function('g:SimpleWhichKeyClipboardAvailable'),
    copy: {
      '+': function('g:SimpleWhichKeyClipboardCopy'),
      '*': function('g:SimpleWhichKeyClipboardCopy'),
    },
    paste: {
      '+': function('g:SimpleWhichKeyClipboardPaste'),
      '*': function('g:SimpleWhichKeyClipboardPaste'),
    },
  }
  &clipmethod = 'simplewhichkey-test'
  memory_provider = true
endif

def g:SimpleWhichKeyClipboardOperator(type: string)
  g:simplewhichkey_clipboard_capture = {
    type: type,
    first: line("'["),
    last: line("']"),
    register: v:register,
  }
enddef

nnoremap <silent> Q g@

def PanelVisible(): bool
  return !empty(popup_list())
enddef

def Hooked(): bool
  return maparg('g', 'n') =~# 'simplewhichkey#Start'
    && maparg('g', 'o') =~# 'simplewhichkey#OperatorHook'
enddef

def OperatorHooked(): bool
  return maparg('g', 'o') =~# 'simplewhichkey#OperatorHook'
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

def Lines(): list<string>
  return mapnew(range(1, 10), (_, nr) => 'line-' .. nr)
enddef

def PutFixture()
  deletebufline(bufnr(), 1, '$')
  setline(1, Lines())
  cursor(8, 1)
enddef

&clipboard = SETTING
&operatorfunc = 'g:SimpleWhichKeyClipboardOperator'
g:simplewhichkey_clipboard_capture = {}

# A Vim built without clipboard support has no `+`/`*` registers at all: the
# in-memory provider above cannot be installed (no 'clipmethod'), `&clipboard`
# silently no-ops, and typing `"+` is rejected with E354 so v:register stays
# `"`.  The explicit-register half of this scenario is then untestable by
# construction, while everything before it is register-agnostic and still
# meaningful -- so run that and record the omission instead of failing.
const explicit_registers = memory_provider || has('clipboard')
var skips: list<string> = []
if !explicit_registers
  add(skips, $'SKIP explicit {clipboard_register} register steps: '
    .. 'this Vim has no clipboard registers '
    .. $'(has("clipboard")={has("clipboard")}, '
    .. $'exists("+clipmethod")={exists("+clipmethod")})')
endif

var steps = [
  # Establish the native operatorfunc register in an otherwise fresh process.
  () => {
    simplewhichkey#Disable()
    PutFixture()
    Type('g@iw')
  },
  () => {
    assert_true(WaitFor(() => !empty(g:simplewhichkey_clipboard_capture)),
      $'native {SETTING} g@ completed')
    g:simplewhichkey_native_register =
      g:simplewhichkey_clipboard_capture.register
    g:simplewhichkey_clipboard_capture = {}
    PutFixture()
    Type('Qgg')
  },
  () => {
    assert_true(WaitFor(() => !empty(g:simplewhichkey_clipboard_capture)),
      $'native mapped {SETTING} g@ completed')
    g:simplewhichkey_native_mapped_register =
      g:simplewhichkey_clipboard_capture.register
    g:simplewhichkey_clipboard_capture = {}
    simplewhichkey#Enable()
    assert_true(WaitFor(() => Hooked()))
    PutFixture()
    Type('g')
  },
  # Full Normal g panel -> g@ -> operator g panel -> gg motion.
  () => {
    assert_true(PanelVisible(), $'{SETTING} Normal g panel before g@')
    Type('@')
  },
  () => {
    assert_true(WaitFor(() => state('o') !=# '' && OperatorHooked()),
      $'{SETTING} g@ retains the operator hook')
    Type('g')
  },
  () => {
    assert_true(PanelVisible(), $'{SETTING} operator g panel')
    Type('g')
  },
  () => {
    var done = WaitFor(() => !empty(g:simplewhichkey_clipboard_capture)
      && Hooked())
    if !done
      assert_report($'hooked {SETTING} g@g incomplete: capture='
        .. string(g:simplewhichkey_clipboard_capture)
        .. ' nmap=' .. string(maparg('g', 'n'))
        .. ' omap=' .. string(maparg('g', 'o'))
        .. ' state=' .. state('mo') .. ' mode=' .. mode(1))
      return
    endif
    assert_equal(g:simplewhichkey_native_register,
      g:simplewhichkey_clipboard_capture.register,
      $'{SETTING} callback register matches native g@')
    g:simplewhichkey_clipboard_capture = {}
    PutFixture()
    Type('Qg')
  },
  # A mapping that starts g@ carries its own v:register context.
  () => {
    assert_true(PanelVisible(), $'mapped g@ reaches {SETTING} operator panel')
    Type('g')
  },
  () => {
    var done = WaitFor(() => !empty(g:simplewhichkey_clipboard_capture)
      && Hooked())
    if !done
      assert_report($'mapped {SETTING} g@ incomplete: capture='
        .. string(g:simplewhichkey_clipboard_capture)
        .. ' nmap=' .. string(maparg('g', 'n'))
        .. ' omap=' .. string(maparg('g', 'o'))
        .. ' state=' .. state('mo') .. ' mode=' .. mode(1))
      return
    endif
    assert_equal(g:simplewhichkey_native_mapped_register,
      g:simplewhichkey_clipboard_capture.register,
      $'mapped {SETTING} callback register matches its native mapping')
    if memory_provider
      PutFixture()
      Type('yg')
    endif
  },
  () => {
    if memory_provider
      assert_true(PanelVisible(), $'{SETTING} ygg reaches operator panel')
      Type('g')
    endif
  },
  () => {
    if memory_provider
      assert_true(WaitFor(() => Hooked()))
      var expected = Lines()[0 : 7]
      assert_equal(expected, getreg('"', 1, 1),
        $'{SETTING} ygg updates the unnamed register')
      # Compare text lines rather than a provider-specific trailing newline.
      assert_equal(expected, split(getreg(clipboard_register), "\n"),
        $'{SETTING} ygg mirrors text to {clipboard_register}')
    endif
  },
]

# Everything below needs a real `+`/`*` register to type and to observe.
var explicit_steps = [
  () => {
    # Remove the separate Normal `"` panel so this fixture isolates the
    # operator hook while retaining an explicitly typed clipboard register.
    simplewhichkey#Disable()
    var without_quote = deepcopy(original_prefixes)
    without_quote.n = filter(copy(without_quote.n),
      (_, prefix) => prefix !=# '"')
    g:simplewhichkey_prefixes = without_quote
    simplewhichkey#Setup()
    g:simplewhichkey_clipboard_capture = {}
    PutFixture()
    Type('"' .. clipboard_register .. 'g@iw')
  },
  () => {
    assert_true(WaitFor(() => !empty(g:simplewhichkey_clipboard_capture)),
      $'native explicit {clipboard_register} g@ completed')
    g:simplewhichkey_explicit_register =
      g:simplewhichkey_clipboard_capture.register
    assert_equal(clipboard_register, g:simplewhichkey_explicit_register)
    g:simplewhichkey_clipboard_capture = {}
    simplewhichkey#Enable()
    assert_true(WaitFor(() => Hooked()))
    PutFixture()
    Type('"' .. clipboard_register .. 'g')
  },
  () => {
    assert_true(PanelVisible(),
      $'explicit {clipboard_register} reaches the Normal g panel')
    Type('@')
  },
  () => {
    assert_true(WaitFor(() => state('o') !=# '' && OperatorHooked()))
    Type('g')
  },
  () => {
    assert_true(PanelVisible(),
      $'explicit {clipboard_register} reaches the operator g panel')
    Type('g')
  },
  () => {
    assert_true(WaitFor(() => !empty(g:simplewhichkey_clipboard_capture)
      && Hooked()))
    assert_equal(g:simplewhichkey_explicit_register,
      g:simplewhichkey_clipboard_capture.register,
      $'explicit {clipboard_register} callback identity stays native')
    g:simplewhichkey_prefixes = deepcopy(original_prefixes)
    simplewhichkey#Setup()
  },
]

if explicit_registers
  steps += explicit_steps
endif

var index = 0
var retry_index = -1
var retry_count = 0

def Finish()
  # The verdict stays on its own first line: the Makefile greps for it anchored,
  # and cats the whole file so the SKIP notes are read by whoever ran the gate.
  if !empty(v:errors)
    writefile(['FAIL'] + v:errors + skips, REPORT)
    cquit 1
  endif
  writefile(['PASS ' .. SETTING] + skips, REPORT)
  qall!
enddef

def Tick(_: number)
  # Do not advance from a recursive timer while the previous mapping is still
  # inside its pre-panel poll. Returning lets that older stack reach either a
  # visible panel or idle state before the next tick retries this step.
  if !PanelVisible() && !empty(state('m'))
    if retry_index == index
      retry_count += 1
    else
      retry_index = index
      retry_count = 1
    endif
    if retry_count >= 10
      assert_report('clipboard PTY step did not settle: index=' .. index
        .. ' state=' .. state('mo') .. ' mode=' .. mode(1)
        .. ' nmap=' .. string(maparg('g', 'n'))
        .. ' omap=' .. string(maparg('g', 'o')))
      Finish()
      return
    endif
    timer_start(300, Tick)
    return
  endif
  retry_index = -1
  retry_count = 0
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
  timer_start(300, Tick)
enddef

# One-shot rearming starts the delay only after the current callback returns,
# keeping each step behind both the previous mapping and the 200ms hook restore.
timer_start(300, Tick)
