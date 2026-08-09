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

const HOOK_MARKER = 'simplewhichkey#\%(Start\|OperatorHook\|InsertHook\)'
# Modes whose hook returns the chosen keys from an <expr> mapping instead of
# feeding them: Vim's live state -- a pending operator, a half-typed line --
# has to survive the detour, and only the expr form leaves it alone.
const EXPR_MODES = ['o', 'i', 'c']
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

# One maplist() sweep is cheap; the number of them is not.  Level() is built
# once to decide whether a prefix has anything to show, again for the first
# panel, again for every keystroke that descends, and once per group when the
# whole tree is listed -- each sweep copying every mapping in the editor.
#
# Everything that reads the mapping table goes through Mappings(), which is a
# live sweep unless a bounded operation has opened a snapshot.  The snapshot is
# never left open across anything that installs or removes a mapping, which is
# what makes "cached" safe here: within one panel session or one listing the
# mapping table cannot change, because the plugin is the only thing running.
var snapshot: list<dict<any>> = []
var snapshot_depth = 0
var sweeps = 0

def OpenSnapshot()
  if snapshot_depth == 0
    sweeps += 1
    snapshot = maplist()
  endif
  snapshot_depth += 1
enddef

def CloseSnapshot()
  snapshot_depth -= 1
  if snapshot_depth <= 0
    snapshot_depth = 0
    snapshot = []
  endif
enddef

def Mappings(): list<dict<any>>
  if snapshot_depth > 0
    return snapshot
  endif
  sweeps += 1
  return maplist()
enddef

# How many times the mapping table has been read since Vim started.  The
# answer to "why does the panel feel slow in this configuration" is usually
# this number multiplied by how many mappings you have.
export def Sweeps(): number
  return sweeps
enddef

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
  # Results of the expr hooks are intentionally remappable after the hook
  # removes itself, so discovered user mappings retain their semantics.
  if mode ==# 'o'
    return 'omap'
  endif
  if mode ==# 'i'
    return 'imap'
  endif
  if mode ==# 'c'
    return 'cmap'
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
  if mode ==# 'i'
    return 'iunmap'
  endif
  if mode ==# 'c'
    return 'cunmap'
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
  # ':map!' covers Insert and command-line mode at once, the same way a space
  # covers the three Normal-side modes.
  if entry_mode ==# '!'
    return mode ==# 'i' || mode ==# 'c'
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
def DeriveDescription(entry: dict<any>, mode: string): string
  if get(entry, 'expr', 0)
    return 'expr: ' .. get(entry, 'rhs', '')
  endif
  # A mapping onto one of Vim's own prefixed commands already has a name in
  # the built-in tables, and that name is better than its keys: '<leader>w='
  # reads as 'equalize-sizes' rather than as '<C-W>='.
  if Flag('simplewhichkey_derive', 1)
    var builtin = get(simplewhichkey#builtin#Table(mode),
      simplewhichkey#keys#Termcodes(get(entry, 'rhs', '')), '')
    if !empty(builtin)
      return builtin
    endif
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

# Buffer-scoped registries beat the global ones, so an ftplugin can name the
# keys it installs without knowing what the rest of the configuration called
# them.  They are dictionaries of the same shape, written by Describe() with
# its buffer argument rather than by hand, because the keys are raw.
def Registered(mode: string, sequence: string): string
  var local = get(b:, 'simplewhichkey_descriptions', {})
  if type(local) == v:t_dict
    var text = get(get(local, mode, {}), sequence, '')
    if !empty(text)
      return text
    endif
  endif
  return get(get(descriptions, mode, {}), sequence, '')
enddef

def RegisteredGroup(mode: string, sequence: string): string
  var local = get(b:, 'simplewhichkey_groups', {})
  if type(local) == v:t_dict
    var name = get(get(local, mode, {}), sequence, '')
    if !empty(name)
      return name
    endif
  endif
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
#
# With {buffer} true the names live on the current buffer instead, which is
# what an ftplugin wants: the same key means something else in another
# filetype, and a global registry cannot say so.
export def Describe(spec: dict<string>, mode: string = 'n', buffer: bool = false)
  if buffer
    if type(get(b:, 'simplewhichkey_descriptions', 0)) != v:t_dict
      b:simplewhichkey_descriptions = {}
    endif
    if type(get(b:, 'simplewhichkey_groups', 0)) != v:t_dict
      b:simplewhichkey_groups = {}
    endif
    # Each dict answers for itself.  An ftplugin resetting its own names has
    # nothing but |:unlet| to do it with, and it may well unlet one of the
    # two: keying the second off the first would then write into a dict that
    # has no entry for this mode.
    if !has_key(b:simplewhichkey_descriptions, mode)
      b:simplewhichkey_descriptions[mode] = {}
    endif
    if !has_key(b:simplewhichkey_groups, mode)
      b:simplewhichkey_groups[mode] = {}
    endif
  elseif !has_key(descriptions, mode)
    descriptions[mode] = {}
    group_names[mode] = {}
  endif
  for [notation, description] in items(spec)
    var sequence = simplewhichkey#keys#Termcodes(notation)
    var into = description =~# '^+'
      ? (buffer ? b:simplewhichkey_groups[mode] : group_names[mode])
      : (buffer ? b:simplewhichkey_descriptions[mode] : descriptions[mode])
    into[sequence] = description
  endfor
enddef

# Drops the global registry only: buffer-scoped names belong to the buffer and
# die with it.
export def Forget()
  descriptions = {}
  group_names = {}
enddef

# ---------------------------------------------------------------------------
# One level of the key tree
# ---------------------------------------------------------------------------

def AddNode(level: dict<any>, key: string, description: string, group: bool, source: string, below: string = '')
  if !has_key(level, key)
    level[key] = {
      label: simplewhichkey#keys#Label(key),
      desc: '',
      group: false,
      count: 0,
      source: source,
      below: [],
    }
  endif
  var node = level[key]
  if group
    node.group = true
    node.count += 1
    # What the mappings under this key are called, kept so an unnamed group
    # can be named after them instead of counted.
    if !empty(below)
      add(node.below, below)
    endif
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
    for entry in Mappings()
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
      var derived = DeriveDescription(entry, mode)
      AddNode(level, key, leaf ? derived : '', !leaf, 'map', leaf ? '' : derived)
    endfor
  endfor
enddef

# The longest beginning every text shares, cut back to a word boundary so a
# half-word ('SimpleGitSta') can never become a name.  Word starts are capital
# letters and anything after a separator, which covers both CamelCase command
# names and 'git status' style ones.
def SharedPrefix(texts: list<string>): string
  if len(texts) < 2
    return ''
  endif
  var shared = strchars(texts[0])
  for text in texts[1 : ]
    if empty(text)
      return ''
    endif
    var index = 0
    while index < shared && index < strchars(text)
          && strcharpart(texts[0], index, 1) ==# strcharpart(text, index, 1)
      index += 1
    endwhile
    shared = index
    if shared == 0
      return ''
    endif
  endfor
  var chars = split(texts[0], '\zs')
  var cut = 0
  if shared == len(chars)
    # The whole of this name is what the others begin with, so it is already
    # a word boundary and the name is all of it: ':SimpleGit' in front of
    # ':SimpleGitStatusExtra' is 'SimpleGit', not 'Simple'.
    cut = shared
  else
    for index in range(1, min([shared, len(chars) - 1]))
      if chars[index] =~# '\u' || chars[index - 1] =~# '[^0-9A-Za-z]'
        cut = index
      endif
    endfor
  endif
  var prefix = substitute(strcharpart(texts[0], 0, cut), '[^0-9A-Za-z]\+$', '', '')
  # A name has to dominate what it names.  'echo' in front of two different
  # :echo commands is a shared beginning, not a subject; 'SimpleGit' in front
  # of SimpleGitStatus and SimpleGitDiff is the subject.
  var shortest = strchars(texts[0])
  for text in texts
    shortest = min([shortest, strchars(text)])
  endfor
  if strchars(prefix) < 3 || strchars(prefix) * 2 < shortest
    return ''
  endif
  return prefix
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
    DropAliases(level, mode, sequence)
  endif

  for [key, node] in items(level)
    var full = sequence .. key
    if node.group
      var name = RegisteredGroup(mode, full)
      if !empty(name)
        node.desc = name
      elseif empty(node.desc)
        # '+N keys' says how much is behind the key and nothing about what.
        # When every mapping under it is named after the same thing, that
        # shared beginning is the name a user would have written by hand.
        var derived = Flag('simplewhichkey_derive', 1)
          ? SharedPrefix(node.below) : ''
        node.desc = empty(derived)
          ? printf('+%d keys', node.count) : '+' .. derived
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
#
# Running first has its own trap, so the registry is still consulted here, for
# one question only: naming the Ctrl form itself.  Describing '<C-w><C-v>' says
# that key is wanted, and dropping it anyway would accept the registration and
# then throw it away with no diagnostic at all.
def DropAliases(level: dict<any>, mode: string, sequence: string)
  var described: dict<bool> = {}
  for [key, node] in items(level)
    if node.source ==# 'builtin' && node.label !~# '^<C-'
      described[node.desc] = true
    endif
  endfor
  for [key, node] in items(level)
    if node.source !=# 'builtin' || node.label !~# '^<C-'
          || !get(described, node.desc, false)
      continue
    endif
    var full = sequence .. key
    if !empty(Registered(mode, full)) || !empty(RegisteredGroup(mode, full))
      continue
    endif
    remove(level, key)
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
  for entry in Mappings()
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
      elseif index(EXPR_MODES, mode) >= 0
        execute printf(
          '%s <silent> <expr> %s simplewhichkey#InsertHook(%s, %s)',
          MapCommand(mode), lhs, string(lhs), string(mode))
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
    if index(['n', 'x', 'o', 'i', 'c'], mode) < 0 || type(prefixes) != v:t_list
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
  for entry in Mappings()
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
    var qualifies = key =~# '^[nxoic]:'
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
  # Nothing installs or removes a mapping between here and the choice, so one
  # sweep answers every Level() and Ambiguous() of the whole session.
  OpenSnapshot()
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
    # Before the caller suspends hooks, which is a change to the very table
    # the snapshot froze.
    CloseSnapshot()
  endtry

  return {aborted: aborted, sequence: sequence}
enddef

# Reasons never to interrupt with a panel while text is being typed.  A live
# completion menu is state a redraw would disturb; a register being replayed is
# a machine rather than a person pausing to think; and keys already queued
# behind the prefix -- the rest of a mapping, a :normal or a feedkeys() -- are
# about to answer the panel's question themselves.
#
# Vim reports queued keys, not where a key came from: state('m') is empty as
# soon as the prefix is the *last* key of a mapping or a feedkeys(), and
# nothing distinguishes that from a person pressing the same key.  There the
# panel does open, which is also what Vim does with the prefix either way --
# CTRL-R and CTRL-X both wait for the next key.  reg_executing() is the one
# origin Vim does report, so a register keeps its native speed to its last key.
def Occupied(mode: string): bool
  if mode !=# 'i' && mode !=# 'c'
    return false
  endif
  return pumvisible() || !empty(reg_executing()) || !empty(state('m'))
enddef

# The body every <expr> hook shares.  Selection happens while Vim's own state
# is still live -- a pending operator, a half-written line -- and the chosen
# keys are returned rather than fed, so that state is never reconstructed.
def ExprHook(prefix: string, mode: string): string
  var raw_prefix = simplewhichkey#keys#Termcodes(prefix)
  if empty(raw_prefix)
    return ''
  endif
  # One snapshot covers both the "is anything listed here" question and the
  # session that follows, so a prefix costs one sweep rather than two.
  var selected: dict<any> = {}
  OpenSnapshot()
  try
    if !Flag('simplewhichkey_enable', 1) || active || Occupied(mode)
          \ || empty(Level(mode, raw_prefix))
      selected = {}
    else
      selected = SelectSequence(raw_prefix, mode)
    endif
  finally
    CloseSnapshot()
  endtry
  if empty(selected)
    Suspend(mode)
    ScheduleRestore()
    return IGNORE_KEY .. raw_prefix
  endif
  if selected.aborted
    # Esc cancels the pending operator, which is what was asked for.  While
    # typing, the same key would leave Insert mode or throw away the command
    # line, so there the panel just goes away and the prefix is dropped.
    return mode ==# 'o' ? ESCAPE_KEY : ''
  endif
  # A recursive expr mapping normally suppresses remapping of its first result
  # byte to prevent self-recursion. <Ignore> forms a harmless boundary; after
  # the hook is removed, the complete returned sequence can resolve user
  # mappings, <Plug> targets and expr mappings exactly as typed.
  Suspend(mode)
  ScheduleRestore()
  return IGNORE_KEY .. selected.sequence
enddef

# Called as an operator-pending <expr> mapping. Vim retains the exact
# operator/count/register state across the selection.
export def OperatorHook(prefix: string): string
  return ExprHook(prefix, 'o')
enddef

# Called as an Insert or command-line <expr> mapping.  The same contract: the
# text typed so far, the cursor and the command line are Vim's, untouched.
export def InsertHook(prefix: string, mode: string): string
  return ExprHook(prefix, mode)
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
  # One snapshot covers that question and the session that follows; it is
  # closed before Feed(), which suspends hooks and so changes the table.
  var selected: dict<any> = {}
  OpenSnapshot()
  try
    if !Flag('simplewhichkey_enable', 1) || active
          \ || empty(Level(mode, raw_prefix))
      selected = {aborted: false, sequence: raw_prefix}
    else
      selected = SelectSequence(raw_prefix, mode)
    endif
  finally
    CloseSnapshot()
  endtry
  if selected.aborted
    return
  endif
  Feed(replay_head .. selected.sequence, mode)
enddef

# What the panel would list for a prefix, without opening it.  Useful to check
# a configuration ( :echo simplewhichkey#Keys('n', '<C-w>') ) and in tests.
export def Keys(mode: string, prefix: string): dict<any>
  var out: dict<any> = {}
  OpenSnapshot()
  try
    for [key, node] in items(Level(mode, simplewhichkey#keys#Termcodes(prefix)))
      out[simplewhichkey#keys#Label(key)] = {
        desc: node.desc,
        group: node.group,
        source: node.source,
      }
    endfor
  finally
    CloseSnapshot()
  endtry
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
# The whole tree
# ---------------------------------------------------------------------------

# The panel answers "what may follow this key", one level at a time, which is
# the right question while typing and the wrong one while configuring: you
# cannot grep a popup, and nothing else in Vim can print a keymap that mixes
# built-in commands with your mappings.  Tree() walks the same Level() the
# panel draws and returns it flat.
#
# Depth is bounded because the tree is not: '"' leads to the registers, a
# register name leads nowhere, but a mistaken group could recurse as deep as
# the sequence can grow.
def ListDepth(requested: number): number
  if requested > 0
    return min([requested, 16])
  endif
  var configured = get(g:, 'simplewhichkey_list_depth', 4)
  if type(configured) != v:t_number || configured <= 0
    return 4
  endif
  return min([configured, 16])
enddef

def Walk(mode: string, sequence: string, remaining: number, out: list<dict<any>>)
  if remaining <= 0
    return
  endif
  var nodes: list<dict<any>> = []
  for [key, node] in items(Level(mode, sequence))
    add(nodes, extend(copy(node), {key: key}))
  endfor
  for node in simplewhichkey#panel#SortEntries(nodes)
    var full = sequence .. node.key
    add(out, {
      keys: simplewhichkey#keys#Label(full),
      label: node.label,
      desc: node.desc,
      group: node.group,
      source: node.source,
    })
    if node.group
      Walk(mode, full, remaining - 1, out)
    endif
  endfor
enddef

# Every sequence reachable under {prefix}, depth first, in the panel's own
# order.  With no prefix, every hooked prefix of that mode in turn.
export def Tree(mode: string = 'n', prefix: string = '', depth: number = 0): list<dict<any>>
  var limit = ListDepth(depth)
  var out: list<dict<any>> = []
  # A walk touches Level() once per group; without one snapshot around the
  # whole thing that is one sweep of every mapping in the editor per group.
  OpenSnapshot()
  try
    if !empty(prefix)
      Walk(mode, simplewhichkey#keys#Termcodes(prefix), limit, out)
      return out
    endif
    for lhs in get(hooks, mode, [])
      var raw = simplewhichkey#keys#Termcodes(lhs)
      var level = Level(mode, raw)
      if empty(level)
        continue
      endif
      var name = RegisteredGroup(mode, raw)
      add(out, {
        keys: simplewhichkey#keys#Label(raw),
        label: simplewhichkey#keys#Label(raw),
        desc: empty(name) ? printf('+%d keys', len(level)) : name,
        group: true,
        source: 'prefix',
      })
      Walk(mode, raw, limit, out)
    endfor
  finally
    CloseSnapshot()
  endtry
  return out
enddef

# Completion for the commands that take a mode.  Only the modes something is
# actually hooked in are offered, so the list never suggests an empty answer.
export def CompleteMode(lead: string, _: string, _2: number): list<string>
  var out: list<string> = []
  for mode in ['n', 'x', 'o', 'i', 'c']
    if !empty(get(hooks, mode, [])) && stridx(mode, lead) == 0
      add(out, mode)
    endif
  endfor
  return out
enddef

# :SimpleWhichKeyList [mode] and :SimpleWhichKeyList! [mode]
export def List(mode_argument: string, to_quickfix: bool)
  var mode = empty(mode_argument) ? 'n' : mode_argument
  if index(['n', 'x', 'o', 'i', 'c'], mode) < 0
    Notify('unknown mode: ' .. mode .. ' (use n, x, o, i or c)')
    return
  endif
  var rows = Tree(mode)
  if empty(rows)
    Notify('nothing is hooked in mode ' .. mode)
    return
  endif
  if to_quickfix
    setqflist([], ' ', {
      title: 'SimpleWhichKey ' .. mode,
      items: mapnew(rows, (_, row) => ({
        text: printf('%s\t%s', row.keys, row.desc),
      })),
    })
    copen
    return
  endif
  var key_width = 0
  var desc_width = 0
  for row in rows
    key_width = max([key_width, strdisplaywidth(row.keys)])
    desc_width = max([desc_width, strdisplaywidth(row.desc)])
  endfor
  var lines = [
    printf('" SimpleWhichKey: mode %s, %d sequences, depth %d',
      mode, len(rows), ListDepth(0)),
    '" Search with /, close with :q',
    '',
  ]
  for row in rows
    # Pad by display width, not by character count: a description may hold
    # register contents, and those are whatever the buffer held.
    add(lines, printf('%s%s  %s%s  %s',
      row.keys, repeat(' ', max([0, key_width - strdisplaywidth(row.keys)])),
      row.desc, repeat(' ', max([0, desc_width - strdisplaywidth(row.desc)])),
      row.source))
  endfor
  new
  setline(1, lines)
  setlocal buftype=nofile bufhidden=wipe noswapfile nomodified nomodifiable
  setlocal filetype=simplewhichkeylist
  cursor(1, 1)
enddef

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

# Every distinct user mapping in a mode, raw, with the plugin's own hooks left
# out.  Both reports below start from this one sweep.
def UserMappings(mode: string): list<string>
  var seen: dict<bool> = {}
  for entry in Mappings()
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
  OpenSnapshot()
  defer CloseSnapshot()
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
  for entry in Mappings()
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
  OpenSnapshot()
  defer CloseSnapshot()
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
