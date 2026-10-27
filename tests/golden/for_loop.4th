\ ( n -- r )
: sum_to { n | s }
  0 to s 
  n 1+ 1 ?do 
    s i + to s 
  loop 
  s 
;
