\ ( x y z -- r )
: calc { x y z }
x y z * + 
;
\ ( x y z -- r )
: grouped { x y z }
x y + z * 
;
