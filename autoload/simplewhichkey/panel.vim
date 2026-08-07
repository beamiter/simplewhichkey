vim9script

# =============================================================================
# The hint panel.
#
# One popup, laid out in columns, redrawn on every level.  It carries no filter
# and no mappings: keys are read by the caller with getcharstr(), so the popup
# is purely a display and can never swallow a keystroke.
# =============================================================================

const PROP_KEY = 'simplewhichkey_key'
const PROP_SEPARATOR = 'simplewhichkey_separator'
const PROP_DESC = 'simplewhichkey_desc'
const PROP_GROUP = 'simplewhichkey_group'

var popup_id = 0
var props_ready = false
var current_level = ''
var current_page = 0
var current_pages = 1
# Page position belongs to a level, not to the popup as a whole. Remember it
# while one key sequence is active so descending into a group and pressing
# <BS> returns to the same slice of a long parent instead of page one.
var pages_by_level: dict<number> = {}

def EnsureProps()
  if props_ready
    return
  endif
  for [name, highlight] in [
      [PROP_KEY, 'SimpleWhichKeyKey'],
      [PROP_SEPARATOR, 'SimpleWhichKeySeparator'],
      [PROP_DESC, 'SimpleWhichKeyDesc'],
      [PROP_GROUP, 'SimpleWhichKeyGroup'],
    ]
    if empty(prop_type_get(name))
      prop_type_add(name, {highlight: highlight})
    endif
  endfor
  props_ready = true
enddef

export def ResetProps()
  for name in [PROP_KEY, PROP_SEPARATOR, PROP_DESC, PROP_GROUP]
    if !empty(prop_type_get(name))
      prop_type_delete(name)
    endif
  endfor
  props_ready = false
enddef

def Truncate(text: string, width: number): string
  if width <= 0
    return ''
  endif
  if strchars(text) <= width
    return text
  endif
  return strcharpart(text, 0, width - 1) .. '…'
enddef

def Pad(text: string, width: number): string
  var missing = width - strdisplaywidth(text)
  return missing > 0 ? text .. repeat(' ', missing) : text
enddef

# Ordinary keys read first, then punctuation, then the <...> keys, which are
# the least likely to be what someone is scanning for.  Within a category the
# order is case insensitive, so 'a' and 'A' stay next to each other.
def Category(label: string): number
  if label =~# '^<.\+>$'
    return 2
  endif
  return label =~# '^[0-9A-Za-z]$' ? 0 : 1
enddef

def SortEntries(entries: list<dict<any>>): list<dict<any>>
  var groups_first = get(g:, 'simplewhichkey_sort', 'key') ==# 'group'
  return sort(copy(entries), (left, right): number => {
    if groups_first && left.group != right.group
      return left.group ? -1 : 1
    endif
    var left_category = Category(left.label)
    var right_category = Category(right.label)
    if left_category != right_category
      return left_category < right_category ? -1 : 1
    endif
    var a = tolower(left.label)
    var b = tolower(right.label)
    if a ==# b
      # Keep a stable, predictable order for keys that differ only in case.
      return left.label < right.label ? -1 : (left.label ==# right.label ? 0 : 1)
    endif
    return a < b ? -1 : 1
  })
enddef

def Cell(entry: dict<any>, key_width: number, desc_width: number, separator: string): dict<any>
  var key = Pad(entry.label, key_width)
  var desc = Truncate(entry.desc, desc_width)
  var text = key .. separator .. desc
  return {
    text: text,
    props: [
      {col: 1, length: strlen(key), type: PROP_KEY},
      {col: strlen(key) + 1, length: strlen(separator), type: PROP_SEPARATOR},
      {
        col: strlen(key) + strlen(separator) + 1,
        length: strlen(desc),
        type: entry.group ? PROP_GROUP : PROP_DESC,
      },
    ],
    width: strdisplaywidth(text),
  }
enddef

const GAP = 2
const MIN_DESC_WIDTH = 10

# Pick a grid.  Start from the width a description would like to have, add
# columns while the panel is taller than it may be, and page only after columns
# run out.  Descriptions shrink before a second page becomes necessary.
def Layout(entries: list<dict<any>>, available: number, requested_page: number): dict<any>
  var separator = get(g:, 'simplewhichkey_separator', ' → ')
  var separator_width = strdisplaywidth(separator)
  var key_width = 0
  var natural_desc = 0
  for entry in entries
    key_width = max([key_width, strdisplaywidth(entry.label)])
    natural_desc = max([natural_desc, strdisplaywidth(entry.desc)])
  endfor
  natural_desc = min([natural_desc, max([MIN_DESC_WIDTH, get(g:, 'simplewhichkey_max_desc_width', 30)])])

  var max_height = get(g:, 'simplewhichkey_max_height', 0)
  if max_height <= 0
    max_height = max([4, &lines / 2 - 2])
  endif
  var total = len(entries)
  var natural_cell = key_width + separator_width + natural_desc
  var min_cell = key_width + separator_width + MIN_DESC_WIDTH
  var max_columns = max([1, (available + GAP) / (min_cell + GAP)])
  var columns = min([max([1, (available + GAP) / (natural_cell + GAP)]), total])
  var height = max([1, (total + columns - 1) / columns])
  while height > max_height && columns < max_columns
    columns += 1
    height = max([1, (total + columns - 1) / columns])
  endwhile

  var cell_width = (available - GAP * (columns - 1)) / columns
  var desc_width = max([MIN_DESC_WIDTH, min([natural_desc, cell_width - key_width - separator_width])])
  cell_width = key_width + separator_width + desc_width

  if height > max_height
    height = max_height
  endif

  # Narrow terminals used to replace everything beyond the first grid with a
  # dead "N more" cell.  Keep the same bounded popup, but retain every entry
  # in pages that can be reached with the mouse wheel (an event the panel loop
  # already consumed rather than replayed).
  var capacity = max([1, height * columns])
  var pages = max([1, (total + capacity - 1) / capacity])
  var page = min([pages - 1, max([0, requested_page])])
  var first = page * capacity
  var last = min([total - 1, first + capacity - 1])

  var cells: list<dict<any>> = []
  var shown = entries[first : last]
  for entry in shown
    add(cells, Cell(entry, key_width, desc_width, separator))
  endfor

  # Column major: reading down a column follows the sort order.
  var lines: list<dict<any>> = []
  for row in range(height)
    var text = ''
    var props: list<dict<any>> = []
    for column in range(columns)
      var index = column * height + row
      if index >= len(cells)
        continue
      endif
      var cell = cells[index]
      if !empty(text)
        text ..= repeat(' ', GAP)
      endif
      var offset = strlen(text)
      text ..= cell.text
      for prop in cell.props
        add(props, {col: prop.col + offset, length: prop.length, type: prop.type})
      endfor
      var padding = cell_width - cell.width
      if padding > 0 && column < columns - 1
        text ..= repeat(' ', padding)
      endif
    endfor
    if !empty(text)
      add(lines, {text: text, props: filter(props, (_, p) => p.length > 0)})
    endif
  endfor
  return {lines: lines, page: page, pages: pages}
enddef

def PopupOptions(title: string, height: number): dict<any>
  var border = get(g:, 'simplewhichkey_border', 1) ? [1, 1, 1, 1] : [0, 0, 0, 0]
  var position = get(g:, 'simplewhichkey_position', 'bottom')
  var options = {
    line: 0,
    col: 1,
    minwidth: &columns - 2,
    maxwidth: &columns - 2,
    zindex: 300,
    border: border,
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    borderhighlight: ['SimpleWhichKeyBorder'],
    padding: [0, 1, 0, 1],
    highlight: 'SimpleWhichKeyNormal',
    title: ' ' .. title .. ' ',
    mapping: false,
    drag: false,
    scrollbar: false,
    pos: 'topleft',
    wrap: false,
  }
  var frame = height + (border[0] + border[2]) + 2
  if position ==# 'top'
    options.line = 1
  elseif position ==# 'center'
    options.line = max([1, (&lines - frame) / 2])
  else
    options.pos = 'botleft'
    options.line = &lines - &cmdheight - (&laststatus > 0 ? 0 : 0)
  endif
  return options
enddef

export def Show(title: string, entries: list<dict<any>>, level_id: string = '')
  if empty(entries)
    Close()
    return
  endif
  EnsureProps()
  # The visible title is presentation, not identity: normal and visual mode
  # can show the same label, and termcode spellings may render alike. Start()
  # supplies mode + raw sequence; direct API callers fall back to the title.
  var identity = level_id ==# '' ? title : level_id
  if identity !=# current_level
    if current_level !=# ''
      pages_by_level[current_level] = current_page
    endif
    current_level = identity
    current_page = get(pages_by_level, identity, 0)
  endif
  var available = &columns - 6
  var layout = Layout(SortEntries(entries), max([20, available]), current_page)
  current_page = layout.page
  current_pages = layout.pages
  pages_by_level[identity] = current_page
  var display_title = title
  if current_pages > 1
    display_title ..= printf(' [%d/%d PgUp/PgDn]', current_page + 1, current_pages)
  endif
  var options = PopupOptions(display_title, len(layout.lines))
  if popup_id > 0 && !empty(popup_getoptions(popup_id))
    popup_settext(popup_id, layout.lines)
    popup_setoptions(popup_id, options)
  else
    popup_id = popup_create(layout.lines, options)
  endif
  redraw
enddef


export def Scroll(direction: number): bool
  if direction == 0 || current_pages <= 1
    return false
  endif
  var next = min([current_pages - 1, max([0, current_page + direction])])
  current_page = next
  if current_level !=# ''
    pages_by_level[current_level] = current_page
  endif
  # True means paging is active and the input should be consumed, including at
  # a boundary. This prevents a second PageDown on the last page from being
  # replayed as an unrelated Normal-mode command.
  return true
enddef

export def Close()
  if popup_id > 0
    popup_close(popup_id)
    popup_id = 0
    redraw
  endif
  current_level = ''
  current_page = 0
  current_pages = 1
  pages_by_level = {}
enddef

export def Visible(): bool
  return popup_id > 0 && !empty(popup_getoptions(popup_id))
enddef
