vim9script

if exists('g:loaded_simplewhichkey')
  finish
endif
g:loaded_simplewhichkey = 1

if v:version < 901
  echohl WarningMsg
  echomsg '[SimpleWhichKey] Vim 9.1 or newer is required.'
  echohl None
  finish
endif

if !has('popupwin') || !has('textprop') || !has('timers')
  echohl WarningMsg
  echomsg '[SimpleWhichKey] Vim must be compiled with +popupwin, +textprop and +timers.'
  echohl None
  finish
endif

def Flag(value: any, fallback: number): number
  if type(value) == v:t_bool
    return value ? 1 : 0
  endif
  if type(value) == v:t_number
    return value == 0 ? 0 : 1
  endif
  return fallback
enddef

def ClampNumber(value: any, fallback: number, minimum: number, maximum: number): number
  if type(value) != v:t_number
    return fallback
  endif
  return min([maximum, max([minimum, value])])
enddef

def Choice(value: any, fallback: string, allowed: list<string>): string
  if type(value) == v:t_string && index(allowed, value) >= 0
    return value
  endif
  return fallback
enddef

def Text(value: any, fallback: string): string
  return type(value) == v:t_string ? value : fallback
enddef

# The delay is one number, or a table of them keyed by prefix notation with an
# optional "mode:" qualifier and a "default" entry.  Every value is clamped the
# same way a bare number is, and an unusable entry is dropped rather than
# allowed to reach the panel loop.
def Delay(value: any, fallback: number): any
  if type(value) != v:t_dict
    return ClampNumber(value, fallback, 0, 5000)
  endif
  var out: dict<number> = {}
  for [key, entry] in items(value)
    if type(entry) == v:t_number
      out[key] = ClampNumber(entry, fallback, 0, 5000)
    endif
  endfor
  if empty(out)
    return fallback
  endif
  if !has_key(out, 'default')
    out['default'] = fallback
  endif
  return out
enddef

def Prefixes(value: any, fallback: dict<list<string>>): dict<any>
  if type(value) != v:t_dict
    return fallback
  endif
  var out: dict<any> = {}
  for [mode, list] in items(value)
    if type(list) == v:t_list
      out[mode] = list
    endif
  endfor
  return empty(out) ? fallback : out
enddef

# Every prefix Vim itself treats as the start of a longer command, plus the two
# leaders.  Marks and registers are listed from the live editor state, which is
# why they are hooked as well.
const DEFAULT_PREFIXES = {
  n: ['<leader>', '<localleader>', 'g', 'z', 'Z', '<C-w>', '[', ']', '"', "'", '`'],
  x: ['<leader>', '<localleader>', 'g', 'z', '[', ']', '"', "'", '`'],
  # Motions beginning with g/[ /] are easy to forget after an operator. The
  # expr hook keeps Vim's original operator/count/register state live; exact
  # user omaps still win their prefix slots.
  o: ['g', '[', ']'],
}

g:simplewhichkey_enable = Flag(get(g:, 'simplewhichkey_enable', 1), 1)
g:simplewhichkey_prefixes = Prefixes(get(g:, 'simplewhichkey_prefixes', {}), DEFAULT_PREFIXES)
g:simplewhichkey_delay = Delay(get(g:, 'simplewhichkey_delay', 200), 200)
g:simplewhichkey_max_height = ClampNumber(get(g:, 'simplewhichkey_max_height', 0), 0, 0, 100)
g:simplewhichkey_max_desc_width = ClampNumber(get(g:, 'simplewhichkey_max_desc_width', 30), 30, 8, 120)
g:simplewhichkey_position = Choice(
  get(g:, 'simplewhichkey_position', 'bottom'), 'bottom', ['bottom', 'top', 'center'])
g:simplewhichkey_sort = Choice(get(g:, 'simplewhichkey_sort', 'key'), 'key', ['key', 'group'])
g:simplewhichkey_separator = Text(get(g:, 'simplewhichkey_separator', ' → '), ' → ')
g:simplewhichkey_border = Flag(get(g:, 'simplewhichkey_border', 1), 1)
g:simplewhichkey_show_builtins = Flag(get(g:, 'simplewhichkey_show_builtins', 1), 1)
g:simplewhichkey_hide_aliases = Flag(get(g:, 'simplewhichkey_hide_aliases', 1), 1)
var configured_ignore = get(g:, 'simplewhichkey_ignore', [])
g:simplewhichkey_ignore = type(configured_ignore) == v:t_list ? configured_ignore : []

command! -nargs=? SimpleWhichKey simplewhichkey#Show(<q-args>)
command! -nargs=? SimpleWhichKeyVisual simplewhichkey#Show(<q-args>, 'x')
command! -nargs=? SimpleWhichKeyOperator simplewhichkey#Show(<q-args>, 'o')
command! SimpleWhichKeyRefresh simplewhichkey#Setup()
command! SimpleWhichKeyToggle simplewhichkey#Toggle()
command! SimpleWhichKeyEnable simplewhichkey#Enable()
command! SimpleWhichKeyDisable simplewhichkey#Disable()
command! SimpleWhichKeyHealth simplewhichkey#Health()

nnoremap <silent> <Plug>(simplewhichkey-toggle) <Cmd>SimpleWhichKeyToggle<CR>

simplewhichkey#SetupHighlights()
simplewhichkey#Setup()

augroup SimpleWhichKey
  autocmd!
  # Mappings and the leaders are usually set after this file is sourced; a
  # second Setup() picks up a leader that changed and re-takes prefixes that
  # were still free.
  autocmd VimEnter * simplewhichkey#Setup()
  autocmd ColorScheme * simplewhichkey#SetupHighlights()
augroup END
