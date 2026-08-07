# Changelog

All notable changes to SimpleWhichKey are documented here.

## Unreleased - 2026-08-07

### Panel evolution

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
