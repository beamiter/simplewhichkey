vim9script

# End to end checks: real keystrokes, real popup, real replay.  These need a
# terminal, so they are driven through a pty:
#
#   script -qec "vim -N -u NONE -n -i NONE -S tests/vim_keys.vim" /dev/null
#
# Steps run from a repeating timer.  Timers keep firing while the plugin blocks
# in getcharstr(), which is what lets a step answer the panel that the previous
# step opened.

set nomore
set nocompatible

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

g:mapleader = ' '
g:maplocalleader = ','
g:simplewhichkey_delay = 50
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplewhichkey.vim')
var original_prefixes = deepcopy(g:simplewhichkey_prefixes)

def g:SimpleWhichKeyTestOperator(type: string)
  g:simplewhichkey_operator_capture = {
    type: type,
    first: line("'["),
    last: line("']"),
    register: v:register,
  }
enddef

g:simplewhichkey_operator_expr_calls = 0
def g:SimpleWhichKeyOperatorExpr(): string
  g:simplewhichkey_operator_expr_calls += 1
  return 'iw'
enddef

g:hit = ''
nnoremap <silent> <leader>ff <Cmd>let g:hit = 'files'<CR>
nnoremap <silent> <leader>fr <Cmd>let g:hit = 'recent'<CR>
xnoremap <silent> <leader>fg <Cmd>let g:hit = 'grep'<CR>
nnoremap <silent> <leader>w= <C-w>=
nnoremap <silent> <leader>i A
# This mapping is deliberately recursive and crosses Normal -> Visual before
# emitting a hooked g. Replay suspension must keep that RHS native.
nmap <silent> <leader>v vg~
nnoremap <silent> <F8> <Cmd>SimpleWhichKeyOperator<CR>
# Reached from Normal mode there is no selection behind the visual command;
# reached with <Cmd> from a Visual mapping there is one, and that difference is
# what decides between browsing and replaying.
nnoremap <silent> <F7> <Cmd>SimpleWhichKeyVisual g<CR>
xnoremap <silent> <F7> <Cmd>SimpleWhichKeyVisual g<CR>
for key in split('ABCDEFGHIJKLMNOPQRS', '\zs')
  execute $"nnoremap <silent> <leader>{key} <Cmd>let g:hit = 'level-{key}'<CR>"
endfor
nnoremap <silent> <leader>Tq <Cmd>let g:hit = 'nested-page-group'<CR>
for key in split('abcdefghijklmnopqrst', '\zs')
  execute $"nnoremap <silent> Z{key} <Cmd>let g:hit = 'overflow-{key}'<CR>"
endfor
nnoremap <silent> Z<PageDown> <Cmd>let g:hit = 'explicit-page-mapping'<CR>

def PanelVisible(): bool
  return !empty(popup_list())
enddef

def PanelTitle(): string
  var ids = popup_list()
  if empty(ids)
    return ''
  endif
  return trim(get(popup_getoptions(ids[-1]), 'title', ''))
enddef

def PanelText(): string
  var ids = popup_list()
  if empty(ids)
    return ''
  endif
  return join(getbufline(winbufnr(ids[-1]), 1, '$'), "\n")
enddef

def Hooked(): bool
  return maparg('<Space>', 'n') =~# 'simplewhichkey#Start'
enddef

def OperatorHooked(): bool
  return maparg('g', 'o') =~# 'simplewhichkey#OperatorHook'
enddef

def TextObjectHooked(): bool
  return maparg('i', 'o') =~# 'simplewhichkey#OperatorHook'
    && maparg('a', 'x') =~# 'simplewhichkey#Start'
enddef

def InsertHooked(): bool
  return maparg('<C-r>', 'i') =~# 'simplewhichkey#InsertHook'
    && maparg('<C-x>', 'i') =~# 'simplewhichkey#InsertHook'
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

def PutLines(lines: list<string>)
  deletebufline(bufnr(), 1, '$')
  setline(1, lines)
enddef

def TenLines(): list<string>
  return mapnew(range(1, 10), (_, nr) => 'line-' .. nr)
enddef

setline(1, ['one', 'two', 'three', 'four'])
setreg('a', 'register-a-content')

var steps = [
  # The explicit operator command defaults to the useful g motion prefix.
  () => Type("\<F8>"),
  () => {
    assert_true(PanelVisible(), 'operator command opens its default panel')
    assert_equal('g', PanelTitle())
    Type("\<Esc>")
  },
  () => assert_false(PanelVisible(), 'operator command panel closes'),

  # No operator is pending behind :SimpleWhichKeyOperator, so choosing an entry
  # must not replay it into Normal mode -- there the same keys are a different
  # command, and here the Normal gp would fire instead of the omap listed.
  () => {
    nnoremap <silent> gp <Cmd>let g:hit = 'normal-gp'<CR>
    onoremap gp iw
    g:hit = ''
    PutLines(['keep browse keep'])
    cursor(1, 6)
    Type("\<F8>")
  },
  () => {
    assert_true(PanelVisible(), 'operator command panel before a selection')
    # 'iw' is a text object Vim already has a name for, so the derived
    # description says what it does rather than repeating its keys.
    assert_match('inner-word', PanelText(),
      'the operator-only gp omap is listed')
    Type('p')
  },
  () => {
    assert_true(WaitFor(() => !PanelVisible()),
      'operator command panel closed after choosing')
    assert_equal('', g:hit,
      'browsing operator hints must not run the Normal-mode command')
    assert_equal('keep browse keep', getline(1),
      'browsing operator hints changes no text')
    assert_match('^n', mode(1))
    nunmap gp
    ounmap gp
  },

  # :SimpleWhichKeyVisual has the same problem: typing ':' leaves Visual mode,
  # so replaying the xmap the panel advertised would run the unrelated
  # Normal-mode command of the same name.
  () => {
    nnoremap <silent> gp <Cmd>let g:hit = 'normal-gp'<CR>
    xnoremap <silent> gp <Cmd>let g:hit = 'visual-gp'<CR>
    g:hit = ''
    PutLines(['keep browse keep'])
    cursor(1, 6)
    Type("\<F7>")
  },
  () => {
    assert_true(PanelVisible(), 'visual command panel before a selection')
    assert_match('visual-gp', PanelText(), 'the x-mode gp mapping is listed')
    Type('p')
  },
  () => {
    assert_true(WaitFor(() => !PanelVisible()),
      'visual command panel closed after choosing')
    assert_equal('', g:hit,
      'browsing visual hints must not run the Normal-mode command')
    assert_match('^n', mode(1))
  },
  # With a live selection behind it -- <Cmd> from a Visual mapping -- the same
  # command still replays into Visual mode, where the panel's entry is real.
  () => {
    g:hit = ''
    cursor(1, 1)
    Type("vll\<F7>")
  },
  () => {
    assert_true(PanelVisible(), 'visual command panel over a live selection')
    Type('p')
  },
  () => {
    assert_true(WaitFor(() => !PanelVisible() && g:hit !=# ''),
      'a live selection must still run the visual mapping')
    assert_equal('visual-gp', g:hit,
      'the visual replay ran the Normal-mode command instead')
    assert_equal('keep browse keep', getline(1),
      'the visual replay changes no text')
    Type("\<Esc>")
  },
  () => {
    assert_true(WaitFor(() => mode(1) =~# '^n'))
    g:hit = ''
    nunmap gp
    xunmap gp
  },

  # --- <C-w> opens the built-in window panel and v splits ------------------
  () => Type("\<C-w>"),
  () => {
    assert_true(PanelVisible(), 'panel after <C-w>')
    assert_equal('<C-W>', PanelTitle())
    assert_match('split-vertical', PanelText())
  },
  () => Type('v'),
  () => {
    assert_false(PanelVisible(), 'panel closed after choosing')
    assert_equal(2, winnr('$'), 'vertical split happened')
    assert_true(Hooked(), 'hooks restored after replay')
    only
  },

  # --- operator-pending selection keeps Vim's original state live ---------
  () => {
    assert_true(WaitFor(() => OperatorHooked()),
      'operator hooks were not installed')
    PutLines(['first line', 'second line', 'third line', 'fourth line'])
    cursor(3, 1)
    Type('dg')
  },
  () => {
    assert_true(PanelVisible(), 'g panel opens after a pending delete')
    assert_equal('g', PanelTitle())
    assert_match('first-line', PanelText())
    Type('g')
  },
  () => {
    assert_true(WaitFor(() => OperatorHooked()),
      'operator hook restored after dgg replay')
    assert_equal(['fourth line'], getline(1, '$'),
      'dgg completed through the panel')
    assert_match('^n', mode(1), 'dgg returned to Normal mode')
  },

  # A motion count and multiplied operator/motion counts go through the hooked
  # g itself rather than merely passing beside an installed hook.
  () => {
    assert_true(WaitFor(() => OperatorHooked()))
    PutLines(TenLines())
    cursor(8, 1)
    Type('d2g')
  },
  () => {
    assert_true(PanelVisible(), 'd2g reaches the operator panel')
    Type('g')
  },
  () => {
    assert_true(WaitFor(() => OperatorHooked()))
    assert_equal(['line-1', 'line-9', 'line-10'], getline(1, '$'),
      'd2gg keeps its motion count')
    PutLines(TenLines())
    cursor(8, 1)
    Type('2d3g')
  },
  () => {
    assert_true(PanelVisible(), '2d3g reaches the operator panel')
    Type('g')
  },
  () => {
    assert_true(WaitFor(() => OperatorHooked()))
    assert_equal(['line-1', 'line-2', 'line-3', 'line-4', 'line-5',
      'line-9', 'line-10'], getline(1, '$'),
      '2d3gg preserves Vim''s multiplied count')
  },

  # Leave the normal register prefix unhooked temporarily so the named
  # register reaches the operator hook itself, not a separate outer panel.
  () => {
    var without_register = deepcopy(g:simplewhichkey_prefixes)
    without_register.n = filter(copy(without_register.n),
      (_, prefix) => prefix !=# '"')
    g:simplewhichkey_prefixes = without_register
    simplewhichkey#Setup()
  },
  () => {
    PutLines(TenLines())
    cursor(8, 1)
    setreg('a', '')
    Type('"adg')
  },
  () => {
    assert_true(PanelVisible(), 'named-register dgg reaches the g panel')
    Type('g')
  },
  () => {
    assert_true(WaitFor(() => OperatorHooked()))
    assert_equal(['line-9', 'line-10'], getline(1, '$'),
      'named-register dgg performs the deletion')
    assert_equal(TenLines()[0 : 7], getreg('a', 1, 1),
      'the captured register receives the operator text')
    PutLines(TenLines())
    cursor(8, 1)
    setreg('"', 'blackhole sentinel')
    g:simplewhichkey_before_blackhole = getreginfo('"')
    Type('"_dg')
  },
  () => {
    assert_true(PanelVisible(), 'black-hole dgg reaches the g panel')
    Type('g')
  },
  () => {
    assert_true(WaitFor(() => OperatorHooked()))
    assert_equal(['line-9', 'line-10'], getline(1, '$'),
      'black-hole dgg performs the deletion')
    assert_equal(g:simplewhichkey_before_blackhole, getreginfo('"'),
      'black-hole replay leaves the unnamed register untouched')
    g:simplewhichkey_prefixes = deepcopy(original_prefixes)
    simplewhichkey#Setup()
  },

  # Another operator proves replay is not delete-specific; the unnamed
  # register receives ygg while the buffer stays untouched.
  () => {
    PutLines(TenLines())
    cursor(8, 1)
    Type('yg')
  },
  () => {
    assert_true(PanelVisible(), 'yank operator reaches the g panel')
    Type('g')
  },
  () => {
    assert_true(WaitFor(() => OperatorHooked()))
    assert_equal(TenLines(), getline(1, '$'), 'ygg does not edit the buffer')
    assert_equal(TenLines()[0 : 7], getreg('"', 1, 1),
      'ygg updates the unnamed register')
  },

  # A change selected through the panel is still a real repeatable Vim command.
  () => {
    PutLines(mapnew(range(1, 6), (_, nr) => 'line-' .. nr))
    cursor(3, 1)
    Type('dg')
  },
  () => {
    assert_true(PanelVisible(), 'repeat fixture reaches the g panel')
    Type('g')
  },
  () => {
    assert_equal(['line-4', 'line-5', 'line-6'], getline(1, '$'))
    Type('.')
  },
  () => assert_equal(['line-5', 'line-6'], getline(1, '$'),
    'dot repeats panel-selected dgg with native semantics'),

  # A multi-key operator selected from the Normal g panel must leave the
  # operator-mode hooks alive for its following motion. This is the complete
  # real g -> @ -> operator g -> g path, not a mapping that bypasses Normal g.
  () => {
    PutLines(TenLines())
    cursor(8, 1)
    &operatorfunc = 'g:SimpleWhichKeyTestOperator'
    g:simplewhichkey_operator_capture = {}
    Type('g')
  },
  () => {
    assert_true(PanelVisible(), 'normal g panel opens before g@')
    assert_match('operatorfunc', PanelText())
    Type('@')
  },
  () => {
    var ready = WaitFor(() => state('o') !=# '' && OperatorHooked())
    assert_true(ready, 'g@ replay keeps operator g hook available: state='
      .. state('mo') .. ' mode=' .. mode(1)
      .. ' nmap=' .. string(maparg('g', 'n'))
      .. ' omap=' .. string(maparg('g', 'o')))
    Type('g')
  },
  () => {
    assert_true(PanelVisible(), 'g@ motion reaches the operator g panel')
    Type('g')
  },
  () => {
    var captured = WaitFor(() => !empty(g:simplewhichkey_operator_capture))
    assert_true(captured, 'real g@g callback missing: state=' .. state('mo')
      .. ' mode=' .. mode(1)
      .. ' nmap=' .. string(maparg('g', 'n'))
      .. ' omap=' .. string(maparg('g', 'o')))
    if captured
      assert_equal('line', g:simplewhichkey_operator_capture.type)
      assert_equal([1, 8], [g:simplewhichkey_operator_capture.first,
        g:simplewhichkey_operator_capture.last])
      assert_equal('"', g:simplewhichkey_operator_capture.register)
    endif
  },

  # Change through the panel still enters Insert mode, and hook restoration
  # waits for InsertLeave instead of stealing the inserted characters.
  () => {
    assert_true(WaitFor(() => OperatorHooked()))
    PutLines(['first line', 'second line', 'third line', 'fourth line'])
    cursor(3, 1)
    Type('cg')
  },
  () => {
    assert_true(PanelVisible(), 'change operator reaches the g panel')
    Type('g')
  },
  () => {
    assert_equal('i', mode(), 'cgg enters Insert mode')
    Type('changed')
  },
  () => {
    assert_equal('i', mode(), 'inserted cgg replacement stays in Insert mode')
    Type("\<Esc>")
  },
  () => {
    assert_true(WaitFor(() => mode(1) =~# '^n' && OperatorHooked()),
      'operator hook restores after InsertLeave: mode=' .. mode(1)
      .. ' omap=' .. string(maparg('g', 'o')))
    assert_equal(['changed', 'fourth line'], getline(1, '$'),
      'cgg keeps inserted text and untouched trailing lines')
  },

  # Operator bracket panels contain motions only. d]} is real; Normal mode's
  # paste/list commands must not be advertised after an operator.
  () => {
    PutLines(['{', 'one', '}', 'middle', '{', 'two', '}', 'tail'])
    cursor(2, 1)
    Type('d]')
  },
  () => {
    assert_true(PanelVisible(), '] panel opens after a pending delete')
    assert_match('next-unmatched-brace', PanelText())
    assert_notmatch('paste-after\|list-defines', PanelText())
    Type('}')
  },
  () => assert_equal(['{', '}', 'middle', '{', 'two', '}', 'tail'],
    getline(1, '$'), 'd]} replays an operator-valid bracket motion'),

  # Text objects are the half of the grammar Vim cannot show. i/a are hooked in
  # Operator-pending mode through the expr hook and in Visual mode through the
  # <Cmd> hook, so both a pending operator and a live selection survive.
  () => {
    assert_true(WaitFor(() => TextObjectHooked()),
      'text object hooks were not installed')
    PutLines(['keep delete keep'])
    cursor(1, 6)
    Type('di')
  },
  () => {
    assert_true(PanelVisible(), 'i panel opens after a pending delete')
    assert_equal('i', PanelTitle())
    assert_match('inner-word', PanelText())
    Type('w')
  },
  () => {
    assert_true(WaitFor(() => TextObjectHooked()))
    assert_equal('keep  keep', getline(1), 'diw completed through the panel')
    PutLines(['x((one))y'])
    cursor(1, 4)
    Type('d2i')
  },
  () => {
    assert_true(PanelVisible(), 'd2i reaches the text object panel')
    Type('(')
  },
  () => {
    assert_true(WaitFor(() => TextObjectHooked()))
    assert_equal('x()y', getline(1),
      'd2i( keeps the count Vim had already taken')
    PutLines(['alpha beta gamma'])
    cursor(1, 7)
    Type('va')
  },
  () => {
    assert_true(PanelVisible(), 'a panel opens in Visual mode')
    assert_equal('a', PanelTitle())
    assert_match('a-word-with-white-space', PanelText())
    Type('w')
  },
  () => {
    assert_true(WaitFor(() => col('.') == 11),
      'vaw extended the selection: col=' .. col('.')
      .. ' mode=' .. mode(1) .. ' state=' .. state('mo'))
    Type('d')
  },
  () => {
    assert_equal('alpha gamma', getline(1),
      'a Visual text object chosen from the panel selected the real object')
    assert_true(WaitFor(() => Hooked() && TextObjectHooked()),
      'hooks restored after a Visual text object replay')
    PutLines(['one', 'two', 'three', 'four'])
    cursor(1, 1)
  },

  # Esc is consumed by getcharstr() and returned from the expr hook, cancelling
  # the still-live operator without changing text.
  () => {
    PutLines(['cancel remains'])
    cursor(1, 1)
    Type('dg')
  },
  () => {
    assert_true(PanelVisible(), 'operator panel visible before cancellation')
    Type("\<Esc>")
  },
  () => {
    assert_true(WaitFor(() => mode(1) =~# '^n' && OperatorHooked()),
      'Esc did not cancel the operator cleanly')
    assert_equal('cancel remains', getline(1),
      'operator cancellation changes no text')
  },

  # A buffer-local omap wins over the global hook in that buffer. Removing it
  # exposes the still-installed hook again.
  () => {
    onoremap <buffer> g iw
    assert_equal('iw', maparg('g', 'o'), 'buffer-local omap owns g')
    PutLines(['keep delete keep'])
    cursor(1, 7)
    Type('dg')
  },
  () => {
    assert_false(PanelVisible(), 'buffer-local omap bypasses the panel')
    assert_equal('keep  keep', getline(1), 'buffer-local omap executes normally')
    ounmap <buffer> g
    assert_true(WaitFor(() => OperatorHooked()),
      'global operator hook remains beneath the buffer-local omap')
    PutLines(['one', 'two', 'three', 'four'])
    cursor(1, 1)
    setreg('a', 'register-a-content')
  },

  # Slow selection must still execute mappings discovered below the hooked
  # prefix. The recursive expr hook removes itself and returns <Ignore> before
  # the selected bytes, preserving noremap, <Plug> and expr semantics.
  () => {
    g:simplewhichkey_saved_timeoutlen = &timeoutlen
    &timeoutlen = 100
    onoremap gx iw
    PutLines(['keep delete keep'])
    cursor(1, 7)
    Type('dg')
  },
  () => {
    assert_true(PanelVisible(), 'slow global gx omap is shown')
    assert_match('inner-word', PanelText())
    Type('x')
  },
  () => {
    assert_equal('keep  keep', getline(1),
      'slow selected nonrecursive omap executes')
    assert_true(WaitFor(() => OperatorHooked()))
    onoremap <Plug>(simplewhichkey-test-around) aw
    omap gz <Plug>(simplewhichkey-test-around)
    PutLines(['keep delete keep'])
    cursor(1, 7)
    Type('dg')
  },
  () => {
    assert_true(PanelVisible(), 'recursive <Plug> omap is shown')
    Type('z')
  },
  () => {
    assert_equal('keep keep', getline(1),
      'slow selected recursive <Plug> omap executes')
    assert_true(WaitFor(() => OperatorHooked()))
    onoremap <expr> gv g:SimpleWhichKeyOperatorExpr()
    g:simplewhichkey_operator_expr_calls = 0
    PutLines(['keep delete keep'])
    cursor(1, 7)
    Type('dg')
  },
  () => {
    assert_true(PanelVisible(), 'operator expr mapping is shown')
    Type('v')
  },
  () => {
    assert_equal('keep  keep', getline(1),
      'slow selected operator expr mapping executes')
    assert_equal(1, g:simplewhichkey_operator_expr_calls)
    ounmap gx
    ounmap gz
    ounmap gv
    ounmap <Plug>(simplewhichkey-test-around)
    &timeoutlen = g:simplewhichkey_saved_timeoutlen
    assert_true(WaitFor(() => OperatorHooked()))
    PutLines(['one', 'two', 'three', 'four'])
    cursor(1, 1)
  },

  # --- leader panel, descending, <BS> and <Esc> ----------------------------
  () => Type(' '),
  () => {
    assert_true(PanelVisible(), 'panel after leader')
    assert_equal('<Space>', PanelTitle())
  },
  () => Type('f'),
  () => {
    assert_equal('<Space> f', PanelTitle(), 'descended into the group')
    assert_match('files', PanelText())
  },
  () => Type("\<BS>"),
  () => assert_equal('<Space>', PanelTitle(), '<BS> goes back one level'),
  () => Type("\<Esc>"),
  () => {
    assert_false(PanelVisible(), '<Esc> closes the panel')
    assert_equal('', g:hit, '<Esc> runs nothing')
    assert_true(Hooked(), 'hooks kept after abort')
  },

  # A recursive mapping may cross modes while its RHS is replayed. Normal
  # replay keeps only operator hooks live; the Visual g here must not recurse
  # into another panel.
  () => {
    PutLines(['lower'])
    cursor(1, 1)
    Type(' ')
  },
  () => {
    assert_true(PanelVisible(), 'leader panel before cross-mode mapping')
    Type('v')
  },
  () => {
    assert_false(PanelVisible(), 'recursive Visual g was not re-hooked')
    assert_equal('Lower', getline(1), 'cross-mode mapping retained native RHS')
    assert_match('^n', mode(1))
    assert_true(WaitFor(() => Hooked() && OperatorHooked()),
      'all hooks restored after cross-mode replay')
    PutLines(['one', 'two', 'three', 'four'])
    cursor(1, 1)
  },

  # --- overflow pages work in a terminal with no mouse --------------------
  () => {
    g:simplewhichkey_max_height = 1
    Type('z')
  },
  () => {
    assert_true(PanelVisible(), 'overflow panel after z')
    assert_match('\[1/[2-9][0-9]* PgUp/PgDn\]', PanelTitle())
    Type("\<PageDown>")
  },
  () => {
    assert_match('\[2/[2-9][0-9]* PgUp/PgDn\]', PanelTitle(),
      'PageDown did not redraw the next page')
    Type("\<PageUp>")
  },
  () => {
    assert_match('\[1/[2-9][0-9]* PgUp/PgDn\]', PanelTitle(),
      'PageUp did not redraw the previous page')
    Type("\<Esc>")
  },
  () => {
    assert_false(PanelVisible(), 'overflow panel closed after Esc')
    g:simplewhichkey_max_height = 0
  },

  # A parent level remembers its page while visiting a nested group.
  () => {
    g:simplewhichkey_max_height = 1
    Type(' ')
  },
  () => {
    assert_match('\[1/[2-9][0-9]* PgUp/PgDn\]', PanelTitle())
    Type("\<PageDown>")
  },
  () => {
    assert_match('\[2/[2-9][0-9]* PgUp/PgDn\]', PanelTitle())
    Type('T')
  },
  () => {
    assert_equal('<Space> T', PanelTitle(), 'entered the nested group')
    Type("\<BS>")
  },
  () => {
    assert_match('<Space> \[2/[2-9][0-9]* PgUp/PgDn\]', PanelTitle(),
      '<BS> restored the parent overflow page')
    Type("\<Esc>")
  },
  () => {
    assert_false(PanelVisible(), 'page-memory panel closed after Esc')
    g:simplewhichkey_max_height = 0
  },

  # An explicit Page key mapping at this level wins over the fallback control.
  () => {
    g:simplewhichkey_max_height = 1
    Type('Z')
  },
  () => {
    assert_true(PanelVisible(), 'custom overflow panel after Z')
    assert_match('PgUp/PgDn', PanelTitle())
    Type("\<PageDown>")
  },
  () => {
    assert_false(PanelVisible(), 'explicit PageDown mapping closes the panel')
    assert_equal('explicit-page-mapping', g:hit,
      'paging fallback hid an explicit PageDown mapping')
    g:hit = ''
    g:simplewhichkey_max_height = 0
  },

  # --- typing through the prefix never shows the panel ---------------------
  () => Type(' ff'),
  () => {
    assert_false(PanelVisible(), 'no panel when the next key is already there')
    assert_equal('files', g:hit, 'mapping ran')
    g:hit = ''
  },

  # --- a count survives the detour ----------------------------------------
  () => {
    cursor(1, 1)
    Type('3')
  },
  () => Type('g'),
  () => {
    assert_true(PanelVisible(), 'panel after a counted g')
    Type('g')
  },
  () => assert_equal(3, line('.'), '3gg used the count'),

  # --- registers and marks are listed from the live state ------------------
  () => {
    assert_true(WaitFor(() => Hooked()),
      'hooks did not restore after the counted replay')
    Type('"')
  },
  () => {
    assert_true(PanelVisible(), 'panel after "')
    assert_match('register-a-content', PanelText(), 'register contents shown')
    Type("\<Esc>")
  },
  () => {
    cursor(2, 1)
    execute 'normal! mq'
    cursor(4, 1)
    Type("'")
  },
  () => {
    assert_true(PanelVisible(), 'panel after mark prefix')
    assert_match('q', PanelText(), 'mark q listed')
    Type('q')
  },
  () => assert_equal(2, line('.'), 'jumped to mark q'),

  # --- visual mode -------------------------------------------------------
  () => {
    cursor(1, 1)
    Type('vj')
  },
  () => Type(' '),
  () => {
    assert_true(PanelVisible(), 'panel in visual mode')
    Type('f')
  },
  () => Type('g'),
  () => {
    assert_equal('grep', g:hit, 'visual mapping ran')
    assert_true(Hooked(), 'hooks restored after a visual replay')
    execute "normal! \<Esc>"
  },

  # --- a mapping that ends in Insert mode really ends there ----------------
  () => {
    cursor(1, 1)
    Type(' ')
  },
  () => Type('i'),
  () => {
    assert_equal('i', mode(), 'the replayed mapping entered Insert mode')
    Type("x\<Esc>")
  },
  () => {
    assert_equal('onex', getline(1), 'and Insert mode kept the typed text')
    assert_true(Hooked(), 'hooks restored after leaving Insert mode')
  },

  # --- Insert mode: CTRL-R lists the registers that hold something ---------
  # The expr hook returns the chosen keys instead of feeding them, so the text
  # typed so far and the cursor are Vim's own throughout.
  () => {
    assert_true(WaitFor(() => InsertHooked()),
      'insert hooks were not installed')
    PutLines(['prefix-'])
    setreg('a', 'register-a-content')
    cursor(1, 1)
    Type("A\<C-r>")
  },
  () => {
    assert_true(PanelVisible(), 'panel after CTRL-R in Insert mode')
    assert_equal('<C-R>', PanelTitle())
    assert_match('register-a-content', PanelText(), 'register contents shown')
    Type('a')
  },
  () => {
    assert_true(WaitFor(() => getline(1) ==# 'prefix-register-a-content'),
      'CTRL-R a inserted the register through the panel: ' .. getline(1))
    assert_equal('i', mode(), 'the insert hook stayed in Insert mode')
    Type("\<Esc>")
  },
  () => {
    assert_true(WaitFor(() => mode(1) =~# '^n' && InsertHooked()),
      'insert hooks restored after leaving Insert mode')
  },

  # CTRL-X picks a completion kind.  Esc must dismiss the panel without also
  # leaving Insert mode -- returning <Esc> from the hook would throw away the
  # insert the user is in the middle of.
  () => {
    PutLines(['keep'])
    cursor(1, 1)
    Type("A\<C-x>")
  },
  () => {
    assert_true(PanelVisible(), 'panel after CTRL-X in Insert mode')
    assert_equal('<C-X>', PanelTitle())
    assert_match('omni-completion', PanelText())
    Type("\<Esc>")
  },
  () => {
    assert_false(PanelVisible(), 'Esc closed the completion panel')
    assert_equal('i', mode(),
      'Esc in an Insert-mode panel must not leave Insert mode')
    assert_equal('keep', getline(1), 'the dismissed prefix inserted nothing')
    Type("\<Esc>")
  },
  () => assert_true(WaitFor(() => mode(1) =~# '^n' && InsertHooked()),
    'insert hooks restored after dismissing the panel'),

  # The same prefix on the command line, where the half-written line has to
  # survive the panel.
  () => {
    g:hit = ''
    setreg('a', 'register-a-content')
    Type(":let g:hit = '\<C-r>")
  },
  () => {
    assert_true(PanelVisible(), 'panel after CTRL-R on the command line')
    assert_match('register-a-content', PanelText())
    Type('a')
  },
  () => Type("'\<CR>"),
  () => {
    assert_true(WaitFor(() => g:hit ==# 'register-a-content'),
      'the command line kept what was typed before the panel: ' .. g:hit)
    g:hit = ''
  },

  # --- disabled means out of the way --------------------------------------
  () => {
    simplewhichkey#Disable()
    assert_equal('', maparg('<C-w>', 'n'), 'hooks removed when disabled')
    simplewhichkey#Enable()
    assert_true(Hooked(), 'hooks back when enabled')
  },
]

var index = 0
var retry_index = -1
var retry_count = 0
# A pty swallows anything written to stderr, so the verdict goes to a file the
# runner can read: $SIMPLEWHICHKEY_TEST_OUT, or tests/.keys-result by default.
const REPORT = empty($SIMPLEWHICHKEY_TEST_OUT)
  ? ROOT .. '/tests/.keys-result'
  : $SIMPLEWHICHKEY_TEST_OUT

def Finish()
  if !empty(v:errors)
    writefile(['FAIL'] + v:errors, REPORT)
    cquit 1
  endif
  writefile(['PASS'], REPORT)
  qall!
enddef

def Tick(_: number)
  # Timers may fire recursively while PollKey() is sleeping inside a mapping.
  # A hidden panel means the previous keystroke has not reached the interaction
  # point yet; do not consume the next test step. Return immediately so the
  # older mapping stack can finish, then retry on the following tick.
  if !PanelVisible() && !empty(state('m'))
    if retry_index == index
      retry_count += 1
    else
      retry_index = index
      retry_count = 1
    endif
    if retry_count >= 10
      assert_report('PTY step did not settle: index=' .. index
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
  # One-shot rearming prevents an overdue repeating timer from nesting inside
  # the PollKey() started by the keystroke this callback just queued.
  timer_start(300, Tick)
enddef

timer_start(300, Tick)
