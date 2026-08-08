# Changelog

All notable changes to SimpleWhichKey are documented here.

## Unreleased - 2026-08-07

### Panel evolution

- `g:simplewhichkey_delay` now also accepts a dictionary keyed by prefix
  notation, optionally scoped to a mode (`o:g`), with a `default` entry. A
  prefix that other mappings extend has already cost a full `'timeoutlen'` and
  wants `0`; one Vim dispatches instantly wants a real pause. The plain number
  form is unchanged. `:SimpleWhichKeyHealth` now prints the delay every hooked
  prefix resolves to, next to its mapping and built-in counts.

- Operator-pending mode is now first-class: `g`, `[` and `]` are hinted by
  default after operators, and `:SimpleWhichKeyOperator` exposes the mode
  explicitly. The expression hook leaves Vim's original operator, multiplied
  count and register live while a motion is selected, preserving `g@`, dot
  repeat and clipboard semantics. Exact prefix omaps still win; discovered
  recursive, `<Plug>` and expr omaps continue to execute after slow selection.

- Page position is now remembered per visited level for the lifetime of one
  key sequence. Entering a group from an overflow page and pressing `<BS>`
  returns to that page instead of resetting the parent to page one.
- Overflow entries are now retained on numbered pages instead of being
  replaced by an inert "N more" row. The popup title reports the current page,
  and the mouse wheel moves through pages.
- `<PageUp>` / `<PageDown>` provide a terminal-safe fallback when `'mouse'` is
  disabled. The title advertises the controls, while an explicit mapping for
  either Page key always takes precedence at that level.
- Added regression coverage for page layout, page navigation, and scroll-event
  classification.

## 0.1.0

- Initial Vim9 release: live hints for configured prefixes, Vim built-in
  command tables, mapping discovery, dynamic registers/marks, descriptions,
  popup layout, and transparent key replay.
