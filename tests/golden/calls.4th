\ ( n -- r )
: twice { n }
n 2 * 
;
\ ( n -- r )
: four { n }
n twice n twice + 
;
\ ( -- r )
: zero 
0 
;
