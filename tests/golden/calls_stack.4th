\ вызовы других слов в выражениях
\ @stack
\ ( n -- r )
: twice 
  2 * 
;
\ @stack
\ ( n -- r )
: four 
  dup twice swap twice + 
;
\ @stack
\ ( -- r )
: zero 
  0 
;
