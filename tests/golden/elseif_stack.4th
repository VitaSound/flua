\ elseif: цепочка условий, else опционален
\ @stack
\ ( n -- r )
: sign 
  dup 0 > if 
    1 nip exit 
  else 
    0 < if 
      1 negate exit 
    else 
      0 exit 
    then 
  then 
;
\ @stack
\ ( s -- r )
: grade 
  dup 90 >= if 
    4 nip exit 
  else 
    dup 75 >= if 
      3 nip exit 
    else 
      60 >= if 
        2 exit 
      else 
        1 exit 
      then 
    then 
  then 
;
