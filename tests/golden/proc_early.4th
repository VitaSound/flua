\ @proc
\ ( x -- )
: clear { x }
  x 0 < if 
    exit 
  then 
  0 to x 
;
