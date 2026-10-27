\ ( -- r1 r2 r3 )
: demo { | xs t0 a z0 t1 b z1 t2 c z2 }
  ulist-new >r 
  TM-INT 30 0 r@ ulist-add 
  TM-INT 20 0 r@ ulist-add 
  TM-INT 10 0 r@ ulist-add 
  r> to xs 
  0 xs ulist-nth-term to z0 to a to t0 
  1 xs ulist-nth-term to z1 to b to t1 
  2 TM-INT 99 0 xs ulist-set-term 
  2 xs ulist-nth-term to z2 to c to t2 
  a b c 
;
