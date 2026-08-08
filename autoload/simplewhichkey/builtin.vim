vim9script

# =============================================================================
# Descriptions for Vim's own prefixed commands.
#
# Mappings can be discovered with maplist(); Vim's built-in commands cannot --
# <C-w>v, gU or zt are not mappings, so nothing in the editor can enumerate
# them.  These tables are that missing half: without them a panel for <C-w>
# would come up empty on a configuration that maps nothing under it.
#
# Keys are written in notation and translated once, on first use.  Registers
# and marks are listed by the providers at the bottom instead, because their
# contents change while Vim runs.
# =============================================================================

const WINDOW = {
  's': 'split-horizontal',
  '<C-s>': 'split-horizontal',
  'S': 'split-horizontal',
  'v': 'split-vertical',
  '<C-v>': 'split-vertical',
  'n': 'new-window',
  '<C-n>': 'new-window',
  '^': 'split-alternate-file',
  '<C-^>': 'split-alternate-file',
  'q': 'quit-window',
  '<C-q>': 'quit-window',
  'c': 'close-window',
  'o': 'only-this-window',
  '<C-o>': 'only-this-window',
  'w': 'next-window',
  '<C-w>': 'next-window',
  'W': 'previous-window',
  'p': 'last-accessed-window',
  '<C-p>': 'last-accessed-window',
  'P': 'preview-window',
  'r': 'rotate-downwards',
  '<C-r>': 'rotate-downwards',
  'R': 'rotate-upwards',
  'x': 'exchange-window',
  '<C-x>': 'exchange-window',
  'h': 'go-left',
  'j': 'go-down',
  'k': 'go-up',
  'l': 'go-right',
  't': 'go-top-left',
  'b': 'go-bottom-right',
  'H': 'move-window-far-left',
  'J': 'move-window-far-bottom',
  'K': 'move-window-far-top',
  'L': 'move-window-far-right',
  'T': 'move-window-to-new-tab',
  '=': 'equalize-sizes',
  '+': 'increase-height',
  '-': 'decrease-height',
  '<': 'decrease-width',
  '>': 'increase-width',
  '_': 'maximize-height',
  '|': 'maximize-width',
  'f': 'split-file-under-cursor',
  'F': 'split-file-under-cursor-at-line',
  'i': 'split-declaration-of-word',
  'd': 'split-definition-of-word',
  'D': 'split-declaration-of-word',
  ']': 'split-tag-under-cursor',
  '<C-]>': 'split-tag-under-cursor',
  '}': 'preview-tag-under-cursor',
  'z': 'close-preview-window',
  ':': 'command-line',
  'g': '+goto',
  'gf': 'tab-file-under-cursor',
  'gF': 'tab-file-under-cursor-at-line',
  'gt': 'next-tab',
  'gT': 'previous-tab',
  'g]': 'tab-tag-select',
  'g<C-]>': 'tab-tag-jump',
  'g}': 'preview-tag-jump',
}

const GOTO_NORMAL = {
  'g': 'first-line',
  'a': 'show-character-code',
  '8': 'show-utf8-bytes',
  '?': 'rot13',
  '&': 'repeat-substitute-on-all-lines',
  '@': 'operatorfunc',
  ';': 'older-change-position',
  ',': 'newer-change-position',
  'i': 'insert-at-last-insert',
  'I': 'insert-at-column-one',
  'J': 'join-without-space',
  'v': 'reselect-last-visual',
  'u': 'lowercase-operator',
  'U': 'uppercase-operator',
  '~': 'swap-case-operator',
  'q': 'format-operator',
  'w': 'format-operator-keep-cursor',
  'd': 'local-declaration',
  'D': 'global-declaration',
  'f': 'edit-file-under-cursor',
  'F': 'edit-file-under-cursor-at-line',
  'x': 'open-file-or-url-under-cursor',
  '_': 'last-non-blank-of-line',
  '0': 'first-screen-column',
  '^': 'first-screen-non-blank',
  '$': 'last-screen-column',
  'm': 'middle-of-screen-line',
  'M': 'middle-of-text-line',
  'e': 'end-of-previous-word',
  'E': 'end-of-previous-WORD',
  'j': 'down-one-screen-line',
  'k': 'up-one-screen-line',
  'n': 'select-next-search-match',
  'N': 'select-previous-search-match',
  'o': 'go-to-byte-offset',
  'p': 'paste-cursor-after',
  'P': 'paste-cursor-after',
  'r': 'virtual-replace-char',
  'R': 'virtual-replace-mode',
  's': 'sleep',
  't': 'next-tab',
  'T': 'previous-tab',
  '<C-]>': 'tag-jump-select',
  ']': 'tag-select',
  '*': 'search-word-under-cursor-partial',
  '#': 'search-word-under-cursor-partial-backwards',
  '<': 'show-previous-output',
  'O': 'file-outline',
}

const GOTO_VISUAL = {
  'u': 'lowercase',
  'U': 'uppercase',
  '~': 'swap-case',
  '?': 'rot13',
  'q': 'format',
  'w': 'format-keep-cursor',
  'J': 'join-without-space',
  'v': 'swap-with-previous-selection',
  'f': 'edit-file-under-cursor',
  'x': 'open-file-or-url-under-cursor',
  '<C-a>': 'increment-sequence',
  '<C-x>': 'decrement-sequence',
  'I': 'block-insert-at-column',
  'A': 'block-append-at-column',
  '_': 'last-non-blank-of-line',
  '0': 'first-screen-column',
  '$': 'last-screen-column',
  'e': 'end-of-previous-word',
  'j': 'down-one-screen-line',
  'k': 'up-one-screen-line',
  'n': 'extend-to-next-search-match',
  'N': 'extend-to-previous-search-match',
}

# `g` motions accepted while an operator is pending. Commands that are only
# valid in Normal/Visual mode deliberately stay out: advertising one would be
# worse than omitting it because the replay is left entirely to Vim.
const GOTO_OPERATOR = {
  'g': 'first-line',
  'e': 'previous-word-end',
  'E': 'previous-WORD-end',
  '_': 'last-non-blank',
  '0': 'first-screen-column',
  '<Home>': 'first-screen-column',
  '^': 'first-screen-non-blank',
  '$': 'last-screen-column',
  '<End>': 'last-screen-column',
  'm': 'middle-screen-column',
  'M': 'middle-text-column',
  'j': 'down-one-screen-line',
  'k': 'up-one-screen-line',
}

const FOLD_SCROLL = {
  'f': 'create-fold-operator',
  'F': 'create-fold-for-lines',
  'd': 'delete-fold',
  'D': 'delete-folds-recursively',
  'E': 'delete-all-folds',
  'a': 'toggle-fold',
  'A': 'toggle-fold-recursively',
  'o': 'open-fold',
  'O': 'open-fold-recursively',
  'c': 'close-fold',
  'C': 'close-fold-recursively',
  'v': 'view-cursor-line',
  'x': 'update-folds',
  'X': 'reapply-folds',
  'm': 'fold-more',
  'M': 'close-all-folds',
  'r': 'fold-less',
  'R': 'open-all-folds',
  'i': 'toggle-foldenable',
  'j': 'move-to-fold-start',
  'k': 'move-to-fold-end',
  'n': 'folds-off',
  'N': 'folds-on',
  't': 'cursor-line-to-top',
  'z': 'cursor-line-to-center',
  'b': 'cursor-line-to-bottom',
  '<CR>': 'cursor-line-to-top-first-non-blank',
  '.': 'cursor-line-to-center-first-non-blank',
  '-': 'cursor-line-to-bottom-first-non-blank',
  '+': 'next-page',
  '^': 'previous-page',
  'h': 'scroll-left',
  'l': 'scroll-right',
  'H': 'scroll-half-screen-left',
  'L': 'scroll-half-screen-right',
  's': 'scroll-to-line-start',
  'e': 'scroll-to-line-end',
  '=': 'spelling-suggestions',
  'g': 'spell-add-good-word',
  'G': 'spell-add-good-word-internal',
  'w': 'spell-add-wrong-word',
  'W': 'spell-add-wrong-word-internal',
  'u': '+spell-undo',
  'ug': 'spell-undo-good-word',
  'uG': 'spell-undo-good-word-internal',
  'uw': 'spell-undo-wrong-word',
  'uW': 'spell-undo-wrong-word-internal',
}

const BRACKET_BACKWARD = {
  '[': 'previous-section-start',
  ']': 'previous-section-end',
  '(': 'previous-unmatched-paren',
  '{': 'previous-unmatched-brace',
  'm': 'previous-method-start',
  'M': 'previous-method-end',
  '#': 'previous-unmatched-if',
  '*': 'previous-comment-start',
  '/': 'previous-comment-start',
  'c': 'previous-diff-change',
  'd': 'show-first-define',
  'D': 'list-defines',
  '<C-d>': 'jump-to-first-define',
  'i': 'show-first-identifier',
  'I': 'list-identifiers',
  '<C-i>': 'jump-to-first-identifier',
  'p': 'paste-before-with-indent',
  'P': 'paste-before-with-indent',
  's': 'previous-spelling-error',
  'z': 'move-to-fold-start',
  "'": 'previous-lowercase-mark',
  '`': 'previous-lowercase-mark',
  'f': 'previous-file-in-directory',
}

const BRACKET_FORWARD = {
  ']': 'next-section-start',
  '[': 'next-section-end',
  ')': 'next-unmatched-paren',
  '}': 'next-unmatched-brace',
  'm': 'next-method-start',
  'M': 'next-method-end',
  '#': 'next-unmatched-endif',
  '*': 'next-comment-end',
  '/': 'next-comment-end',
  'c': 'next-diff-change',
  'd': 'show-next-define',
  'D': 'list-defines-below',
  '<C-d>': 'jump-to-next-define',
  'i': 'show-next-identifier',
  'I': 'list-identifiers-below',
  '<C-i>': 'jump-to-next-identifier',
  'p': 'paste-after-with-indent',
  'P': 'paste-after-with-indent',
  's': 'next-spelling-error',
  'z': 'move-to-fold-end',
  "'": 'next-lowercase-mark',
  '`': 'next-lowercase-mark',
  'f': 'next-file-in-directory',
}

# Only entries Vim accepts as motions belong in operator-pending panels.
# Display/list/paste/file commands from the Normal-mode tables are omitted: a
# pending operator cannot consume them as its motion.
const BRACKET_BACKWARD_OPERATOR = {
  '[': 'previous-section-start',
  ']': 'previous-section-end',
  '(': 'previous-unmatched-paren',
  '{': 'previous-unmatched-brace',
  'm': 'previous-method-start',
  'M': 'previous-method-end',
  '#': 'previous-unmatched-if',
  '*': 'previous-comment-start',
  '/': 'previous-comment-start',
  'c': 'previous-diff-change',
  's': 'previous-spelling-error',
  'z': 'move-to-fold-start',
  "'": 'previous-lowercase-mark',
  '`': 'previous-lowercase-mark',
}

const BRACKET_FORWARD_OPERATOR = {
  ']': 'next-section-start',
  '[': 'next-section-end',
  ')': 'next-unmatched-paren',
  '}': 'next-unmatched-brace',
  'm': 'next-method-start',
  'M': 'next-method-end',
  '#': 'next-unmatched-endif',
  '*': 'next-comment-end',
  '/': 'next-comment-end',
  'c': 'next-diff-change',
  's': 'next-spelling-error',
  'z': 'move-to-fold-end',
  "'": 'next-lowercase-mark',
  '`': 'next-lowercase-mark',
}

const QUIT = {
  'Z': 'write-and-quit',
  'Q': 'quit-without-writing',
}

# Text objects.  These exist only in Visual and Operator-pending mode, which is
# also why they are the most forgotten half of Vim's grammar: `d` shows nothing
# and there is no way to ask.  Vim gives most blocks two or three interchangeable
# keys (i( == i) == ib) and all of them are listed, because the point of the
# panel is to reach the one you happen to remember.
const TEXTOBJECT_INNER = {
  'w': 'inner-word',
  'W': 'inner-WORD',
  's': 'inner-sentence',
  'p': 'inner-paragraph',
  '(': 'inner-parenthesised',
  ')': 'inner-parenthesised',
  'b': 'inner-parenthesised',
  '{': 'inner-braced',
  '}': 'inner-braced',
  'B': 'inner-braced',
  '[': 'inner-bracketed',
  ']': 'inner-bracketed',
  '<': 'inner-angled',
  '>': 'inner-angled',
  't': 'inner-tag-block',
  '"': 'inner-double-quoted',
  "'": 'inner-single-quoted',
  '`': 'inner-backtick-quoted',
}

# The `a` forms take the delimiters with them, and the word/sentence/paragraph
# forms take the white space that follows.
const TEXTOBJECT_AROUND = {
  'w': 'a-word-with-white-space',
  'W': 'a-WORD-with-white-space',
  's': 'a-sentence-with-white-space',
  'p': 'a-paragraph-with-blank-lines',
  '(': 'a-parenthesised-block',
  ')': 'a-parenthesised-block',
  'b': 'a-parenthesised-block',
  '{': 'a-braced-block',
  '}': 'a-braced-block',
  'B': 'a-braced-block',
  '[': 'a-bracketed-block',
  ']': 'a-bracketed-block',
  '<': 'an-angled-block',
  '>': 'an-angled-block',
  't': 'a-tag-block',
  '"': 'a-double-quoted-string',
  "'": 'a-single-quoted-string',
  '`': 'a-backtick-quoted-string',
}

# prefix notation -> {mode -> {relative notation -> description}}
const TABLES = {
  '<C-w>': {n: WINDOW},
  'g': {n: GOTO_NORMAL, x: GOTO_VISUAL, o: GOTO_OPERATOR},
  'z': {n: FOLD_SCROLL, x: FOLD_SCROLL},
  '[': {n: BRACKET_BACKWARD, x: BRACKET_BACKWARD, o: BRACKET_BACKWARD_OPERATOR},
  ']': {n: BRACKET_FORWARD, x: BRACKET_FORWARD, o: BRACKET_FORWARD_OPERATOR},
  'Z': {n: QUIT},
  # No Normal-mode entry: `i` and `a` there start Insert mode, not a text
  # object, and hooking them would be a different feature entirely.
  'i': {x: TEXTOBJECT_INNER, o: TEXTOBJECT_INNER},
  'a': {x: TEXTOBJECT_AROUND, o: TEXTOBJECT_AROUND},
}

# mode -> raw sequence -> description, built on first use.
var cache: dict<dict<string>> = {}

def Build(mode: string): dict<string>
  var table: dict<string> = {}
  for [prefix, per_mode] in items(TABLES)
    var entries = get(per_mode, mode, {})
    if empty(entries)
      continue
    endif
    var raw_prefix = simplewhichkey#keys#Termcodes(prefix)
    for [suffix, description] in items(entries)
      table[raw_prefix .. simplewhichkey#keys#Termcodes(suffix)] = description
    endfor
  endfor
  return table
enddef

export def Table(mode: string): dict<string>
  if !has_key(cache, mode)
    cache[mode] = Build(mode)
  endif
  return cache[mode]
enddef

export def Clear()
  cache = {}
enddef

# ---------------------------------------------------------------------------
# Providers for prefixes whose contents only exist at runtime.
# ---------------------------------------------------------------------------

def Preview(text: string, width: number): string
  var flat = substitute(text, '\n', '⏎', 'g')
  flat = substitute(flat, '\t', ' ', 'g')
  flat = substitute(flat, '[[:cntrl:]]', '.', 'g')
  if strchars(flat) > width
    return strcharpart(flat, 0, width - 1) .. '…'
  endif
  return flat
enddef

def Registers(): dict<string>
  var out: dict<string> = {}
  for name in split('"0123456789-abcdefghijklmnopqrstuvwxyz.:%#=*+~/', '\zs')
    var info = getreginfo(name)
    var body = join(get(info, 'regcontents', []), '\n')
    if empty(body)
      continue
    endif
    out[name] = Preview(body, 30)
  endfor
  return out
enddef

def Marks(): dict<string>
  var out: dict<string> = {}
  for mark in getmarklist(bufnr())
    var name = substitute(mark.mark, '^''', '', '')
    out[name] = printf('line %d, col %d', mark.pos[1], mark.pos[2])
  endfor
  for mark in getmarklist()
    var name = substitute(mark.mark, '^''', '', '')
    out[name] = fnamemodify(get(mark, 'file', ''), ':~:.') .. ':' .. mark.pos[1]
  endfor
  return out
enddef

# Children of a prefix that has to be listed from Vim's current state.  Returns
# an empty dict for every other prefix.
export def Dynamic(mode: string, sequence: string): dict<string>
  if sequence ==# '"'
    return Registers()
  endif
  if sequence ==# "'" || sequence ==# '`'
    return Marks()
  endif
  return {}
enddef
