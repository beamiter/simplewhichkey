" Syntax for the :SimpleWhichKeyList scratch buffer.
"
" Three columns separated by two spaces: the key sequence, its description and
" where the description came from.  Only the first and last columns are
" anchored, because a description may hold register contents -- arbitrary
" text, spaces included -- and must not be able to break the line it sits on.

if exists('b:current_syntax')
  finish
endif

syntax match simpleWhichKeyListComment '^".*$'
syntax match simpleWhichKeyListSource '\s\+\%(builtin\|dynamic\|map\|prefix\)\s*$'
syntax match simpleWhichKeyListGroup '^\S\+\s\{2,}+\S.*$'
syntax match simpleWhichKeyListKey '^\S\+'

highlight default link simpleWhichKeyListComment Comment
highlight default link simpleWhichKeyListKey Identifier
highlight default link simpleWhichKeyListGroup Function
highlight default link simpleWhichKeyListSource Comment

let b:current_syntax = 'simplewhichkeylist'
