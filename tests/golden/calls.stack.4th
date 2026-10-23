\ вызовы других слов в выражениях
\ ( n -- r )
: twice 
2 * 
;
\ ( n -- r )
: four 
dup twice swap twice + 
;
\ ( -- r )
: zero 
0 
;
