; extends

; Show a labelled link as its label: [[projects/atlas#risks|Atlas risks]] reads
; as "Atlas risks". Takes effect with 'conceallevel' 2 or 3; the cursor line is
; revealed per 'concealcursor'.
(link
  "[[" @conceal
  (link_target) @conceal
  "|" @conceal
  (link_label)
  "]]" @conceal
  (#set! conceal ""))
