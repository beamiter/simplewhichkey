vim9script

# =============================================================================
# SimpleWhichKey
#
# Vim can tell you what a key does only after you press it.  This plugin maps
# every prefix you care about -- the leader, but also <C-w>, g, z, [, ], " and
# the mark keys -- to a hint panel that lists what may follow.
#
# How a keystroke flows through here:
#
#   1. The prefix is mapped to <Cmd>call simplewhichkey#Start(...)<CR>, so
#      pressing it lands in Start() instead of Vim's command table.
#   2. Start() waits a moment.  If the next key arrives while waiting, nothing
#      is drawn: fast typists never see the panel, and the timing of an
#      established finger habit does not change.
#   3. Otherwise the panel opens and keys are read with getcharstr() until the
#      sequence stops being a prefix.
#   4. The collected sequence is handed back to Vim with feedkeys().  The hooks
#      are removed for the duration, which is what keeps the replay from
#      re-entering Start(), and restored once Vim is idle again.
#
# Step 4 is deliberately dumb: the sequence is replayed as typed rather than
# interpreted here.  Mappings therefore keep their own semantics -- <expr>,
# <ScriptCmd>, buffer-local, silent, counts, registers -- because Vim, not this
# plugin, is the one resolving them.
# =============================================================================

const HOOK_MARKER = 'simplewhichkey#Start'
const RESTORE_GROUP = 'simplewhichkey_restore'
const ESCAPE_KEY = "\<Esc>"
const INTERRUPT_KEY = "\<C-c>"
const BACKSPACE_KEY = "\<BS>"

# mode -> hooked prefixes, in Vim's canonical notation.
var hooks: dict<list<string>> = {}
# mode -> raw sequence -> description, from Register()/Describe().
var descriptions: dict<dict<string>> = {}
var group_names: dict<dict<string>> = {}

var active = false
var suspended = false
var pending_feeds = 0
var restore_timer = -1

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def Notify(message: string)
  echohl WarningMsg
  echomsg '[SimpleWhichKey] ' .. message
  echohl None
enddef

def Flag(name: string, fallback: number): number
  var value = get(g:, name, fallback)
  return type(value) == v:t_number ? (value != 0 ? 1 : 0) : fallback
enddef

def MapCommand(mode: string): string
  if mode ==# 'x'
    return 'xnoremap'
  endif
  if mode ==# 'o'
    return 'onoremap'
  endif
  return 'nnoremap'
enddef

def UnmapCommand(mode: string): string
  if mode ==# 'x'
    return 'xunmap'
  endif
  if mode ==# 'o'
    return 'ounmap'
  endif
  return 'nunmap'
enddef

# maplist() reports the modes of a mapping as they appear in :map output, where
# a single space stands for normal, visual and operator-pending at once.
def ModeMatches(entry_mode: string, mode: string): bool
  if empty(entry_mode)
    return false
  endif
  if entry_mode ==# ' '
    return mode ==# 'n' || mode ==# 'x' || mode ==# 'o' || mode ==# 'v'
  endif
  if entry_mode ==# 'v'
    return mode ==# 'x' || mode ==# 'v' || mode ==# 's'
  endif
  return entry_mode ==# mode
enddef

# The raw form of a mapping's left hand side that continues 'sequence', if any.
# Control keys have two encodings and maplist() reports both.
def MatchingLhs(entry: dict<any>, sequence: string): string
  for raw in [get(entry, 'lhsrawalt', ''), get(entry, 'lhsraw', '')]
    if !empty(raw) && simplewhichkey#keys#StartsWith(raw, sequence)
      return raw
    endif
  endfor
  return ''
enddef

def DefaultRegister(): string
  if &clipboard =~# 'unnamedplus'
    return '+'
  endif
  if &clipboard =~# 'unnamed'
    return '*'
  endif
  return '"'
enddef

# ---------------------------------------------------------------------------
# Descriptions
# ---------------------------------------------------------------------------

# What a mapping does, guessed from its right hand side.  This is what makes
# an unregistered configuration useful on the first run: '<Cmd>SimpleGitDiff<CR>'
# reads as 'SimpleGitDiff' and '<Plug>(simpletree-toggle)' as 'simpletree-toggle'.
def DeriveDescription(entry: dict<any>): string
  if get(entry, 'expr', 0)
    return 'expr: ' .. get(entry, 'rhs', '')
  endif
  var text = get(entry, 'rhs', '')
  text = substitute(text, '\c^<Cmd>', '', '')
  text = substitute(text, '\c^<ScriptCmd>', '', '')
  text = substitute(text, '^:\+', '', '')
  text = substitute(text, '\c^<C-U>', '', '')
  text = substitute(text, '\c<CR>$', '', '')
  text = substitute(text, '\c^<Plug>(\(.\{-}\))$', '\1', '')
  text = substitute(text, '\c^<Plug>', '', '')
  text = substitute(text, '^\s\+', '', '')
  text = substitute(text, '\s\+$', '', '')
  return empty(text) ? '…' : text
enddef

def Registered(mode: string, sequence: string): string
  return get(get(descriptions, mode, {}), sequence, '')
enddef

def RegisteredGroup(mode: string, sequence: string): string
  return get(get(group_names, mode, {}), sequence, '')
enddef

def Flatten(sequence: string, spec: dict<any>, mode: string)
  for [key, value] in items(spec)
    if key ==# 'name'
      if type(value) == v:t_string
        group_names[mode][sequence] = value
      endif
      continue
    endif
    var child = sequence .. simplewhichkey#keys#Termcodes(key)
    if type(value) == v:t_dict
      Flatten(child, value, mode)
    elseif type(value) == v:t_list
      # which-key's [command, description] form; the command is ignored because
      # the real mapping is what gets executed.
      if len(value) > 1 && type(value[1]) == v:t_string
        descriptions[mode][child] = value[1]
      endif
    elseif type(value) == v:t_string
      descriptions[mode][child] = value
    endif
  endfor
enddef

# Register a nested description dictionary, in the shape vim-which-key used, so
# an existing g:which_key_map can be reused unchanged.
export def Register(prefix: string, spec: any, mode: string = 'n')
  var root: any = spec
  if type(spec) == v:t_string
    if !exists(spec)
      Notify('unknown variable: ' .. spec)
      return
    endif
    root = eval(spec)
  endif
  if type(root) != v:t_dict
    Notify('Register() needs a dictionary')
    return
  endif
  if !has_key(descriptions, mode)
    descriptions[mode] = {}
    group_names[mode] = {}
  endif
  Flatten(simplewhichkey#keys#Termcodes(prefix), root, mode)
enddef

# Flat form: {'<Space>ff': 'find files', '<Space>f': '+file'}.  A description
# starting with '+' names a group.
export def Describe(spec: dict<string>, mode: string = 'n')
  if !has_key(descriptions, mode)
    descriptions[mode] = {}
    group_names[mode] = {}
  endif
  for [notation, description] in items(spec)
    var sequence = simplewhichkey#keys#Termcodes(notation)
    if description =~# '^+'
      group_names[mode][sequence] = description
    else
      descriptions[mode][sequence] = description
    endif
  endfor
enddef

export def Forget()
  descriptions = {}
  group_names = {}
enddef

# ---------------------------------------------------------------------------
# One level of the key tree
# ---------------------------------------------------------------------------

def AddNode(level: dict<any>, key: string, description: string, group: bool, source: string)
  if !has_key(level, key)
    level[key] = {
      label: simplewhichkey#keys#Label(key),
      desc: '',
      group: false,
      count: 0,
      source: source,
    }
  endif
  var node = level[key]
  if group
    node.group = true
    node.count += 1
    # A '+name' entry names the group; anything else is a leaf description and
    # must not overwrite it.
    if description =~# '^+'
      node.desc = description
    endif
  else
    node.group = node.group || description =~# '^+'
    if empty(node.desc) || source ==# 'map'
      node.desc = description
    endif
  endif
  if source ==# 'map'
    node.source = 'map'
  endif
enddef

def Ignored(sequence: string): bool
  var patterns = get(g:, 'simplewhichkey_ignore', [])
  if type(patterns) != v:t_list
    return false
  endif
  for notation in patterns
    if type(notation) == v:t_string
          && simplewhichkey#keys#Termcodes(notation) ==# sequence
      return true
    endif
  endfor
  return false
enddef

def CollectBuiltins(level: dict<any>, mode: string, sequence: string)
  for [raw, description] in items(simplewhichkey#builtin#Table(mode))
    if !simplewhichkey#keys#StartsWith(raw, sequence)
      continue
    endif
    var rest = strpart(raw, strlen(sequence))
    var key = simplewhichkey#keys#First(rest)
    var leaf = strlen(key) == strlen(rest)
    AddNode(level, key, description, !leaf, 'builtin')
  endfor
  for [key, description] in items(simplewhichkey#builtin#Dynamic(mode, sequence))
    AddNode(level, key, description, false, 'dynamic')
  endfor
enddef

def CollectMappings(level: dict<any>, mode: string, sequence: string)
  # Global mappings first: a buffer-local mapping on the same keys wins, and
  # overwriting in that order is what makes it win here too.
  for buffer_local in [0, 1]
    for entry in maplist()
      if get(entry, 'abbr', 0) || get(entry, 'buffer', 0) != buffer_local
        continue
      endif
      if !ModeMatches(get(entry, 'mode', ''), mode)
        continue
      endif
      var raw = MatchingLhs(entry, sequence)
      if empty(raw) || get(entry, 'rhs', '') =~# HOOK_MARKER
        continue
      endif
      var rest = strpart(raw, strlen(sequence))
      var key = simplewhichkey#keys#First(rest)
      var leaf = strlen(key) == strlen(rest)
      if leaf && Ignored(raw)
        continue
      endif
      AddNode(level, key, leaf ? DeriveDescription(entry) : '', !leaf, 'map')
    endfor
  endfor
enddef

# Everything that may follow 'sequence', keyed by the raw next key.
def Level(mode: string, sequence: string): dict<any>
  var level: dict<any> = {}
  if Flag('simplewhichkey_show_builtins', 1)
    CollectBuiltins(level, mode, sequence)
  endif
  CollectMappings(level, mode, sequence)

  for [key, node] in items(level)
    var full = sequence .. key
    if node.group
      var name = RegisteredGroup(mode, full)
      if !empty(name)
        node.desc = name
      elseif empty(node.desc)
        node.desc = printf('+%d keys', node.count)
      endif
    else
      var description = Registered(mode, full)
      if !empty(description)
        node.desc = description
      endif
    endif
  endfor
  if Flag('simplewhichkey_hide_aliases', 1)
    DropAliases(level)
  endif
  return level
enddef

# Vim gives many window commands a Ctrl variant that does exactly the same
# thing: <C-w><C-v> is <C-w>v.  Listing both doubles the panel without adding
# anything, so the Ctrl form is dropped when a plain key already says it.
def DropAliases(level: dict<any>)
  var described: dict<bool> = {}
  for [key, node] in items(level)
    if node.source ==# 'builtin' && node.label !~# '^<C-'
      described[node.desc] = true
    endif
  endfor
  for [key, node] in items(level)
    if node.source ==# 'builtin' && node.label =~# '^<C-' && get(described, node.desc, false)
      remove(level, key)
    endif
  endfor
enddef

def Entries(level: dict<any>): list<dict<any>>
  var out: list<dict<any>> = []
  for node in values(level)
    add(out, node)
  endfor
  return out
enddef

def Title(sequence: string): string
  var parts: list<string> = []
  for key in simplewhichkey#keys#Split(sequence)
    add(parts, simplewhichkey#keys#Label(key))
  endfor
  return join(parts, ' ')
enddef

# ---------------------------------------------------------------------------
# Hooks
# ---------------------------------------------------------------------------

# True when the global mapping slot is free or already held by a hook.  A
# buffer-local mapping does not block the global hook: it simply wins locally.
def Available(lhs: string, mode: string): bool
  var entry = maparg(lhs, mode, false, true)
  if empty(entry) || get(entry, 'buffer', 0)
    return true
  endif
  return get(entry, 'rhs', '') =~# HOOK_MARKER
enddef

def InstallHooks()
  for [mode, prefixes] in items(hooks)
    for lhs in prefixes
      if !Available(lhs, mode)
        continue
      endif
      execute printf(
        '%s <silent> %s <Cmd>call simplewhichkey#Start(%s, %s)<CR>',
        MapCommand(mode),
        lhs,
        string(lhs),
        string(mode))
    endfor
  endfor
enddef

def RemoveHooks()
  for [mode, prefixes] in items(hooks)
    for lhs in prefixes
      var entry = maparg(lhs, mode, false, true)
      if empty(entry) || get(entry, 'buffer', 0)
        continue
      endif
      if get(entry, 'rhs', '') =~# HOOK_MARKER
        execute printf('silent! %s %s', UnmapCommand(mode), lhs)
      endif
    endfor
  endfor
enddef

export def Setup()
  var configured = get(g:, 'simplewhichkey_prefixes', {})
  if type(configured) != v:t_dict
    return
  endif
  RemoveHooks()
  hooks = {}
  for [mode, prefixes] in items(configured)
    if index(['n', 'x', 'o'], mode) < 0 || type(prefixes) != v:t_list
      continue
    endif
    var canonical: list<string> = []
    for notation in prefixes
      if type(notation) != v:t_string
        continue
      endif
      var raw = simplewhichkey#keys#Termcodes(notation)
      if empty(raw)
        continue
      endif
      var lhs = simplewhichkey#keys#Label(raw)
      if index(canonical, lhs) < 0
        add(canonical, lhs)
      endif
    endfor
    if !empty(canonical)
      hooks[mode] = canonical
    endif
  endfor
  if Flag('simplewhichkey_enable', 1)
    InstallHooks()
  endif
enddef

export def Enable()
  g:simplewhichkey_enable = 1
  InstallHooks()
enddef

export def Disable()
  g:simplewhichkey_enable = 0
  RemoveHooks()
enddef

export def Toggle()
  if Flag('simplewhichkey_enable', 1)
    Disable()
    echo '[SimpleWhichKey] off'
  else
    Enable()
    echo '[SimpleWhichKey] on'
  endif
enddef

# ---------------------------------------------------------------------------
# Replay
# ---------------------------------------------------------------------------

def Suspend()
  if suspended
    return
  endif
  RemoveHooks()
  suspended = true
enddef

export def Restore()
  if restore_timer >= 0
    timer_stop(restore_timer)
    restore_timer = -1
  endif
  execute 'silent! autocmd! ' .. RESTORE_GROUP
  pending_feeds = 0
  if suspended
    suspended = false
    if Flag('simplewhichkey_enable', 1)
      InstallHooks()
    endif
  endif
enddef

def RestoreTick(_: number)
  # 'm' means a mapping or :normal is still halfway; restoring the hooks then
  # could feed the replayed keys straight back into Start().
  if !empty(state('mo'))
    return
  endif
  Restore()
enddef

def ScheduleRestore()
  execute 'augroup ' .. RESTORE_GROUP
  execute 'autocmd!'
  # SafeState is the accurate signal: it fires only once nothing is pending.
  # The others cover the states SafeState does not reach, such as sitting in
  # Insert mode after a mapping that ends there.
  autocmd SafeState * ++once simplewhichkey#Restore()
  autocmd InsertLeave,CmdlineLeave,CursorHold * ++once simplewhichkey#Restore()
  augroup END
  if restore_timer >= 0
    timer_stop(restore_timer)
  endif
  restore_timer = timer_start(200, RestoreTick, {repeat: -1})
enddef

def Feed(sequence: string)
  if empty(sequence)
    Restore()
    return
  endif
  if pending_feeds >= 3
    # Three replays without ever reaching a quiet moment means something is
    # feeding us our own keys; stop rather than spin.
    Notify('key replay did not settle, hints skipped for this keystroke')
    Restore()
    return
  endif
  Suspend()
  pending_feeds += 1
  feedkeys(sequence, 'mt')
  ScheduleRestore()
enddef

# ---------------------------------------------------------------------------
# The panel loop
# ---------------------------------------------------------------------------

def PollKey(delay: number): string
  var char = getcharstr(0)
  if !empty(char) || delay <= 0
    return char
  endif
  var waited = 0
  while waited < delay
    sleep 10m
    waited += 10
    char = getcharstr(0)
    if !empty(char)
      return char
    endif
  endwhile
  return ''
enddef

# Vim waits 'timeoutlen' by itself when other mappings extend the prefix, so by
# the time Start() runs the user has already paused.  Waiting again would only
# add lag; the extra delay is for prefixes Vim dispatches immediately.
def Ambiguous(mode: string, sequence: string): bool
  for entry in maplist()
    if get(entry, 'abbr', 0) || !ModeMatches(get(entry, 'mode', ''), mode)
      continue
    endif
    if get(entry, 'rhs', '') =~# HOOK_MARKER
      continue
    endif
    if !empty(MatchingLhs(entry, sequence))
      return true
    endif
  endfor
  return false
enddef

def InitialDelay(mode: string, sequence: string): number
  var delay = get(g:, 'simplewhichkey_delay', 200)
  if type(delay) != v:t_number || delay < 0
    delay = 200
  endif
  return Ambiguous(mode, sequence) ? 0 : delay
enddef

export def Start(prefix: string, mode: string = 'n')
  var raw_prefix = simplewhichkey#keys#Termcodes(prefix)
  if empty(raw_prefix)
    return
  endif
  var count = v:count > 0 ? string(v:count) : ''
  var register = v:register ==# DefaultRegister() ? '' : '"' .. v:register

  # Disabled, re-entered, or nothing known under this prefix: hand the key back
  # without waiting, so a key that has nothing to show keeps its native speed.
  if !Flag('simplewhichkey_enable', 1) || active || empty(Level(mode, raw_prefix))
    Feed(count .. register .. raw_prefix)
    return
  endif

  active = true
  var sequence = raw_prefix
  var stack: list<string> = []
  var pending = PollKey(InitialDelay(mode, raw_prefix))
  var aborted = false

  try
    while true
      var level = Level(mode, sequence)
      if empty(level)
        break
      endif
      if empty(pending)
        pending = getcharstr(0)
      endif
      if empty(pending)
        simplewhichkey#panel#Show(Title(sequence), Entries(level))
        pending = getcharstr()
      endif
      var char = pending
      pending = ''

      if empty(char) || char ==# ESCAPE_KEY || char ==# INTERRUPT_KEY
        aborted = true
        break
      endif
      if simplewhichkey#keys#IsMouse(char)
        continue
      endif
      if char ==# BACKSPACE_KEY && !empty(stack)
        sequence = remove(stack, -1)
        continue
      endif

      add(stack, sequence)
      sequence ..= char
      var node = get(level, char, {})
      if !empty(node) && node.group
        continue
      endif
      break
    endwhile
  catch /^Vim:Interrupt$/
    aborted = true
  finally
    simplewhichkey#panel#Close()
    active = false
  endtry

  if aborted
    return
  endif
  Feed(count .. register .. sequence)
enddef

# What the panel would list for a prefix, without opening it.  Useful to check
# a configuration ( :echo simplewhichkey#Keys('n', '<C-w>') ) and in tests.
export def Keys(mode: string, prefix: string): dict<any>
  var out: dict<any> = {}
  for [key, node] in items(Level(mode, simplewhichkey#keys#Termcodes(prefix)))
    out[simplewhichkey#keys#Label(key)] = {
      desc: node.desc,
      group: node.group,
      source: node.source,
    }
  endfor
  return out
enddef

# :SimpleWhichKey [prefix]
export def Show(argument: string, mode: string = 'n')
  var prefix = empty(argument) ? '<leader>' : argument
  Start(prefix, mode)
enddef

# ---------------------------------------------------------------------------
# Highlights and health
# ---------------------------------------------------------------------------

export def SetupHighlights()
  highlight default link SimpleWhichKeyNormal Normal
  highlight default link SimpleWhichKeyBorder Comment
  highlight default link SimpleWhichKeyKey Identifier
  highlight default link SimpleWhichKeyDesc Normal
  highlight default link SimpleWhichKeyGroup Function
  highlight default link SimpleWhichKeySeparator Comment
  simplewhichkey#panel#ResetProps()
enddef

def CountMappings(mode: string, sequence: string): number
  var total = 0
  for entry in maplist()
    if get(entry, 'abbr', 0) || !ModeMatches(get(entry, 'mode', ''), mode)
      continue
    endif
    if get(entry, 'rhs', '') =~# HOOK_MARKER
      continue
    endif
    if !empty(MatchingLhs(entry, sequence))
      total += 1
    endif
  endfor
  return total
enddef

export def Health()
  var lines = ['[SimpleWhichKey] health']
  add(lines, printf('  vim            : %d.%d patch %d',
    v:version / 100, v:version % 100, v:versionlong % 10000))
  add(lines, printf('  popup window   : %s', has('popupwin') ? 'yes' : 'NO'))
  add(lines, printf('  text properties: %s', has('textprop') ? 'yes' : 'NO'))
  add(lines, printf('  enabled        : %s', Flag('simplewhichkey_enable', 1) ? 'yes' : 'no'))
  add(lines, printf('  delay          : %d ms (timeoutlen %d ms)',
    get(g:, 'simplewhichkey_delay', 200), &timeoutlen))
  add(lines, printf('  descriptions   : %d entries, %d groups',
    len(get(descriptions, 'n', {})) + len(get(descriptions, 'x', {})),
    len(get(group_names, 'n', {})) + len(get(group_names, 'x', {}))))
  for [mode, prefixes] in items(hooks)
    add(lines, printf('  mode %s', mode))
    for lhs in prefixes
      var entry = maparg(lhs, mode, false, true)
      var status = 'MISSING'
      if !empty(entry) && get(entry, 'rhs', '') =~# HOOK_MARKER
        status = 'hooked'
      elseif !empty(entry)
        status = 'taken by another mapping'
      endif
      var raw = simplewhichkey#keys#Termcodes(lhs)
      add(lines, printf('    %-10s %-24s %d mapping(s), %d built-in(s)',
        lhs,
        status,
        CountMappings(mode, raw),
        len(filter(
          keys(simplewhichkey#builtin#Table(mode)),
          (_, key) => simplewhichkey#keys#StartsWith(key, raw)))))
    endfor
  endfor
  echo join(lines, "\n")
enddef
