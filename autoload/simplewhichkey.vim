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
#   1. Normal/Visual prefixes enter Start() through <Cmd>; operator prefixes
#      use a recursive <expr> hook so Vim's pending state never has to be
#      cancelled or reconstructed.
#   2. The selector waits a moment. If the next key arrives while waiting, nothing
#      is drawn: fast typists never see the panel, and the timing of an
#      established finger habit does not change.
#   3. Otherwise the panel opens and keys are read with getcharstr() until the
#      sequence stops being a prefix.
#   4. Normal/Visual sequences are handed back with feedkeys(). An operator
#      motion is returned from its expr mapping while the original operator,
#      counts and register remain live. Hooks are suspended during either path
#      so replay cannot re-enter the panel.
#
# Step 4 is deliberately dumb: Vim resolves the selected bytes. Mappings keep
# their own semantics -- <expr>, <ScriptCmd>, <Plug>, buffer-local, silent,
# counts and registers -- because the plugin never interprets their action.
# =============================================================================

const HOOK_MARKER = 'simplewhichkey#\%(Start\|OperatorHook\)'
const RESTORE_GROUP = 'simplewhichkey_restore'
const ESCAPE_KEY = "\<Esc>"
const INTERRUPT_KEY = "\<C-c>"
const BACKSPACE_KEY = "\<BS>"
const IGNORE_KEY = "\<Ignore>"

# mode -> hooked prefixes, in Vim's canonical notation.
var hooks: dict<list<string>> = {}
# mode -> raw sequence -> description, from Register()/Describe().
var descriptions: dict<dict<string>> = {}
var group_names: dict<dict<string>> = {}

var active = false
var suspended_modes: dict<bool> = {}
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
    # Operator results are intentionally remappable after the expr hook
    # removes itself, so discovered user mappings retain their semantics.
    return 'omap'
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

# Whether a full key sequence is hidden from the panel.  It is asked about the
# whole sequence, not about the last key, so naming a group hides its subtree
# and the group's own "+N keys" never counts what it will not show.  Three
# forms, in the order they are cheapest to test:
#
#   '<leader>1'         the sequence itself and everything below it
#   '<leader>1**'       every sequence whose label starts that way
#   '/^<Space>[0-9]/'   a regexp over the label
#
# The glob marker is two stars because one star is a real key and a real
# register: '"*' has to keep meaning the * register alone, and '<leader>*' the
# mapping of that name, otherwise adding the glob form would silently turn an
# existing single hidden key into a hidden subtree.  A sequence whose label
# genuinely ends in '**' is reached with the regexp form.
def Ignored(sequence: string): bool
  var patterns = get(g:, 'simplewhichkey_ignore', [])
  if type(patterns) != v:t_list || empty(patterns)
    return false
  endif
  # keytrans() is only worth paying for once, and only for a pattern form that
  # actually looks at the label.
  var label = ''
  for pattern in patterns
    if type(pattern) != v:t_string || empty(pattern)
      continue
    endif
    if strlen(pattern) > 2 && pattern =~# '^/.*/$'
      if empty(label)
        label = simplewhichkey#keys#Label(sequence)
      endif
      try
        if label =~# strpart(pattern, 1, strlen(pattern) - 2)
          return true
        endif
      catch
        # This runs inside the panel loop, once per candidate. An unusable
        # regexp is a configuration mistake and must not take a keystroke down
        # with it, so it simply matches nothing.
      endtry
      continue
    endif
    if strlen(pattern) > 2 && pattern[-2 : ] ==# '**'
      if empty(label)
        label = simplewhichkey#keys#Label(sequence)
      endif
      var head = simplewhichkey#keys#Label(simplewhichkey#keys#Termcodes(
        strpart(pattern, 0, strlen(pattern) - 2)))
      if strpart(label, 0, strlen(head)) ==# head
        return true
      endif
      continue
    endif
    var raw = simplewhichkey#keys#Termcodes(pattern)
    if !empty(raw)
          && (sequence ==# raw || simplewhichkey#keys#StartsWith(sequence, raw))
      return true
    endif
  endfor
  return false
enddef

def CollectBuiltins(level: dict<any>, mode: string, sequence: string)
  for [raw, description] in items(simplewhichkey#builtin#Table(mode))
    if !simplewhichkey#keys#StartsWith(raw, sequence) || Ignored(raw)
      continue
    endif
    var rest = strpart(raw, strlen(sequence))
    var key = simplewhichkey#keys#First(rest)
    var leaf = strlen(key) == strlen(rest)
    AddNode(level, key, description, !leaf, 'builtin')
  endfor
  for [key, description] in items(simplewhichkey#builtin#Dynamic(mode, sequence))
    if Ignored(sequence .. key)
      continue
    endif
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
      # Filtering the contribution rather than the finished node is what makes
      # a hidden subtree disappear from its parent's "+N keys" as well.
      if Ignored(raw)
        continue
      endif
      var rest = strpart(raw, strlen(sequence))
      var key = simplewhichkey#keys#First(rest)
      var leaf = strlen(key) == strlen(rest)
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
  # Before the overlay: whether two keys are the same command is a fact about
  # Vim's tables, and the overlay is about to replace the text that says so.
  if Flag('simplewhichkey_hide_aliases', 1)
    DropAliases(level)
  endif

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
  return level
enddef

# Vim gives many window commands a Ctrl variant that does exactly the same
# thing: <C-w><C-v> is <C-w>v.  Listing both doubles the panel without adding
# anything, so the Ctrl form is dropped when a plain key already says it.
#
# Sameness is decided from the built-in table's own wording, which is why this
# runs before registered descriptions overwrite it.  Run afterwards, naming
# <C-w>v renamed only the plain node and every one of the ten window pairs
# stopped looking like a duplicate -- naming your window commands used to fill
# the panel with the phantoms this option exists to remove.
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

# Find the exact global mapping even when a buffer-local mapping shadows it in
# maparg(). Install/remove decisions are about the global slot and must never
# overwrite a hidden user mapping or fail to remove a hidden plugin hook.
def GlobalMapping(lhs: string, mode: string): dict<any>
  var wanted = simplewhichkey#keys#Termcodes(lhs)
  for entry in maplist()
    if get(entry, 'abbr', 0) || get(entry, 'buffer', 0)
          \ || !ModeMatches(get(entry, 'mode', ''), mode)
      continue
    endif
    for raw in [get(entry, 'lhsrawalt', ''), get(entry, 'lhsraw', '')]
      if raw !=# '' && raw ==# wanted
        return entry
      endif
    endfor
  endfor
  return {}
enddef

# True when the global mapping slot is free or already held by a hook.  A
# buffer-local mapping does not block the global hook: it simply wins locally.
def Available(lhs: string, mode: string): bool
  var entry = GlobalMapping(lhs, mode)
  return empty(entry) || get(entry, 'rhs', '') =~# HOOK_MARKER
enddef

def InstallHooks(only_mode: string = '')
  for [mode, prefixes] in items(hooks)
    if only_mode !=# '' && mode !=# only_mode
      continue
    endif
    for lhs in prefixes
      if !Available(lhs, mode)
        continue
      endif
      if mode ==# 'o'
        execute printf(
          '%s <silent> <expr> %s simplewhichkey#OperatorHook(%s)',
          MapCommand(mode), lhs, string(lhs))
      else
        execute printf(
          '%s <silent> %s <Cmd>call simplewhichkey#Start(%s, %s)<CR>',
          MapCommand(mode), lhs, string(lhs), string(mode))
      endif
    endfor
  endfor
enddef

def RemoveHooks(only_mode: string = '')
  for [mode, prefixes] in items(hooks)
    if only_mode !=# '' && mode !=# only_mode
      continue
    endif
    for lhs in prefixes
      var entry = GlobalMapping(lhs, mode)
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

def Suspend(mode: string)
  if get(suspended_modes, mode, false)
    return
  endif
  # Only the mappings that could catch this replay need to disappear. Keeping
  # the other modes live is essential when a Normal command such as g@, g~,
  # gu, gU or gq finishes its replay waiting for an operator motion.
  RemoveHooks(mode)
  suspended_modes[mode] = true
enddef

export def Restore()
  if restore_timer >= 0
    timer_stop(restore_timer)
    restore_timer = -1
  endif
  execute 'silent! autocmd! ' .. RESTORE_GROUP
  pending_feeds = 0
  var modes = keys(suspended_modes)
  suspended_modes = {}
  if Flag('simplewhichkey_enable', 1)
    for mode in modes
      InstallHooks(mode)
    endfor
  endif
enddef

export def RestoreWhenIdle()
  if empty(state('mo'))
    Restore()
  endif
enddef

def RestoreTick(_: number)
  # 'm' means a mapping or :normal is still halfway; restoring the hooks then
  # could feed the replayed keys straight back into Start().
  if !empty(state('mo'))
    return
  endif
  RestoreWhenIdle()
enddef

def ScheduleRestore()
  execute 'augroup ' .. RESTORE_GROUP
  execute 'autocmd!'
  # SafeState is the accurate signal: it fires only once nothing is pending.
  # The others cover the states SafeState does not reach, such as sitting in
  # Insert mode after a mapping that ends there.
  autocmd SafeState * ++once simplewhichkey#RestoreWhenIdle()
  autocmd InsertLeave,CmdlineLeave,CursorHold * ++once simplewhichkey#RestoreWhenIdle()
  augroup END
  if restore_timer >= 0
    timer_stop(restore_timer)
  endif
  restore_timer = timer_start(200, RestoreTick, {repeat: -1})
enddef

def Feed(sequence: string, mode: string)
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
  # Preserve only the transition this feature needs: a Normal replay may end
  # waiting for an operator motion, so its o-mode hints stay installed. Other
  # replay entry points may cross back through Normal mode, therefore all
  # prefix modes are suspended for those paths.
  Suspend('n')
  Suspend('x')
  if mode !=# 'n'
    Suspend('o')
  endif
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

# How long this particular prefix waits.  One number applies everywhere; a
# dictionary lets prefixes differ, which they need to: the leader has already
# cost a full 'timeoutlen' before the hook runs, <C-w> is dispatched instantly
# and wants a real pause, and a text object introducer sits on the hottest key
# in the language and wants almost none.  Lookup order is 'mode:prefix'
# ("o:i"), then 'prefix', then 'default'.  Prefix keys are compared after
# termcode expansion, so '<leader>', '<Space>' and a literal ' ' are one key.
def ConfiguredDelay(mode: string, sequence: string): number
  var configured = get(g:, 'simplewhichkey_delay', 200)
  if type(configured) == v:t_number
    return configured >= 0 ? configured : 200
  endif
  if type(configured) != v:t_dict
    return 200
  endif
  var fallback = 200
  var plain = -1
  var scoped = -1
  for [key, value] in items(configured)
    if type(value) != v:t_number || value < 0
      continue
    endif
    if key ==# 'default'
      fallback = value
      continue
    endif
    var notation = key
    var qualifies = key =~# '^[nxo]:'
    if qualifies
      if key[0] !=# mode
        continue
      endif
      notation = strpart(key, 2)
    endif
    if simplewhichkey#keys#Termcodes(notation) !=# sequence
      continue
    endif
    if qualifies
      scoped = value
    else
      plain = value
    endif
  endfor
  if scoped >= 0
    return scoped
  endif
  return plain >= 0 ? plain : fallback
enddef

# The delay a prefix resolves to, for :SimpleWhichKeyHealth and for tests.
export def ResolvedDelay(mode: string, prefix: string): number
  return ConfiguredDelay(mode, simplewhichkey#keys#Termcodes(prefix))
enddef

def InitialDelay(mode: string, sequence: string): number
  return Ambiguous(mode, sequence) ? 0 : ConfiguredDelay(mode, sequence)
enddef

def SelectSequence(raw_prefix: string, mode: string): dict<any>
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
        simplewhichkey#panel#Show(
          Title(sequence), Entries(level), mode .. "\x01" .. sequence)
        pending = getcharstr()
      endif
      var char = pending
      pending = ''

      if empty(char) || char ==# ESCAPE_KEY || char ==# INTERRUPT_KEY
        aborted = true
        break
      endif
      var page = simplewhichkey#keys#PageDirection(char)
      if page != 0 && !has_key(level, char) && simplewhichkey#panel#Scroll(page)
        continue
      endif
      var scroll = simplewhichkey#keys#ScrollDirection(char)
      if scroll != 0
        simplewhichkey#panel#Scroll(scroll)
        continue
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

  return {aborted: aborted, sequence: sequence}
enddef

# Called as an operator-pending <expr> mapping. Selection happens while Vim's
# original operator is still pending, and the chosen motion is returned
# directly. Vim therefore retains the exact operator/count/register state.
export def OperatorHook(prefix: string): string
  var raw_prefix = simplewhichkey#keys#Termcodes(prefix)
  if empty(raw_prefix)
    return ''
  endif
  if !Flag('simplewhichkey_enable', 1) || active
        \ || empty(Level('o', raw_prefix))
    Suspend('o')
    ScheduleRestore()
    return IGNORE_KEY .. raw_prefix
  endif
  var selected = SelectSequence(raw_prefix, 'o')
  if selected.aborted
    return ESCAPE_KEY
  endif
  # A recursive expr mapping normally suppresses remapping of its first result
  # byte to prevent self-recursion. <Ignore> forms a harmless boundary; after
  # the hook is removed, the complete returned motion can resolve user omaps,
  # <Plug> targets and expr mappings exactly as typed.
  Suspend('o')
  ScheduleRestore()
  return IGNORE_KEY .. selected.sequence
enddef

export def Start(prefix: string, mode: string = 'n')
  # Normal/Visual prefixes are replayed from their mapping context, so capture
  # count/register before waiting or drawing. Operator hooks never come here:
  # they preserve Vim's live pending state and replay only a motion above.
  var captured_count = v:count
  var captured_register = v:register
  var captured_default_register = DefaultRegister()
  var raw_prefix = simplewhichkey#keys#Termcodes(prefix)
  if empty(raw_prefix)
    return
  endif
  var count = captured_count > 0 ? string(captured_count) : ''
  var register = captured_register ==# captured_default_register
    ? '' : '"' .. captured_register
  var replay_head = count .. register

  # Disabled, re-entered, or nothing known under this prefix: hand the key back
  # without waiting, so a key that has nothing to show keeps its native speed.
  if !Flag('simplewhichkey_enable', 1) || active || empty(Level(mode, raw_prefix))
    Feed(replay_head .. raw_prefix, mode)
    return
  endif

  var selected = SelectSequence(raw_prefix, mode)
  if selected.aborted
    return
  endif
  Feed(replay_head .. selected.sequence, mode)
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

# Browse a level without executing what is chosen.  :SimpleWhichKeyOperator is
# typed on the command line, so no operator is pending behind it and the motion
# it lists means nothing on its own.  Replaying the selection would run it in
# Normal mode, where the same keys are a different command entirely -- with
# `onoremap gx iw` the panel advertises a text object and choosing it would
# open the URL under the cursor.  So report the sequence instead.
#
# :SimpleWhichKeyVisual has exactly the same problem: typing ':' leaves Visual
# mode, so there is no selection behind the command either, and an xmap chosen
# from that panel would run as the unrelated Normal-mode command of the same
# name.  It browses too -- unless a selection really is live, which is the case
# when the command is reached through <Cmd> from a Visual mapping.
def Browse(prefix: string, mode: string)
  var raw_prefix = simplewhichkey#keys#Termcodes(prefix)
  if empty(raw_prefix) || !Flag('simplewhichkey_enable', 1) || active
    return
  endif
  if empty(Level(mode, raw_prefix))
    Notify('nothing is listed under ' .. simplewhichkey#keys#Label(raw_prefix))
    return
  endif
  var selected = SelectSequence(raw_prefix, mode)
  if selected.aborted
    return
  endif
  echo printf('[SimpleWhichKey] %s: %s',
    mode ==# 'o' ? 'operator-pending motion' : 'visual mode sequence',
    Title(selected.sequence))
enddef

# True while a Visual or Select selection is live, so a replayed sequence lands
# in the mode the panel listed.
def Selecting(): bool
  return mode() =~# "^[vVsS\<C-V>\<C-S>]"
enddef

# :SimpleWhichKey [prefix]
export def Show(argument: string, mode: string = 'n')
  var prefix = empty(argument) ? (mode ==# 'o' ? 'g' : '<leader>') : argument
  if mode ==# 'o' || (mode ==# 'x' && !Selecting())
    Browse(prefix, mode)
    return
  endif
  Start(prefix, mode)
enddef

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

# Every distinct user mapping in a mode, raw, with the plugin's own hooks left
# out.  Both reports below start from this one sweep.
def UserMappings(mode: string): list<string>
  var seen: dict<bool> = {}
  for entry in maplist()
    if get(entry, 'abbr', 0) || !ModeMatches(get(entry, 'mode', ''), mode)
      continue
    endif
    if get(entry, 'rhs', '') =~# HOOK_MARKER
      continue
    endif
    for raw in [get(entry, 'lhsraw', ''), get(entry, 'lhsrawalt', '')]
      if !empty(raw)
        seen[raw] = true
      endif
    endfor
  endfor
  return sort(keys(seen))
enddef

# Pairs where one mapping continues another.  Vim cannot dispatch the shorter
# one until 'timeoutlen' has passed, which is the usual answer to "why does
# this key feel slow" -- and the panel is built on exactly that pause, so the
# plugin already knows which keys pay it.
export def Conflicts(mode: string = 'n'): list<dict<string>>
  var raws = UserMappings(mode)
  var out: list<dict<string>> = []
  # Sorting puts every continuation of a sequence directly after it, so a
  # forward scan that stops at the first non-continuation sees them all
  # without an all-pairs comparison.
  for index in range(len(raws))
    for follower in range(index + 1, len(raws) - 1)
      if !simplewhichkey#keys#StartsWith(raws[follower], raws[index])
        break
      endif
      add(out, {
        short: simplewhichkey#keys#Label(raws[index]),
        long: simplewhichkey#keys#Label(raws[follower]),
      })
    endfor
  endfor
  return out
enddef

# Registered descriptions that name a sequence nothing provides.  A description
# for a key that does not exist is silently ignored everywhere else, so a typo
# in Describe() has no other symptom than the name never appearing.
export def Orphans(mode: string = 'n'): list<string>
  var known = UserMappings(mode) + keys(simplewhichkey#builtin#Table(mode))
  var out: list<string> = []
  for registry in [get(descriptions, mode, {}), get(group_names, mode, {})]
    for sequence in keys(registry)
      var covered = false
      for raw in known
        # A group name describes a prefix rather than a sequence of its own, so
        # anything continuing it counts as coverage.
        if raw ==# sequence || simplewhichkey#keys#StartsWith(raw, sequence)
          covered = true
          break
        endif
      endfor
      if !covered
        add(out, simplewhichkey#keys#Label(sequence))
      endif
    endfor
  endfor
  return sort(out)
enddef

# :SimpleWhichKeyConflicts
export def Report()
  var lines = ['[SimpleWhichKey] conflicts']
  if !&timeout
    add(lines, "  [WARN] 'notimeout' is set: Vim never dispatches an ambiguous")
    add(lines, '         prefix on its own, so a prefix that other mappings')
    add(lines, '         extend can never reach the panel')
  elseif &timeoutlen > 1000
    add(lines, printf('  [WARN] timeoutlen is %d ms: every prefix that other',
      &timeoutlen))
    add(lines, '         mappings extend waits that long before its panel opens')
  endif
  for mode in sort(keys(hooks))
    add(lines, printf('  mode %s', mode))
    var conflicts = Conflicts(mode)
    if empty(conflicts)
      add(lines, '    no mapping waits for a longer one')
    endif
    for pair in conflicts
      add(lines, printf('    %-16s waits for %s', pair.short, pair.long))
    endfor
    for label in Orphans(mode)
      add(lines, printf('    %-16s described, but nothing is mapped there',
        label))
    endfor
    for lhs in get(hooks, mode, [])
      if empty(Level(mode, simplewhichkey#keys#Termcodes(lhs)))
        # Registers and marks come from live state, so "nothing" here can be a
        # true but momentary answer; say so rather than implying it is broken.
        add(lines, printf('    %-16s hooked, but lists nothing right now', lhs))
      endif
    endfor
  endfor
  echo join(lines, "\n")
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
  var configured_delay = get(g:, 'simplewhichkey_delay', 200)
  add(lines, printf('  delay          : %s (timeoutlen %d ms)',
    type(configured_delay) == v:t_number
      ? printf('%d ms', configured_delay)
      : string(configured_delay),
    &timeoutlen))
  var description_count = 0
  var group_count = 0
  for registered in values(descriptions)
    description_count += len(registered)
  endfor
  for registered in values(group_names)
    group_count += len(registered)
  endfor
  add(lines, printf('  descriptions   : %d entries, %d groups',
    description_count, group_count))
  var shadowed = 0
  var unknown = 0
  for mode in keys(hooks)
    shadowed += len(Conflicts(mode))
    unknown += len(Orphans(mode))
  endfor
  add(lines, printf(
    '  conflicts      : %d mapping(s) waiting for a longer one, '
    .. '%d description(s) naming nothing (:SimpleWhichKeyConflicts)',
    shadowed, unknown))
  if !&timeout
    add(lines, "  [WARN] 'notimeout' keeps an ambiguous prefix from dispatching")
  endif
  for [mode, prefixes] in items(hooks)
    add(lines, printf('  mode %s', mode))
    for lhs in prefixes
      # maparg() reports a current-buffer mapping first and can hide the
      # global slot whose ownership Health is describing.
      var entry = GlobalMapping(lhs, mode)
      var status = 'MISSING'
      if !empty(entry) && get(entry, 'rhs', '') =~# HOOK_MARKER
        status = 'hooked'
      elseif !empty(entry)
        status = 'taken by another mapping'
      endif
      var raw = simplewhichkey#keys#Termcodes(lhs)
      # The resolved delay belongs next to the prefix it applies to: with a
      # per-prefix table it is the only place the effective value is visible.
      add(lines, printf(
        '    %-10s %-24s %d mapping(s), %d built-in(s), %d ms',
        lhs,
        status,
        CountMappings(mode, raw),
        len(filter(
          keys(simplewhichkey#builtin#Table(mode)),
          (_, key) => simplewhichkey#keys#StartsWith(key, raw))),
        ConfiguredDelay(mode, raw)))
    endfor
  endfor
  echo join(lines, "\n")
enddef
