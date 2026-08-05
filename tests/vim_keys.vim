vim9script

# End to end checks: real keystrokes, real popup, real replay.  These need a
# terminal, so they are driven through a pty:
#
#   script -qec "vim -N -u NONE -S tests/vim_keys.vim" /dev/null
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

g:hit = ''
nnoremap <silent> <leader>ff <Cmd>let g:hit = 'files'<CR>
nnoremap <silent> <leader>fr <Cmd>let g:hit = 'recent'<CR>
xnoremap <silent> <leader>fg <Cmd>let g:hit = 'grep'<CR>
nnoremap <silent> <leader>w= <C-w>=
nnoremap <silent> <leader>i A

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

def Type(keys: string)
  feedkeys(keys, 't')
enddef

setline(1, ['one', 'two', 'three', 'four'])
setreg('a', 'register-a-content')

var steps = [
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
  () => Type('"'),
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

  # --- disabled means out of the way --------------------------------------
  () => {
    simplewhichkey#Disable()
    assert_equal('', maparg('<C-w>', 'n'), 'hooks removed when disabled')
    simplewhichkey#Enable()
    assert_true(Hooked(), 'hooks back when enabled')
  },
]

var index = 0
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
  endtry
enddef

timer_start(200, Tick, {repeat: -1})
