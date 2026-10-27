\ elseif: цепочка условий, else опционален
\ ( n -- r )
: sign { n }
  n 0 > if 
    1 exit 
  else 
    n 0 < if 
      1 negate exit 
    else 
      0 exit 
    then 
  then 
;
\ ( s -- r )
: grade { s }
  s 90 >= if 
    4 exit 
  else 
    s 75 >= if 
      3 exit 
    else 
      s 60 >= if 
        2 exit 
      else 
        1 exit 
      then 
    then 
  then 
;
