\ ( -- r1 r2 r3 )
: demo { | m xs vt v f ok t a z }
  hashmap-new >r 
  r> to m 
  TM-STR s\" k" TM-INT 7 0 m hashmap-set 
  ulist-new >r 
  TM-INT 2 0 r@ ulist-add 
  TM-INT 1 0 r@ ulist-add 
  r> to xs 
  0 TM-INT 5 0 xs ulist-set-term 
  TM-STR s\" k" m hashmap-get to ok to f to v to vt 
  0 xs ulist-nth-term to z to a to t 
  v ok a 
;
