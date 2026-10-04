vim9script

# =============================================================================
# Key representation.
#
# Everything the user writes -- prefixes in the configuration, the built-in
# description tables, keys in a registered description dictionary -- is written
# in Vim's key notation ('<C-w>', '<Space>', 'g').  Everything Vim hands back at
# runtime -- getcharstr(), maplist()'s 'lhsraw' -- is raw key codes.  Only the
# raw form can be compared reliably, so notation is translated once on the way
# in and the raw form is translated back with keytrans() only for display.
# =============================================================================

# K_SPECIAL introduces a three byte encoded key; 0xfc marks a modifier, and the
# modifier is followed by the key it applies to.
const K_SPECIAL = "\x80"
const KS_MODIFIER = "\xfc"

def SpecialKey(name: string): string
  try
    return eval('"\<' .. name .. '>"')
  catch
    # Not a key name Vim knows: keep the text as typed.
    return '<' .. name .. '>'
  endtry
enddef

# Translate key notation to raw key codes.  '<leader>' and '<localleader>' are
# expanded first because Vim itself only does that while parsing :map.
export def Termcodes(notation: string): string
  if empty(notation)
    return ''
  endif
  var text = notation
  var leader = get(g:, 'mapleader', '\')
  var localleader = get(g:, 'maplocalleader', '\')
  if type(leader) == v:t_number
    leader = leader >= 0 && leader < 256 ? nr2char(leader) : '\'
  endif
  if type(localleader) == v:t_number
    localleader = localleader >= 0 && localleader < 256 ? nr2char(localleader) : '\'
  endif
  if type(leader) == v:t_string
    text = substitute(text, '\c<leader>', escape(leader, '\&~'), 'g')
  endif
  if type(localleader) == v:t_string
    text = substitute(text, '\c<localleader>', escape(localleader, '\&~'), 'g')
  endif
  return substitute(
    text,
    '<[^<>]\+>',
    (match) => SpecialKey(strpart(match[0], 1, strlen(match[0]) - 2)),
    'g')
enddef

# The first whole key of a raw key sequence.  Multi-byte characters and the
# three byte K_SPECIAL encodings both have to stay in one piece, otherwise a
# sequence like <C-w> would be split into meaningless bytes.
export def First(raw: string): string
  if empty(raw)
    return ''
  endif
  if strpart(raw, 0, 1) ==# K_SPECIAL
    if strlen(raw) < 3
      return raw
    endif
    var head = strpart(raw, 0, 3)
    if strpart(raw, 1, 1) ==# KS_MODIFIER
      # A modifier on its own is not a key; the real key follows it.
      return head .. First(strpart(raw, 3))
    endif
    return head
  endif
  var char = strcharpart(raw, 0, 1)
  return empty(char) ? strpart(raw, 0, 1) : char
enddef

export def Split(raw: string): list<string>
  var result: list<string> = []
  var rest = raw
  while !empty(rest)
    var key = First(rest)
    if empty(key)
      break
    endif
    add(result, key)
    rest = strpart(rest, strlen(key))
  endwhile
  return result
enddef

# True when 'raw' begins with 'prefix' and has at least one key left.
export def StartsWith(raw: string, prefix: string): bool
  return strlen(raw) > strlen(prefix) && strpart(raw, 0, strlen(prefix)) ==# prefix
enddef

export def Label(raw: string): string
  if empty(raw)
    return ''
  endif
  return keytrans(raw)
enddef

# Mouse and scroll events arrive through getcharstr() like any other key.  They
# are never part of a mapping, so the panel ignores them instead of treating
# them as a choice.
export def IsMouse(raw: string): bool
  return Label(raw) =~? 'mouse\|scrollwheel\|drag\|release'
enddef


# Mouse events were already consumed by the panel rather than replayed.  Give
# vertical (and tilt-wheel horizontal) scroll events a useful meaning without
# reserving any keyboard key that could be part of a user's mapping.
export def ScrollDirection(raw: string): number
  var label = Label(raw)
  if label =~? '^<ScrollWheel\(Up\|Left\)>$'
    return -1
  endif
  if label =~? '^<ScrollWheel\(Down\|Right\)>$'
    return 1
  endif
  return 0
enddef

# Keyboard fallback for terminals where 'mouse' is empty.  The caller only
# treats these as paging controls when the current which-key level does not
# itself define that key, so an explicit mapping always wins.
export def PageDirection(raw: string): number
  var label = Label(raw)
  if label ==# '<PageUp>'
    return -1
  endif
  if label ==# '<PageDown>'
    return 1
  endif
  return 0
enddef
