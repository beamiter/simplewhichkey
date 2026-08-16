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

# Insert and command-line mode have exactly two prefixes worth hinting, and
# both are pure built-in commands that no mapping can enumerate.
#
# CTRL-R takes a register name.  Its three CTRL sub-forms change how the text
# lands -- literally, as if typed, or reindented -- and then take a register
# name as well, so they are groups: the register list follows them too.  '='
# is the odd one out, a leaf that opens the expression command line.
const INSERT_REGISTER = {
  '<C-r>': '+insert-literally',
  '<C-o>': '+insert-as-typed',
  '<C-p>': '+insert-and-fix-indent',
  '=': 'expression-register',
}

# CTRL-X selects which kind of completion the next key starts.  Nobody
# remembers more than two of these, which is the whole argument for the panel.
const COMPLETION = {
  '<C-f>': 'file-names',
  '<C-l>': 'whole-lines',
  '<C-n>': 'keywords-next',
  '<C-p>': 'keywords-previous',
  '<C-k>': 'dictionary-words',
  '<C-t>': 'thesaurus-words',
  '<C-i>': 'keywords-in-included-files',
  '<C-]>': 'tags',
  '<C-d>': 'definitions-and-macros',
  '<C-v>': 'vim-command-line',
  '<C-u>': 'user-defined-completefunc',
  '<C-o>': 'omni-completion',
  's': 'spelling-suggestions',
  '<C-s>': 'spelling-suggestions',
  '<C-z>': 'stop-completion',
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
  # CTRL-R means the same thing while typing text and while typing a command
  # line; CTRL-X completion exists in Insert mode only.
  '<C-r>': {i: INSERT_REGISTER, c: INSERT_REGISTER},
  '<C-x>': {i: COMPLETION},
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

# Bytes of register text the previews have taken out of the registers since
# Vim started.  What a register panel costs is this number, and the panel can
# only ever draw thirty characters of each register, so any answer that grows
# with what is stored in them is the bug this counts.  Counted where the text
# is taken rather than where it is flattened, because the two were separate
# regressions: the flattening ran over whole registers, and then the taking
# did.
var scanned = 0

export def Scanned(): number
  return scanned
enddef

# Thirty characters of a register, with the parts that cannot be drawn on one
# line replaced.
#
# The head is cut off before the replacements rather than after, because the
# rest of the register can be a yanked file: three regexps over megabytes, for
# every one of the ~48 registers, ran on every '"' the user pressed.
#
# The cut counts composed characters -- the trailing 1 -- and not the way
# |strchars()| counts by default, because a replacement is one character for
# one character only until a combining mark is involved.  A tab carrying a
# U+0301 is two characters to strcharpart() and one to the regexp engine, which
# matches the base together with its marks: [[:cntrl:]] turns the pair into a
# single '.'.  Cutting between the tab and its mark therefore left a bare tab
# that matched '\t' instead, and the head shrank to fewer characters than it
# was asked for -- a register of forty such pairs previewed as sixteen
# characters with no ellipsis, when the whole of it flattens to forty and the
# ellipsis is the only thing saying there is more.  Cutting on composed
# boundaries keeps the promise the fast path needs: the head flattens to a
# prefix of what the whole register flattens to, and to at least width + 1
# characters of it, which is what decides the ellipsis.
def Preview(text: string, width: number): string
  var head = strcharpart(text, 0, width + 1, 1)
  var flat = substitute(head, '\n', '⏎', 'g')
  flat = substitute(flat, '\t', ' ', 'g')
  flat = substitute(flat, '[[:cntrl:]]', '.', 'g')
  if strchars(flat) > width
    return strcharpart(flat, 0, width - 1) .. '…'
  endif
  return flat
enddef

# The leading `width` composed characters of what the lines flatten to, and no
# more of them.
#
# Preview() cutting first is only half the saving: joining the whole register
# to hand it over rebuilds every byte of it anyway, which is a megabyte copied
# per yanked file, for each of the ~48 registers, to produce thirty characters.
# Measured with seven 150 KB registers, the join alone was 5.7 ms of a 10.5 ms
# panel after the regexps had already been dealt with.
#
# The count is in composed characters, for the reason Preview() explains: the
# regexp engine replaces a base character together with its marks, so a head
# measured any other way can flatten to fewer characters than it promised and
# lose the ellipsis.  One extra character is taken beyond `width` because that
# is what tells Preview() there is more to come.
def Head(lines: list<string>, width: number): string
  var head: list<string> = []
  for line in lines
    # No one line is ever needed beyond `width` characters of it, so the
    # megabyte a yanked file puts on its first line is cut here rather than
    # copied and then thrown away.
    add(head, strcharpart(line, 0, width + 1, 1))
    # Measured on what the pieces join to rather than on the sum of their
    # lengths, because the two differ: a line beginning with a combining mark
    # loses that mark into the newline in front of it, so the sum can promise
    # a character the join does not deliver -- and a head one character short
    # is a preview that drops the ellipsis saying there is more.  Both the
    # pieces and their number are bounded by `width`, so this stays a few
    # hundred characters of work however large the register is.
    if strchars(join(head, "\n"), 1) > width
      break
    endif
  endfor
  var text = join(head, "\n")
  scanned += strlen(text)
  return text
enddef

def Registers(): dict<string>
  var out: dict<string> = {}
  for name in split('"0123456789-abcdefghijklmnopqrstuvwxyz.:%#=*+~/', '\zs')
    var contents = get(getreginfo(name), 'regcontents', [])
    # What `join(contents, "\n")` used to be tested for, decided without
    # building it: only a register with no lines at all, or exactly one empty
    # one, flattens to nothing.  A register of blank lines does not, and it
    # previewed as a row of newline glyphs before this, so it still must.
    if empty(contents) || (len(contents) == 1 && empty(contents[0]))
      continue
    endif
    # A double quoted "\n" is a newline; the single quoted form is a backslash
    # followed by an n, which is what a multi-line register used to preview as
    # -- and it also meant Preview()'s newline pass had nothing to match, so
    # the glyph it exists to draw never appeared.
    out[name] = Preview(Head(contents, 30), 30)
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

# Every Insert/command-line sequence that ends by taking a register name:
# CTRL-R itself and the three sub-forms that only change how the text lands.
def TakesRegisterName(sequence: string): bool
  var base = simplewhichkey#keys#Termcodes('<C-r>')
  if sequence ==# base
    return true
  endif
  for suffix in ['<C-r>', '<C-o>', '<C-p>']
    if sequence ==# base .. simplewhichkey#keys#Termcodes(suffix)
      return true
    endif
  endfor
  return false
enddef

# Children of a prefix that has to be listed from Vim's current state.  Returns
# an empty dict for every other prefix.
export def Dynamic(mode: string, sequence: string): dict<string>
  if mode ==# 'i' || mode ==# 'c'
    # '"' and the mark keys are ordinary text while typing; only CTRL-R reads
    # a register name here.
    return TakesRegisterName(sequence) ? Registers() : {}
  endif
  if sequence ==# '"'
    return Registers()
  endif
  if sequence ==# "'" || sequence ==# '`'
    return Marks()
  endif
  return {}
enddef
