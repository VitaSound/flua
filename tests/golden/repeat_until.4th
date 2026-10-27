\ ( n -- r )
: until_zero { n }
  begin 
    n 1 - to n 
  n 0 = until 
  n 
;
