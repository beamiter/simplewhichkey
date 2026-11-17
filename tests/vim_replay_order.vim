vim9script
# Keep a choice's already queued arguments behind its replayed <Plug> mapping.
set nocompatible nomore
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplewhichkey_prefixes = {n: ['z']}
g:simplewhichkey_delay = 10
g:replay_result = ''
def g:ReadReplayArguments()
  var first = getcharstr()
  g:replay_result = first .. getcharstr()
enddef
nmap zx <Plug>(test-replay-reader)
nnoremap <Plug>(test-replay-reader) <ScriptCmd>g:ReadReplayArguments()<CR>
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplewhichkey.vim')
var phase = 0
var ticks = 0

def Finish()
  var out = empty($SIMPLEWHICHKEY_TEST_OUT)
    ? '/tmp/simplewhichkey-replay-result' : $SIMPLEWHICHKEY_TEST_OUT
  writefile(empty(v:errors) ? ['PASS replay order'] : v:errors, out)
  if !empty(v:errors)
    cquit 1
  endif
  qa!
enddef

def Tick(_: number)
  ticks += 1
  if ticks > 100
    assert_report('queued arguments were not read after replay: ' .. g:replay_result)
    Finish()
  endif
  if phase == 0
    phase = 1
    feedkeys('z', 'mt')
  elseif phase == 1 && !empty(popup_list())
    phase = 2
    feedkeys('xab', 'mt')
  elseif phase == 2 && g:replay_result ==# 'ab'
    assert_equal([], popup_list())
    Finish()
  endif
enddef

timer_start(20, Tick, {repeat: -1})
