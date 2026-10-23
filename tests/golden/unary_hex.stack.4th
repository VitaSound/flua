\ ( v -- r )
: negate_it 
negate 
;
\ ( n -- r )
: offset 
$10 + 
;
\ ( n -- r )
: shift 
$FF * 
;
