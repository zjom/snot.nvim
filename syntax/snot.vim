" Simple Note Format (NOTE_SPEC.md)

if exists("b:current_syntax")
  finish
endif

syn case match

" Inline content (section 8). Later definitions win when several start at the
" same place, so verbatim spans come last.
syn match snotEscape /\\[!-\/:-@[-`{-~]/
syn match snotToken /\%(^\|\s\||\)\@1<=@[a-z][a-z0-9_-]*\%(:\%(\[\%(\\.\|[^\\\]]\)*\]\|\%(\\.\|[^[:space:]|\\]\)\+\)\)\?/
syn match snotLink /\[\[\%(\\.\|[^\\\]]\|\]\]\@!\)\+\]\]/
syn match snotBold /\%(^\|[[:space:][:punct:]]\)\@1<=\*\S\%(.\{-}\S\)\?\*\%($\|[[:space:][:punct:]]\)\@=/ contains=snotUnderline,snotToken,snotLink,snotCode,snotMath,snotEscape
syn match snotUnderline /\%(^\|[[:space:][:punct:]]\)\@1<=_\S\%(.\{-}\S\)\?_\%($\|[[:space:][:punct:]]\)\@=/ contains=snotBold,snotToken,snotLink,snotCode,snotMath,snotEscape
syn match snotMath /\$\S\%(.\{-}\S\)\?\$\d\@!/
syn region snotCode start=/\z(`\+\)/ end=/\z1/ oneline

syn cluster snotInline contains=snotEscape,snotToken,snotLink,snotBold,snotUnderline,snotMath,snotCode

" Line kinds (section 2.2)
syn match snotHeading /^#\{1,6} .*$/ contains=@snotInline
syn match snotListMarker /^\s*\%(-\|\d\+\.\) / nextgroup=snotTaskOpen,snotTaskDone,snotTaskCancelled
syn match snotTaskOpen /\[ \]\%( \|$\)\@=/ contained
syn match snotTaskDone /\[x\]\%( \|$\)\@=/ contained
syn match snotTaskCancelled /\[-\]\%( \|$\)\@=/ contained
syn match snotTableRow /^\s*|.*$/ contains=@snotInline,snotTablePipe
syn match snotTablePipe /|/ contained
syn match snotTableSeparator /^\s*|\%(\s*-\+\s*|\)*\s*-\+\s*|\=\s*$/

" Verbatim blocks (section 9.1)
syn region snotCodeBlock start=/^\s*\z(```\+\)/ end=/^\s*\z1`*\s*$/ keepend
syn region snotMathBlock start=/^\s*\$\$\s*$/ end=/^\s*\$\$\s*$/ keepend

" Blocks can be long and fences look alike, so parse from the top.
syn sync fromstart

hi def link snotHeading Title
hi def link snotToken Identifier
hi def link snotLink Underlined
hi def link snotEscape SpecialChar
hi def link snotCode String
hi def link snotCodeBlock String
hi def link snotMath Special
hi def link snotMathBlock Special
hi def link snotListMarker Statement
hi def link snotTaskOpen Todo
hi def link snotTaskDone Comment
hi def link snotTaskCancelled Comment
hi def link snotTablePipe Delimiter
hi def link snotTableSeparator Delimiter
hi def snotBold term=bold cterm=bold gui=bold
hi def snotUnderline term=underline cterm=underline gui=underline

let b:current_syntax = "snot"
