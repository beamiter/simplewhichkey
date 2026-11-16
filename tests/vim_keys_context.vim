vim9script

# A timer runs while getcharstr() waits. The displayed buffer-local choice
# must not turn into a different buffer's mapping when replay eventually runs.
set nocompatible nomore hidden
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplewhichkey_delay = 50
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplewhichkey.vim')
g:hit = ''
var cases = ['buffer', 'window', 'edit', 'delay', 'unchanged']
var index = 0

def Finish()
  var out = empty($SIMPLEWHICHKEY_TEST_OUT)
    ? '/tmp/simplewhichkey-context-result' : $SIMPLEWHICHKEY_TEST_OUT
  writefile(empty(v:errors) ? ['PASS context'] : v:errors, out)
  if !empty(v:errors)
    cquit 1
  endif
  qa!
enddef

def RunCase()
  if index >= len(cases)
    Finish()
    return
  endif
  var kind = cases[index]
  index += 1
  silent! only!
  enew!
  setline(1, 'original')
  nnoremap <buffer> zx <Cmd>let g:hit = 'original'<CR>
  var original = bufnr()
  new
  setline(1, 'replacement')
  nnoremap <buffer> zx <Cmd>let g:hit = 'wrong-buffer'<CR>
  var replacement = bufnr()
  execute 'buffer ' .. original
  var origin_window = win_getid()
  g:hit = ''
  g:simplewhichkey_delay = kind ==# 'delay' ? 500 : 50
  timer_start(50, (_) => feedkeys('z', 'mt'))
  timer_start(200, (_) => {
    if kind ==# 'buffer' || kind ==# 'delay'
      execute 'buffer ' .. replacement
    elseif kind ==# 'window'
      wincmd w
      assert_notequal(origin_window, win_getid())
      assert_equal(original, bufnr())
    elseif kind ==# 'edit'
      setline(1, 'changed')
    endif
    feedkeys('x', 'nt')
  })
  timer_start(700, (_) => {
    assert_equal(kind ==# 'unchanged' ? 'original' : '', g:hit, kind)
    assert_equal([], popup_list(), kind .. ': stale popup')
    RunCase()
  })
enddef

timer_start(100, (_) => RunCase())
timer_start(15000, (_) => {
  assert_report('context test timed out')
  Finish()
})
