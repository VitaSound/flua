\ ( -- r1 r2 r3 r4 )
: demo { | m vt v1 v2 ok t2 x y ok2 }
  hashmap-new >r 
  TM-STR s\" a" TM-INT 1 0 r@ hashmap-set 
  TM-STR s\" b" TM-STR s\" x" r@ hashmap-set 
  r> to m 
  TM-STR s\" a" m hashmap-get to ok to v2 to v1 to vt 
  TM-STR s\" c" TM-INT 3 0 m hashmap-set 
  TM-STR s\" c" m hashmap-get to ok2 to y to x to t2 
  v1 ok x ok2 
;
